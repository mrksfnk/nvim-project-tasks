cmake_minimum_required(VERSION 3.20)
project(test_app_no_presets LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_executable(test_app src/main.cpp)

# Install rules
install(TARGETS test_app
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

# Enable testing with CTest
enable_testing()
add_test(NAME test_app_runs COMMAND test_app)
add_test(NAME test_app_returns_zero COMMAND test_app)
set_tests_properties(test_app_returns_zero PROPERTIES WILL_FAIL FALSE)

# CPack configuration
set(CPACK_PACKAGE_NAME "test_app_no_presets")
set(CPACK_PACKAGE_VERSION "1.0.0")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Test application without presets")
set(CPACK_GENERATOR "TGZ")
include(CPack)
