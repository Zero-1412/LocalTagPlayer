# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(local_tag_player LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "local_tag_player")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("native_player")

# Rust 媒体库扫描 sidecar 是可选构建依赖；没有 cargo 时保留 Dart 后端并继续正常构建。
find_program(LTP_CARGO_EXECUTABLE cargo)
if(LTP_CARGO_EXECUTABLE)
  execute_process(
    COMMAND "${LTP_CARGO_EXECUTABLE}" --version
    RESULT_VARIABLE LTP_CARGO_VERSION_RESULT
    OUTPUT_QUIET
    ERROR_QUIET
    TIMEOUT 5)
endif()
if(LTP_CARGO_EXECUTABLE AND LTP_CARGO_VERSION_RESULT EQUAL 0)
  set(LTP_RUST_SCAN_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/rust_library_scan/Cargo.toml")
  set(LTP_RUST_SCAN_EXE "${CMAKE_CURRENT_SOURCE_DIR}/rust_library_scan/target/release/ltp_rust_library_scan.exe")
  file(GLOB_RECURSE LTP_RUST_SCAN_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/rust_library_scan/src/*.rs"
    "${LTP_RUST_SCAN_MANIFEST}")
  add_custom_command(
    OUTPUT "${LTP_RUST_SCAN_EXE}"
    COMMAND "${LTP_CARGO_EXECUTABLE}" build --release --manifest-path "${LTP_RUST_SCAN_MANIFEST}"
    DEPENDS ${LTP_RUST_SCAN_SOURCES}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/rust_library_scan"
    COMMENT "Building read-only Rust LibraryScanBackend"
    VERBATIM)
  add_custom_target(ltp_rust_library_scan ALL DEPENDS "${LTP_RUST_SCAN_EXE}")
  # 安装规则必须等 Flutter 将前缀绑定到 Release/Debug bundle 后再声明，
  # 否则干净配置会把 sidecar 解析到系统 Program Files 并要求管理员权限。
  set(LTP_RUST_SCAN_AVAILABLE TRUE)
else()
  message(STATUS "Rust toolchain unavailable; using Dart LibraryScanBackend fallback")
endif()

add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
set(LTP_MEDIA_KIT_VIDEO_ANGLE_SOURCE
  "${FLUTTER_MANAGED_DIR}/ephemeral/.plugin_symlinks/media_kit_video/windows/angle_surface_manager.cc")
set(LTP_MEDIA_KIT_VIDEO_OUTPUT_SOURCE
  "${FLUTTER_MANAGED_DIR}/ephemeral/.plugin_symlinks/media_kit_video/windows/video_output.cc")
# 上游源文件仍保留在插件目标中用于 IDE 导航，但不再编译；实际编译的是上面从
# 固定归档生成的 LUID 与纹理生命周期补丁版本，因此不会写入全局 Pub Cache。
set_source_files_properties("${LTP_MEDIA_KIT_VIDEO_ANGLE_SOURCE}"
  PROPERTIES HEADER_FILE_ONLY TRUE)
set_source_files_properties("${LTP_MEDIA_KIT_VIDEO_OUTPUT_SOURCE}"
  PROPERTIES HEADER_FILE_ONLY TRUE)
include(flutter/generated_plugins.cmake)
if(TARGET media_kit_video_plugin)
  get_target_property(LTP_MEDIA_KIT_VIDEO_SOURCES
    media_kit_video_plugin SOURCES)
  get_target_property(LTP_MEDIA_KIT_VIDEO_SOURCE_DIR
    media_kit_video_plugin SOURCE_DIR)
  set(LTP_MEDIA_KIT_VIDEO_FILTERED_SOURCES)
  foreach(source IN LISTS LTP_MEDIA_KIT_VIDEO_SOURCES)
    if(source MATCHES "(^|[/\\\\])(angle_surface_manager|video_output)\\.cc$")
      continue()
    endif()
    if(IS_ABSOLUTE "${source}")
      list(APPEND LTP_MEDIA_KIT_VIDEO_FILTERED_SOURCES "${source}")
    else()
      # SOURCES 属性中的相对路径属于插件自身 SOURCE_DIR；转换成绝对路径后再从
      # 父目录重设，避免 CMake 把它们误解为项目根目录文件。
      list(APPEND LTP_MEDIA_KIT_VIDEO_FILTERED_SOURCES
        "${LTP_MEDIA_KIT_VIDEO_SOURCE_DIR}/${source}")
    endif()
  endforeach()
  set_property(TARGET media_kit_video_plugin PROPERTY SOURCES
    "${LTP_MEDIA_KIT_VIDEO_FILTERED_SOURCES}")
  target_sources(media_kit_video_plugin PRIVATE
    "${LTP_PATCHED_MEDIA_KIT_ANGLE_SOURCE}"
    "${LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE}")
  target_include_directories(media_kit_video_plugin PRIVATE
    "${LTP_PINNED_MEDIA_KIT_VIDEO_WINDOWS_DIR}")
  target_compile_options(media_kit_video_plugin PRIVATE /utf-8)
endif()


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

if(LTP_RUST_SCAN_AVAILABLE)
  install(PROGRAMS "${LTP_RUST_SCAN_EXE}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
  install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/rust_library_scan/LICENSE"
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/rust_library_scan"
    COMPONENT Runtime)
endif()

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

if(LTP_NATIVE_RUNTIME_DLLS)
  install(FILES ${LTP_NATIVE_RUNTIME_DLLS}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
if(LTP_NATIVE_LICENSE_FILES)
  install(FILES ${LTP_NATIVE_LICENSE_FILES}
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/native_player"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)


# Optional bundled media tools for fast library indexing.
# Put ffmpeg.exe, ffprobe.exe and their required DLLs under:
#   windows/tools/ffmpeg/bin
# They will be copied next to the packaged executable as tools/ffmpeg/bin.
set(LOCAL_MEDIA_TOOLS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tools/ffmpeg/bin")
if(EXISTS "${LOCAL_MEDIA_TOOLS_DIR}/ffmpeg.exe" AND EXISTS "${LOCAL_MEDIA_TOOLS_DIR}/ffprobe.exe")
  install(FILES
      "${LOCAL_MEDIA_TOOLS_DIR}/ffmpeg.exe"
      "${LOCAL_MEDIA_TOOLS_DIR}/ffprobe.exe"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/ffmpeg/bin"
    COMPONENT Runtime)
  file(GLOB LOCAL_MEDIA_TOOL_DLLS "${LOCAL_MEDIA_TOOLS_DIR}/*.dll")
  if(LOCAL_MEDIA_TOOL_DLLS)
    install(FILES ${LOCAL_MEDIA_TOOL_DLLS}
      DESTINATION "${CMAKE_INSTALL_PREFIX}/tools/ffmpeg/bin"
      COMPONENT Runtime)
  endif()
endif()

# Optional bundled SQLite runtime for sqflite_common_ffi.
set(LOCAL_SQLITE_DLL "${CMAKE_CURRENT_SOURCE_DIR}/tools/sqlite/sqlite3.dll")
if(EXISTS "${LOCAL_SQLITE_DLL}")
  install(FILES "${LOCAL_SQLITE_DLL}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
endif()
# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
