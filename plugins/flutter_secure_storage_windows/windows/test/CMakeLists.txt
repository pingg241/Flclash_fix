cmake_minimum_required(VERSION 3.15)
project(flutter_secure_storage_windows_test LANGUAGES CXX)

include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/b514bdc898e2951020cbdca1304b75f5950d1f59.zip
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
# Prevent overriding the parent project's compiler/linker settings on Windows.
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

enable_testing()
string(RANDOM LENGTH 32 ALPHABET 0123456789abcdef TEST_STORAGE_GUID)
set(TEST_STORAGE_PREFIX "fss_native_test_${TEST_STORAGE_GUID}_")

# Compile the plugin source directly into the test binary so that the C++
# class symbols are available without requiring DLL exports.
add_executable(flutter_secure_storage_windows_test
  flutter_secure_storage_windows_plugin_test.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../flutter_secure_storage_windows_plugin.cpp
)

# A fresh prefix is generated for every configure so native tests cannot touch
# application credentials even when a parent project defines a global prefix.
target_compile_definitions(flutter_secure_storage_windows_test PRIVATE
  FLUTTER_PLUGIN_IMPL
  FLUTTER_SECURE_STORAGE_WINDOWS_TESTING
  FLUTTER_SECURE_STORAGE_WINDOWS_TEST_PREFIX="${TEST_STORAGE_PREFIX}"
  SECURE_STORAGE_KEY_PREFIX="standalone_production_prefix_must_not_be_used_"
)

target_include_directories(flutter_secure_storage_windows_test PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(flutter_secure_storage_windows_test PRIVATE
  flutter_wrapper_plugin
  GTest::gtest_main
)

target_compile_features(flutter_secure_storage_windows_test PRIVATE cxx_std_17)

# Copy flutter_windows.dll next to the test binary so the process can load it
# both during ctest discovery (PRE_TEST) and during actual test execution.
add_custom_command(TARGET flutter_secure_storage_windows_test POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FLUTTER_LIBRARY}"
    "$<TARGET_FILE_DIR:flutter_secure_storage_windows_test>"
  COMMENT "Copying flutter_windows.dll for test runner"
)

include(GoogleTest)
# PRE_TEST defers test-case discovery to ctest runtime (not cmake build time),
# so flutter_windows.dll is already present when the binary is first executed.
gtest_discover_tests(flutter_secure_storage_windows_test
  DISCOVERY_MODE PRE_TEST
)
