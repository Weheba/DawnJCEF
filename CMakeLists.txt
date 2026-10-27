# Copyright (c) 2016 The Chromium Embedded Framework Authors. All rights
# reserved. Use of this source code is governed by a BSD-style license that
# can be found in the LICENSE file.

# OVERVIEW
#
# CMake is a cross-platform open-source build system that can generate project
# files in many different formats. It can be downloaded from
# http://www.cmake.org or installed via a platform package manager.
#
# CMake-generated project formats that have been tested with JCEF include:
#
# Linux:      Ninja, GCC 7.5.0+, Unix Makefiles
# MacOS:      Ninja, Xcode 13.3 to 16.4
# Windows:    Ninja, Visual Studio 2022
#
# Ninja is a cross-platform open-source tool for running fast builds using
# pre-installed platform toolchains (GNU, clang, Xcode or MSVC). It can be
# downloaded from http://martine.github.io/ninja/ or installed via a platform
# package manager.
#
# BUILD REQUIREMENTS
#
# The below requirements must be met to build JCEF.
#
# - CMake version 3.21 or newer.
#
# - Linux requirements:
#   Currently supported distributions include Debian 10 (Buster), Ubuntu 18
#   (Bionic Beaver), and related. Ubuntu 18.04 64-bit with GCC 7.5.0+ is
#   recommended. Newer versions will likely also work but may not have been
#   tested.
#   Required packages include:
#     build-essential
#     libgtk3.0-dev     (required by the cefclient target only)
#
# - MacOS requirements:
#   Xcode 13.5 to 16.4 building on MacOS 12.0 (Monterey) or newer. The Xcode
#   command-line tools must also be installed. Newer Xcode versions may not have
#   been been tested and are not recommended.
#
# - Windows requirements:
#   Visual Studio 2022 building on Windows 10 or newer. Windows 10/11 64-bit is
#   recommended. Newer versions will likely also work but may not have been
#   tested.
#
# BUILD EXAMPLES
#
# The below commands will generate project files and create a Debug build of all
# JCEF native targets using CMake and the platform toolchain.
#
# Start by creating and entering the CMake build output directory. The
#`jcef_build` directory name is required by other JCEF tooling (specifically the
# tools/make_distrib.[bat|sh] and tools/run.[bat|sh] scripts) and should not be
# changed.
# > cd path/to/java-cef/src
# > mkdir jcef_build && cd jcef_build
#
# To perform a Linux build using a 32-bit CEF binary distribution on a 32-bit
# Linux platform or a 64-bit CEF binary distribution on a 64-bit Linux platform:
#   Using Unix Makefiles:
#     > cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug ..
#     > make -j4
#
#   Using Ninja:
#     > cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ..
#     > ninja
#
# To perform a MacOS build using a 64-bit CEF binary distribution:
#   Using the Xcode IDE:
#     > cmake -G "Xcode" -DPROJECT_ARCH="x86_64" ..
#     Open jcef.xcodeproj in Xcode and select Product > Build.
#
#   Using Ninja:
#     > cmake -G "Ninja" -DPROJECT_ARCH="x86_64" -DCMAKE_BUILD_TYPE=Debug ..
#     > ninja
#
# To perform a MacOS build using an ARM64 CEF binary distribution:
#   Using the Xcode IDE:
#     > cmake -G "Xcode" -DPROJECT_ARCH="arm64" ..
#     Open jcef.xcodeproj in Xcode and select Product > Build.
#
#   Using Ninja:
#     > cmake -G "Ninja" -DPROJECT_ARCH="arm64" -DCMAKE_BUILD_TYPE=Debug ..
#     > ninja
#
# To perform a Windows build using a 32-bit CEF binary distribution:
#   Using the Visual Studio 2022 IDE:
#     > cmake -G "Visual Studio 17" -A Win32 ..
#     Open jcef.sln in Visual Studio and select Build > Build Solution.
#
#   Using Ninja with Visual Studio 2022 command-line tools:
#     (this path may be different depending on your Visual Studio installation)
#     > "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars32.bat"
#     > cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ..
#     > ninja
#
# To perform a Windows build using a 64-bit CEF binary distribution:
#   Using the Visual Studio 2022 IDE:
#     > cmake -G "Visual Studio 17" -A x64 ..
#     Open jcef.sln in Visual Studio and select Build > Build Solution.
#
#   Using Ninja with Visual Studio 2022 command-line tools:
#     (this path may be different depending on your Visual Studio installation)
#     > "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
#     > cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ..
#     > ninja

#
# Shared configuration.
#

# For VS2022 and Xcode 12+ support.
cmake_minimum_required(VERSION 3.21)

# Only generate Debug and Release configuration types.
set(CMAKE_CONFIGURATION_TYPES Debug Release)

# Project name.
project(jcef)

# Use folders in the resulting project files.
set_property(GLOBAL PROPERTY OS_FOLDERS ON)


#
# CEF configuration.
#

# Specify the CEF distribution version.
if(NOT DEFINED CEF_VERSION)
  set(CEF_VERSION "146.0.10+g8219561+chromium-146.0.7680.179")
endif()

# Determine the platform.
if("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
  if("${PROJECT_ARCH}" STREQUAL "arm64")
    set(CEF_PLATFORM "macosarm64")
  elseif("${PROJECT_ARCH}" STREQUAL "x86_64")
    set(CEF_PLATFORM "macosx64")
  elseif("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "arm64")
    set(PROJECT_ARCH "arm64")
    set(CEF_PLATFORM "macosarm64")
  else()
    set(PROJECT_ARCH "x86_64")
    set(CEF_PLATFORM "macosx64")
  endif()
elseif("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux")
  if(CMAKE_SIZEOF_VOID_P MATCHES 8)
    set(CEF_PLATFORM "linux64")
  else()
    set(CEF_PLATFORM "linux32")
  endif()
elseif("${CMAKE_SYSTEM_NAME}" STREQUAL "Windows")
  if(CMAKE_SIZEOF_VOID_P MATCHES 8)
    set(CEF_PLATFORM "windows64")
  else()
    set(CEF_PLATFORM "windows32")
  endif()
endif()

# Add this project's cmake/ directory to the module path.
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Use an explicitly supplied CEF binary distribution when provided. Dawn uses
# this path to build JCEF against its patched CEF binaries without publishing
# them to the upstream Spotify distribution bucket first.
option(DAWN_NATIVE_CODECS
       "Require Dawn's native-codec CEF distribution marker" OFF)
if(DEFINED CEF_ROOT AND NOT "${CEF_ROOT}" STREQUAL "")
  get_filename_component(CEF_ROOT "${CEF_ROOT}" ABSOLUTE)
  if(NOT EXISTS "${CEF_ROOT}/cmake/FindCEF.cmake")
    message(FATAL_ERROR "CEF_ROOT is not a CEF binary distribution: ${CEF_ROOT}")
  endif()
  if(DAWN_NATIVE_CODECS)
    if(NOT EXISTS "${CEF_ROOT}/dawn-codec-build.properties")
      message(FATAL_ERROR
              "CEF_ROOT is not a Dawn native-codec distribution: ${CEF_ROOT}")
    endif()
    file(STRINGS "${CEF_ROOT}/dawn-codec-build.properties" DAWN_CODEC_BUILD)
    # Every Dawn codec revision is built from one immutable DawnCEFSource commit, so it pins one
    # exact CEF version. native-codecs.5 adds the MP4 AAC demuxer fix, is the first macOS build and
    # leaves out OpenH264. native-codecs.4 was never released and is not accepted.
    if("codec.revision=native-codecs.3" IN_LIST DAWN_CODEC_BUILD)
      set(DAWN_CODEC_REVISION "native-codecs.3")
      set(CEF_ROOT_EXPECTED_VERSION
          "146.0.15+g566c566+chromium-146.0.7680.179")
    elseif("codec.revision=native-codecs.5" IN_LIST DAWN_CODEC_BUILD)
      set(DAWN_CODEC_REVISION "native-codecs.5")
      set(CEF_ROOT_EXPECTED_VERSION
          "146.0.27+g8a3c83a+chromium-146.0.7680.179")
      if(NOT "media.use-openh264=false" IN_LIST DAWN_CODEC_BUILD)
        message(FATAL_ERROR
                "CEF_ROOT marker is missing 'media.use-openh264=false': ${CEF_ROOT}")
      endif()
    else()
      message(FATAL_ERROR
              "CEF_ROOT marker names no known Dawn codec revision: ${CEF_ROOT}")
    endif()
  else()
    set(CEF_ROOT_EXPECTED_VERSION "${CEF_VERSION}")
  endif()
  if(NOT EXISTS "${CEF_ROOT}/include/cef_version.h")
    message(FATAL_ERROR "CEF_ROOT does not contain include/cef_version.h: ${CEF_ROOT}")
  endif()
  file(STRINGS "${CEF_ROOT}/include/cef_version.h" CEF_VERSION_LINE
       REGEX "^#define CEF_VERSION ")
  if(NOT "${CEF_VERSION_LINE}" STREQUAL
     "#define CEF_VERSION \"${CEF_ROOT_EXPECTED_VERSION}\"")
    message(FATAL_ERROR "CEF_ROOT has an unexpected CEF version: ${CEF_VERSION_LINE}")
  endif()

  if(DAWN_NATIVE_CODECS)
    foreach(REQUIRED_MARKER
        "cef.source.commit=82195616d8405e6081a0d90924707b82aa9e4141"
        "chromium.version=146.0.7680.179"
        "ffmpeg.branding=Chromium")
      list(FIND DAWN_CODEC_BUILD "${REQUIRED_MARKER}" MARKER_INDEX)
      if(MARKER_INDEX EQUAL -1)
        message(FATAL_ERROR
                "CEF_ROOT marker is missing '${REQUIRED_MARKER}': ${CEF_ROOT}")
      endif()
    endforeach()
  endif()

  set(CEF_ROOT "${CEF_ROOT}" CACHE PATH "Path to a CEF binary distribution" FORCE)
  message(STATUS "Using CEF binary distribution from ${CEF_ROOT}")
else()
  # Download and extract the upstream CEF binary distribution.
  include(DownloadCEF)
  DownloadCEF("${CEF_PLATFORM}" "${CEF_VERSION}" "${CMAKE_SOURCE_DIR}/third_party/cef")
endif()

# Add the CEF binary distribution's cmake/ directory to the module path.
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CEF_ROOT}/cmake")

# Load the CEF configuration (executes FindCEF.cmake).
find_package(CEF REQUIRED)


#
# Python configuration.
#

# Support specification of the Python executable path via the command-line.
if(DEFINED ENV{PYTHON_EXECUTABLE})
  file(TO_CMAKE_PATH "$ENV{PYTHON_EXECUTABLE}" PYTHON_EXECUTABLE)
endif()

if(NOT PYTHON_EXECUTABLE)
  unset(PYTHON_EXECUTABLE)

  # Find the python interpreter.
  find_package(PythonInterp)

  if(NOT ${PYTHONINTERP_FOUND})
    message(FATAL_ERROR "A Python installation is required. Set the "
                        "PYTHON_EXECUTABLE environment variable to explicitly "
                        "specify the Python executable path.")
  endif()
endif()

message(STATUS "Using Python: ${PYTHON_EXECUTABLE}")


#
# Java configuration.
#

# Minimum required Java version.
set(JDK_MIN_VERSION 1.7)

set(JAVA_FATAL_ERROR "A Java installation is required. Set the JAVA_HOME "
                     "environment variable to explicitly specify the Java "
                     "installation directory.")

# Find the Java Native Interface (JNI) installation.
find_package(JNI ${JDK_MIN_VERSION})
if(NOT ${JNI_FOUND})
  message(FATAL_ERROR ${JAVA_FATAL_ERROR})
endif()

if(OS_MACOSX)
  # OS X stores the Java binaries separately from the JNI includes/libraries.
  # Find the Java development installation.
  find_package(Java ${JDK_MIN_VERSION} COMPONENTS Development)

  if(NOT ${Java_FOUND})
    message(FATAL_ERROR ${JAVA_FATAL_ERROR})
  endif()

  # Determine the root path for the Java installation.
  # Remove "bin/javac" from the path.
  get_filename_component(JAVA_DIR ${Java_JAVAC_EXECUTABLE} DIRECTORY)
  get_filename_component(JAVA_DIR ${JAVA_DIR} DIRECTORY)
else()
  # Determine the root path for the Java installation.
  # Remove "include" from the path.
  get_filename_component(JAVA_DIR ${JAVA_INCLUDE_PATH} DIRECTORY)
endif()


#
# Post-configuration actions.
#

# Generate the JCEF version header.
message(STATUS "Generating native/jcef_version.h file...")
execute_process(
  COMMAND "${PYTHON_EXECUTABLE}"
          "tools/make_version_header.py"
          "--header"
          "native/jcef_version.h"
          "--cef-path"
          "${CEF_ROOT}"
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  RESULT_VARIABLE EXECUTE_RV
  )
if(NOT EXECUTE_RV STREQUAL "0")
  message(FATAL_ERROR "Execution failed with unexpected result: ${EXECUTE_RV}")
endif()

# Copy the CEF README.txt file to the cmake build directory for use by the
# make_readme.py script.
file(COPY "${CEF_ROOT}/README.txt" DESTINATION "${CMAKE_BINARY_DIR}")

# Download clang-format from Google Storage.
if(OS_WINDOWS)
  set(GS_PLATFORM "win32")
  set(GS_HASHPATH "win/clang-format.exe.sha1")
  set(GS_OUTPATH "win/clang-format.exe")
elseif(OS_MACOSX)
  set(GS_PLATFORM "darwin")
  if("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "arm64")
    set(GS_HASHPATH "mac/clang-format.arm64.sha1")
  else()
    set(GS_HASHPATH "mac/clang-format.x64.sha1")
  endif()
  set(GS_OUTPATH "mac/clang-format")
elseif(OS_LINUX)
  set(GS_PLATFORM "linux*")
  set(GS_HASHPATH "linux64/clang-format.sha1")
  set(GS_OUTPATH "linux64/clang-format")
endif()

message(STATUS "Downloading clang-format from Google Storage...")
execute_process(
  COMMAND "${PYTHON_EXECUTABLE}"
          "tools/buildtools/download_from_google_storage.py"
          "--no_resume"
          "--platform=${GS_PLATFORM}"
          "--no_auth"
          "--bucket" "chromium-clang-format"
          "-s" "tools/buildtools/${GS_HASHPATH}"
          "-o" "tools/buildtools/${GS_OUTPATH}"
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  RESULT_VARIABLE EXECUTE_RV
  )
if(NOT EXECUTE_RV STREQUAL "0")
  message(FATAL_ERROR "Execution failed with unexpected result: ${EXECUTE_RV}")
endif()


#
# Include target subdirectories.
#

add_subdirectory(${CEF_LIBCEF_DLL_WRAPPER_PATH} libcef_dll_wrapper)
add_subdirectory(native)


#
# Display configuration settings.
#

PRINT_CEF_CONFIG()

message(STATUS "*** JCEF CONFIGURATION SETTINGS ***")
message(STATUS "Python executable:            ${PYTHON_EXECUTABLE}")
message(STATUS "Java directory:               ${JAVA_DIR}")
message(STATUS "JNI libraries:                ${JNI_LIBRARIES}")
message(STATUS "JNI include directories:      ${JNI_INCLUDE_DIRS}")
