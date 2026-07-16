cmake_minimum_required(VERSION 3.22.1)

project("core")

message("CMAKE_SOURCE_DIR ${CMAKE_SOURCE_DIR}")

message("CMAKE_BUILD_TYPE ${CMAKE_BUILD_TYPE}")


if (NOT "${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
    add_compile_options(-O3 -flto -g0 -fno-exceptions -fno-rtti)
    add_link_options(-flto -Wl,--gc-sections,--strip-all)
endif ()

set(LIB_CLASH_PATH "${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libclash.so")
set(LIB_CLASH_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/../cpp/includes/${ANDROID_ABI}")
set(LIB_CLASH_HEADER_PATH "${LIB_CLASH_INCLUDE_DIR}/libclash.h")
set(BRIDE_HEADER_PATH "${LIB_CLASH_INCLUDE_DIR}/bride.h")
set(LIB_CLASH_STAMP_PATH "${LIB_CLASH_INCLUDE_DIR}/.libclash.stamp")

if (EXISTS "${LIB_CLASH_STAMP_PATH}")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
            "${LIB_CLASH_STAMP_PATH}")
endif ()

message("LIB_CLASH_PATH ${LIB_CLASH_PATH}")
set(MISSING_LIB_CLASH_ARTIFACTS)
foreach (ARTIFACT
        "${LIB_CLASH_PATH}"
        "${LIB_CLASH_HEADER_PATH}"
        "${BRIDE_HEADER_PATH}")
    if (NOT EXISTS "${ARTIFACT}")
        list(APPEND MISSING_LIB_CLASH_ARTIFACTS "${ARTIFACT}")
    endif ()
endforeach ()
if (MISSING_LIB_CLASH_ARTIFACTS)
    list(JOIN MISSING_LIB_CLASH_ARTIFACTS "\n  " MISSING_LIB_CLASH_ARTIFACTS_MESSAGE)
    message(FATAL_ERROR
            "Missing required Go core artifacts for ABI ${ANDROID_ABI}:\n  ${MISSING_LIB_CLASH_ARTIFACTS_MESSAGE}")
endif ()

message("Found libclash.so and headers for ABI ${ANDROID_ABI}")
add_library(${CMAKE_PROJECT_NAME} SHARED
        jni_helper.cpp
        core.cpp)
add_library(clash SHARED IMPORTED)
set_target_properties(clash PROPERTIES
        IMPORTED_LOCATION "${LIB_CLASH_PATH}"
        IMPORTED_NO_SONAME TRUE)
target_compile_definitions(${CMAKE_PROJECT_NAME} PRIVATE LIBCLASH)
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
        "${LIB_CLASH_INCLUDE_DIR}")
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE clash)
