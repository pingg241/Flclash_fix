if(NOT DEFINED BUILDKIT_CMAKE)
  message(FATAL_ERROR "BUILDKIT_CMAKE is required")
endif()
if(NOT DEFINED TEST_ROOT OR NOT DEFINED DART_EXECUTABLE)
  message(FATAL_ERROR "TEST_ROOT and DART_EXECUTABLE are required")
endif()

include("${BUILDKIT_CMAKE}")
file(MAKE_DIRECTORY "${TEST_ROOT}/windows/flutter/ephemeral")
file(TO_CMAKE_PATH "${DART_EXECUTABLE}" _expected_dart)
get_filename_component(_dart_bin "${_expected_dart}" DIRECTORY)
get_filename_component(_dart_sdk "${_dart_bin}/../../../.." ABSOLUTE)
file(WRITE "${TEST_ROOT}/windows/flutter/ephemeral/generated_config.cmake"
  "set(FLUTTER_ROOT \"${_dart_sdk}\")\n")

_resolve_buildkit_windows_dart(
  "${TEST_ROOT}/windows/flutter/ephemeral/generated_config.cmake" _actual_dart)
if(NOT _actual_dart STREQUAL _expected_dart)
  message(FATAL_ERROR
    "Resolved Dart mismatch: expected '${_expected_dart}', got '${_actual_dart}'")
endif()
