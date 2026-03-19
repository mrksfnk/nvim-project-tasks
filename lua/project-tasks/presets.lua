-- project-tasks/presets.lua
-- CMake presets parsing and File API integration
local M = {}

-- Cache for loaded presets data
M._cache = {}

--- Load and merge CMakePresets.json + CMakeUserPresets.json
---@param root string Project root path
---@return table|nil presets List of configure presets
function M.load(root)
	local presets = {}
	local presets_map = {}

	-- Load base presets
	local base = M.read_presets_file(root .. "/CMakePresets.json")
	if base then
		M.merge_presets(presets_map, base, "configure")
	end

	-- Load user presets (higher priority)
	local user = M.read_presets_file(root .. "/CMakeUserPresets.json")
	if user then
		M.merge_presets(presets_map, user, "configure")
	end

	if not base and not user then
		return nil
	end

	-- Resolve inheritance and filter hidden
	for name, preset in pairs(presets_map) do
		if not preset.hidden then
			local resolved = M.resolve_preset(preset, presets_map, root)
			table.insert(presets, resolved)
		end
	end

	-- Sort by name
	table.sort(presets, function(a, b)
		return a.name < b.name
	end)

	-- Cache the raw data for build presets lookup
	M._cache[root] = { base = base, user = user }

	return presets
end

--- Check if any build preset exists
---@param root string Project root path
---@return boolean
function M.has_build_preset(root)
	local cached = M._cache[root]
	if not cached then
		-- Load if not cached
		M.load(root)
		cached = M._cache[root]
	end

	if not cached then
		return false
	end

	-- Check build presets in both base and user
	for _, data in ipairs({ cached.base, cached.user }) do
		if data and data.buildPresets and #data.buildPresets > 0 then
			return true
		end
	end

	return false
end

--- Get build presets for a configure preset
---@param root string Project root path
---@param configure_preset_name string|nil Optional filter by configure preset
---@return table build_presets
function M.get_build_presets(root, configure_preset_name)
	local cached = M._cache[root]
	if not cached then
		M.load(root)
		cached = M._cache[root]
	end

	if not cached then
		return {}
	end

	local build_presets = {}
	local build_presets_map = {}

	-- Merge by name first (user presets override base presets).
	for _, data in ipairs({ cached.base, cached.user }) do
		if data and data.buildPresets then
			for _, bp in ipairs(data.buildPresets) do
				build_presets_map[bp.name] = bp
			end
		end
	end

	for _, bp in pairs(build_presets_map) do
		if not bp.hidden then
			local resolved = M.resolve_inheritance(bp, build_presets_map, {})
			if not configure_preset_name or resolved.configurePreset == configure_preset_name then
				table.insert(build_presets, resolved)
			end
		end
	end

	table.sort(build_presets, function(a, b)
		return a.name < b.name
	end)

	return build_presets
end

--- Read a presets file
---@param path string
---@return table|nil
function M.read_presets_file(path)
	local stat = vim.uv.fs_stat(path)
	if not stat then
		return nil
	end

	local content = vim.fn.readfile(path)
	local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
	if not ok then
		vim.notify("[project-tasks] Failed to parse: " .. path, vim.log.levels.WARN)
		return nil
	end

	return data
end

--- Merge presets from a file into the map
---@param map table
---@param data table
---@param preset_type string "configure" or "build"
function M.merge_presets(map, data, preset_type)
	local key = preset_type .. "Presets"
	if data[key] then
		for _, preset in ipairs(data[key]) do
			map[preset.name] = preset
		end
	end
end

--- Resolve preset inheritance and expand macros
---@param preset table
---@param all_presets table
---@param root string
---@return table
function M.resolve_preset(preset, all_presets, root)
	-- First resolve inheritance without macro expansion
	local resolved = M.resolve_inheritance(preset, all_presets, {})

	-- Provide sensible default binaryDir if not specified
	-- This prevents in-source builds when preset doesn't define binaryDir
	if not resolved.binaryDir then
		resolved.binaryDir = "build/${presetName}"
	end

	-- Expand macros using the final preset's name (not parent's)
	if resolved.binaryDir then
		resolved.binaryDir = M.expand_macros(resolved.binaryDir, {
			sourceDir = root,
			presetName = resolved.name,
		})
	end

	return resolved
end

--- Resolve preset inheritance chain (without macro expansion)
---@param preset table
---@param all_presets table
---@param visited table Already visited presets (cycle detection)
---@return table
function M.resolve_inheritance(preset, all_presets, visited)
	local resolved = vim.deepcopy(preset)

	-- Cycle detection
	if visited[preset.name] then
		return resolved
	end
	visited[preset.name] = true

	-- Resolve inheritance chain
	if preset.inherits then
		local parents = type(preset.inherits) == "table" and preset.inherits or { preset.inherits }
		for _, parent_name in ipairs(parents) do
			local parent = all_presets[parent_name]
			if parent then
				local resolved_parent = M.resolve_inheritance(parent, all_presets, visited)
				-- Don't inherit hidden property - it applies only to the preset itself
				resolved_parent.hidden = nil
				resolved = vim.tbl_deep_extend("keep", resolved, resolved_parent)
			end
		end
	end

	return resolved
end

--- Expand CMake preset macros like ${sourceDir}
---@param str string
---@param vars table
---@return string
function M.expand_macros(str, vars)
	return (str:gsub("%${([^}]+)}", function(macro)
		return vars[macro] or ("${" .. macro .. "}")
	end))
end

--- Get executable targets from CMake File API
---@param root string Project root
---@param binary_dir string|nil Build directory
---@return table|nil targets
function M.get_targets(root, binary_dir)
	-- Handle nil binary_dir
	if not binary_dir then
		return nil
	end

	-- Resolve binary_dir if relative
	if not binary_dir:match("^/") then
		binary_dir = root .. "/" .. binary_dir
	end

	local reply_dir = binary_dir .. "/.cmake/api/v1/reply"
	local index_path = M.find_reply_index(reply_dir)

	if not index_path then
		-- Try to create query files for next configure
		M.setup_query(binary_dir)
		-- Fallback: scan for executables in build directory
		return M.scan_for_executables(binary_dir)
	end

	local targets = M.parse_codemodel(reply_dir, index_path)
	-- If no targets from File API, try scanning
	if not targets or #targets == 0 then
		return M.scan_for_executables(binary_dir)
	end
	return targets
end

--- Scan build directory for executable files (fallback when File API unavailable)
---@param binary_dir string
---@return table|nil
function M.scan_for_executables(binary_dir)
	local targets = {}

	-- Check if directory exists
	if not vim.uv.fs_stat(binary_dir) then
		return nil
	end

	-- On macOS, look for .app bundles first
	local apps = vim.fn.glob(binary_dir .. "/*.app", false, true)
	for _, app_path in ipairs(apps) do
		local name = vim.fn.fnamemodify(app_path, ":t:r") -- Get name without .app
		table.insert(targets, {
			name = name,
			path = app_path,
			type = "EXECUTABLE",
		})
	end

	-- Also look for regular executables (non-hidden, executable files)
	local files = vim.fn.readdir(binary_dir)
	for _, f in ipairs(files) do
		local path = binary_dir .. "/" .. f
		local stat = vim.uv.fs_stat(path)
		-- Check if it's an executable file (not directory, not hidden, has execute permission)
		if stat and stat.type == "file" and not f:match("^%.") and not f:match("%.") then
			-- On Unix, check if file is executable
			local mode = stat.mode
			if mode and bit.band(mode, 0x49) ~= 0 then -- 0x49 = 0111 (user/group/other execute)
				table.insert(targets, {
					name = f,
					path = path,
					type = "EXECUTABLE",
				})
			end
		end
	end

	return #targets > 0 and targets or nil
end

--- Find the latest reply index file
---@param reply_dir string
---@return string|nil
function M.find_reply_index(reply_dir)
	local stat = vim.uv.fs_stat(reply_dir)
	if not stat then
		return nil
	end

	local files = vim.fn.readdir(reply_dir)
	local latest = nil

	for _, f in ipairs(files) do
		if f:match("^index%-.*%.json$") then
			if not latest or f > latest then
				latest = f
			end
		end
	end

	return latest and (reply_dir .. "/" .. latest)
end

--- Parse codemodel to extract executable targets
---@param reply_dir string
---@param index_path string
---@return table
function M.parse_codemodel(reply_dir, index_path)
	local targets = {}

	-- Read index
	local content = vim.fn.readfile(index_path)
	local ok, index = pcall(vim.json.decode, table.concat(content, "\n"))
	if not ok then
		return targets
	end

	-- Find codemodel reference
	local codemodel_file = nil
	for _, obj in ipairs(index.objects or {}) do
		if obj.kind == "codemodel" then
			codemodel_file = reply_dir .. "/" .. obj.jsonFile
			break
		end
	end

	if not codemodel_file then
		return targets
	end

	-- Read codemodel
	content = vim.fn.readfile(codemodel_file)
	ok, codemodel = pcall(vim.json.decode, table.concat(content, "\n"))
	if not ok then
		return targets
	end

	-- Extract targets from configurations
	for _, config in ipairs(codemodel.configurations or {}) do
		for _, target_ref in ipairs(config.targets or {}) do
			local target_file = reply_dir .. "/" .. target_ref.jsonFile
			local target = M.parse_target(target_file, reply_dir)
			if target and target.type == "EXECUTABLE" then
				table.insert(targets, {
					name = target.name,
					path = target.path,
					type = target.type,
				})
			end
		end
	end

	return targets
end

--- Parse individual target file
---@param path string
---@param reply_dir string
---@return table|nil
function M.parse_target(path, reply_dir)
	local content = vim.fn.readfile(path)
	local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
	if not ok then
		return nil
	end

	local artifact_path = nil
	if data.artifacts and data.artifacts[1] then
		artifact_path = data.artifacts[1].path
		-- Make absolute if needed
		if artifact_path and not artifact_path:match("^/") then
			-- Path is relative to build directory
			-- reply_dir is <build_dir>/.cmake/api/v1/reply
			-- Go up 4 levels: reply -> v1 -> api -> .cmake -> build_dir
			local build_dir = vim.fn.fnamemodify(reply_dir, ":h:h:h:h")
			artifact_path = build_dir .. "/" .. artifact_path
		end
	end

	return {
		name = data.name,
		type = data.type,
		path = artifact_path,
	}
end

--- Setup CMake File API query files
---@param binary_dir string
function M.setup_query(binary_dir)
	local query_dir = binary_dir .. "/.cmake/api/v1/query/client-project-tasks"

	-- Try to create directory (may fail on read-only paths)
	local ok = pcall(function()
		vim.fn.mkdir(query_dir, "p")
	end)

	if not ok then
		return
	end

	-- Create query files (empty files trigger the queries)
	local queries = { "codemodel-v2", "cache-v2", "toolchains-v1" }
	for _, q in ipairs(queries) do
		local f = io.open(query_dir .. "/" .. q, "w")
		if f then
			f:close()
		end
	end
end

--- Normalize binary_dir to an absolute path
---@param root string
---@param binary_dir string
---@return string|nil
function M.resolve_binary_dir(root, binary_dir)
	if not binary_dir or binary_dir == "" then
		return nil
	end
	if vim.startswith(binary_dir, "/") then
		return binary_dir
	end
	return root .. "/" .. binary_dir
end

local function is_windows()
	local uname = vim.uv.os_uname()
	return uname and uname.sysname == "Windows_NT"
end

local function is_truthy(val)
	if type(val) == "boolean" then
		return val
	end
	if type(val) ~= "string" then
		return false
	end
	local v = val:upper()
	return v == "ON" or v == "1" or v == "TRUE" or v == "YES"
end

--- Find the latest File API cache reply file
---@param binary_dir string
---@return string|nil
function M.find_latest_cache_reply(binary_dir)
	local reply_dir = binary_dir .. "/.cmake/api/v1/reply"
	local stat = vim.uv.fs_stat(reply_dir)
	if not stat then
		return nil
	end

	local files = vim.fn.readdir(reply_dir)
	local latest = nil
	for _, f in ipairs(files) do
		if f:match("^cache%-.*%.json$") then
			if not latest or f > latest then
				latest = f
			end
		end
	end

	return latest and (reply_dir .. "/" .. latest)
end

--- Determine whether CMAKE_EXPORT_COMPILE_COMMANDS is enabled
---@param root string
---@param binary_dir string
---@return boolean
function M.is_compile_commands_exported(root, binary_dir)
	local bdir = M.resolve_binary_dir(root, binary_dir)
	if not bdir then
		return false
	end

	-- Prefer File API cache data if available
	local cache_path = M.find_latest_cache_reply(bdir)
	if cache_path then
		local content = vim.fn.readfile(cache_path)
		local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
		if ok and data and data.entries then
			for _, entry in ipairs(data.entries) do
				if entry.key == "CMAKE_EXPORT_COMPILE_COMMANDS" then
					return is_truthy(entry.value)
				end
			end
		end
	end

	-- Fallback to CMakeCache.txt parsing
	local cache_txt = bdir .. "/CMakeCache.txt"
	if vim.uv.fs_stat(cache_txt) then
		for _, line in ipairs(vim.fn.readfile(cache_txt)) do
			local key, value = line:match("^([^:#=]+):[^=]*=(.*)$")
			if key == "CMAKE_EXPORT_COMPILE_COMMANDS" then
				return is_truthy(value)
			end
		end
	end

	return false
end

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()
	return data
end

local function write_file(path, data)
	local f = io.open(path, "wb")
	if not f then
		return false
	end
	f:write(data)
	f:close()
	return true
end

local function remove_file(path)
	-- Ignore errors if file doesn't exist
	pcall(vim.uv.fs_unlink, path)
end

local function read_marker(marker_path)
	local data = read_file(marker_path)
	if not data then
		return nil
	end
	return data:gsub("%s+$", "")
end

local function write_marker(marker_path, target)
	write_file(marker_path, tostring(target))
end

local function is_symlink(path)
	local stat = vim.uv.fs_lstat(path)
	return stat and stat.type == "link"
end

local function ensure_symlink(link, target, marker_path)
	-- If link already exists and points to the correct target, nothing to do
	if is_symlink(link) then
		local current = vim.uv.fs_readlink(link)
		if current == target then
			write_marker(marker_path, target)
			return true
		end
		-- Remove outdated symlink
		remove_file(link)
	end

	-- If a regular file exists and we didn't create it, don't overwrite
	if vim.uv.fs_stat(link) then
		local existing_marker = read_marker(marker_path)
		if not existing_marker then
			return false
		end
		remove_file(link)
	end

	-- Create symlink
	local ok, result = pcall(vim.uv.fs_symlink, target, link)
	if not ok or not result then
		return false
	end
	write_marker(marker_path, target)
	return true
end

local function copy_file(src, dst)
	local data = read_file(src)
	if not data then
		return false
	end
	return write_file(dst, data)
end

local function ensure_copy(link, target, marker_path)
	local marker = read_marker(marker_path)
	if vim.uv.fs_stat(link) and not marker then
		-- Do not overwrite a user-provided file
		return false
	end

	if not copy_file(target, link) then
		return false
	end
	write_marker(marker_path, target)
	return true
end

local function remove_link_and_marker(link, marker_path)
	-- Only remove if we previously managed it
	local marker = read_marker(marker_path)
	if not marker then
		return false
	end

	-- Remove link if it exists (file or symlink)
	if vim.uv.fs_stat(link) then
		remove_file(link)
	end
	remove_file(marker_path)
	return true
end

--- Synchronize project-root compile_commands.json pointer
--- Creates a symlink (Unix) or copy (Windows) to the build directory file
---@param root string
---@param binary_dir string
function M.sync_compile_commands_link(root, binary_dir)
	local bdir = M.resolve_binary_dir(root, binary_dir)
	if not bdir then
		return
	end

	local link_path = root .. "/compile_commands.json"
	local marker_path = root .. "/.project_tasks_compile_commands"

	local export_enabled = M.is_compile_commands_exported(root, binary_dir)
	local target_path = bdir .. "/compile_commands.json"

	-- If export is disabled or the target is missing, remove any existing link/copy we created.
	if not export_enabled or not vim.uv.fs_stat(target_path) then
		remove_link_and_marker(link_path, marker_path)
		return
	end

	if is_windows() then
		ensure_copy(link_path, target_path, marker_path)
	else
		ensure_symlink(link_path, target_path, marker_path)
	end
end

return M
