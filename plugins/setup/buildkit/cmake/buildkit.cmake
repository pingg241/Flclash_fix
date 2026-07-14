# buildkit.cmake — Build Go core as part of the native Linux/Windows build
#
# Include this from a plugin's CMakeLists.txt and call:
#   apply_buildkit()
#
# This adds a custom command that runs build_tool before the native target is linked.

# Resolve at include-time so CMAKE_CURRENT_LIST_DIR is this file's directory
get_filename_component(BUILDKIT_DIR "${CMAKE_CURRENT_LIST_DIR}" DIRECTORY)

function(_resolve_buildkit_windows_dart FLUTTER_CONFIG OUT_VAR)
  if(NOT EXISTS "${FLUTTER_CONFIG}")
    message(FATAL_ERROR
      "Flutter generated configuration not found at ${FLUTTER_CONFIG}. "
      "Run the Windows build through Flutter so the SDK can be resolved.")
  endif()
  include("${FLUTTER_CONFIG}")
  set(_dart_executable
    "${FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart.exe")
  if(NOT EXISTS "${_dart_executable}")
    message(FATAL_ERROR
      "Dart executable not found at ${_dart_executable}. "
      "The generated Flutter SDK configuration is invalid.")
  endif()
  set(${OUT_VAR} "${_dart_executable}" PARENT_SCOPE)
endfunction()

function(apply_buildkit)
  if(WIN32)
    set(_launcher "${BUILDKIT_DIR}/run_build_tool.cmd")
  else()
    set(_launcher "${BUILDKIT_DIR}/run_build_tool.sh")
  endif()

  # Project root is one level up from CMAKE_SOURCE_DIR (the top-level CMakeLists.txt
  # lives in linux/ or windows/, so project root is the parent).
  get_filename_component(PROJECT_ROOT "${CMAKE_SOURCE_DIR}" DIRECTORY)

  if(WIN32)
    # Flutter's generated configuration is the authoritative SDK selected by
    # the invoking Flutter tool. It remains available when the caller has no
    # FLUTTER_ROOT environment variable and safely preserves spaces in paths.
    set(_flutter_config
      "${PROJECT_ROOT}/windows/flutter/ephemeral/generated_config.cmake")
    _resolve_buildkit_windows_dart(
      "${_flutter_config}" _dart_executable)
  endif()

  # The output files the build_tool produces. Keep the helper in the build graph
  # as well: otherwise a stale debug/release helper can survive a core rebuild.
  if(WIN32)
    set(_output "${PROJECT_ROOT}/libclash/windows/FlClashCore.exe")
    set(_helper_output "${PROJECT_ROOT}/libclash/windows/FlClashHelperService.exe")
    set(_platform_args "windows")
  else()
    set(_output "${PROJECT_ROOT}/libclash/linux/FlClashCore")
    set(_helper_output "")
    set(_platform_args "linux")
  endif()

  # Build inputs are explicit so edits inside the Meta submodule, the Go
  # wrapper, build tool, or Windows helper invalidate the native artifact.
  file(GLOB_RECURSE _build_inputs CONFIGURE_DEPENDS
    "${PROJECT_ROOT}/core/*.go"
    "${PROJECT_ROOT}/core/*.s"
    "${PROJECT_ROOT}/core/*.c"
    "${PROJECT_ROOT}/core/*.h"
    "${PROJECT_ROOT}/core/*.crt"
    "${PROJECT_ROOT}/core/*.mod"
    "${PROJECT_ROOT}/core/*.sum"
    "${PROJECT_ROOT}/build_config.yaml"
    "${PROJECT_ROOT}/plugins/setup/buildkit/build_tool/*.dart"
    "${PROJECT_ROOT}/plugins/setup/buildkit/build_tool/pubspec.*"
    "${PROJECT_ROOT}/plugins/setup/buildkit/build_tool/build_config.yaml"
    "${PROJECT_ROOT}/plugins/setup/buildkit/run_build_tool.sh"
    "${PROJECT_ROOT}/plugins/setup/buildkit/run_build_tool.cmd"
  )
  if(WIN32)
    file(GLOB_RECURSE _helper_inputs CONFIGURE_DEPENDS
      "${PROJECT_ROOT}/services/helper/*.rs"
      "${PROJECT_ROOT}/services/helper/Cargo.toml"
      "${PROJECT_ROOT}/services/helper/Cargo.lock"
    )
    list(APPEND _build_inputs ${_helper_inputs})
  endif()
  list(FILTER _build_inputs EXCLUDE REGEX "[/\\\\](target|build|\\.dart_tool)[/\\\\]")
  list(FILTER _build_inputs EXCLUDE REGEX "[/\\\\]test[/\\\\]|_test\\.go$")

  get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
  if(IS_MULTICONFIG)
    # CMAKE_CFG_INTDIR expands to $(Configuration) for Visual Studio, keeping
    # Debug, Profile, and Release stamps independent without requiring a newer
    # CMake generator-expression in OUTPUT.
    set(_stamp "${CMAKE_CURRENT_BINARY_DIR}/buildkit/${CMAKE_CFG_INTDIR}/${_platform_args}.stamp")
    set(_config_stamps
      "${CMAKE_CURRENT_BINARY_DIR}/buildkit/Debug/${_platform_args}.stamp"
      "${CMAKE_CURRENT_BINARY_DIR}/buildkit/Profile/${_platform_args}.stamp"
      "${CMAKE_CURRENT_BINARY_DIR}/buildkit/Release/${_platform_args}.stamp"
    )
  else()
    string(TOLOWER "${CMAKE_BUILD_TYPE}" _config_name)
    if(_config_name STREQUAL "")
      set(_config_name "debug")
    endif()
    set(_stamp "${CMAKE_CURRENT_BINARY_DIR}/buildkit/${_platform_args}-${_config_name}.stamp")
    set(_config_stamps
      "${CMAKE_CURRENT_BINARY_DIR}/buildkit/${_platform_args}-debug.stamp"
      "${CMAKE_CURRENT_BINARY_DIR}/buildkit/${_platform_args}-profile.stamp"
      "${CMAKE_CURRENT_BINARY_DIR}/buildkit/${_platform_args}-release.stamp"
    )
  endif()
  get_filename_component(_stamp_dir "${_stamp}" DIRECTORY)

  set(BUILDKIT_ENV
    "BUILDKIT_CONFIGURATION=$<CONFIG>"
    "PROJECT_DIR=${PROJECT_ROOT}"
  )
  if(WIN32)
    list(APPEND BUILDKIT_ENV
      "BUILDKIT_DART_EXECUTABLE=${_dart_executable}")
  endif()

  add_custom_command(
    OUTPUT
      "${_stamp}"
      "${_output}"
      ${_helper_output}
    COMMAND ${CMAKE_COMMAND} -E env ${BUILDKIT_ENV}
    "${_launcher}" ${_platform_args}
    # Desktop artifacts share their install path. Invalidate other configuration
    # witnesses after a successful overwrite so Debug -> Release -> Debug cannot
    # accept the previous mode's helper.
    COMMAND ${CMAKE_COMMAND} -E rm -f ${_config_stamps}
    COMMAND ${CMAKE_COMMAND} -E make_directory "${_stamp_dir}"
    COMMAND ${CMAKE_COMMAND} -E touch "${_stamp}"
    DEPENDS ${_build_inputs}
    WORKING_DIRECTORY "${PROJECT_ROOT}"
    COMMENT "Building Go core via buildkit..."
    VERBATIM
  )

  add_custom_target(setup_buildkit_build
    DEPENDS "${_stamp}" "${_output}" ${_helper_output})
endfunction()
