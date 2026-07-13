cmake_minimum_required(VERSION 3.14)

# 固定第三方依赖版本与摘要，禁止回退到Pub Cache或历史build目录。
set(LTP_NATIVE_DEPS "${CMAKE_BINARY_DIR}/ltp_native_deps")
set(LTP_MPV_ARCHIVE "${LTP_NATIVE_DEPS}/mpv.7z")
set(LTP_ANGLE_ARCHIVE "${LTP_NATIVE_DEPS}/angle.7z")
set(LTP_VIDEO_ARCHIVE "${LTP_NATIVE_DEPS}/media_kit_video.tar.gz")
file(MAKE_DIRECTORY "${LTP_NATIVE_DEPS}")

function(ltp_download url sha256 output)
  if(EXISTS "${output}")
    file(SHA256 "${output}" actual)
  endif()
  if(NOT EXISTS "${output}" OR NOT actual STREQUAL sha256)
    file(REMOVE "${output}")
    file(DOWNLOAD "${url}" "${output}"
      EXPECTED_HASH "SHA256=${sha256}"
      TLS_VERIFY ON
      SHOW_PROGRESS)
  endif()
endfunction()

ltp_download(
  "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z"
  "dce982222d7a23e4a1c6f0fb6cc39f6e899a6714624b95ea49cff6558ee97572"
  "${LTP_MPV_ARCHIVE}")
ltp_download(
  "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"
  "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a"
  "${LTP_ANGLE_ARCHIVE}")
ltp_download(
  "https://pub.dev/api/archives/media_kit_video-1.3.1.tar.gz"
  "813858c3fe84eb46679eb698695f60665e2bfbef757766fac4d2e683f926e15a"
  "${LTP_VIDEO_ARCHIVE}")
ltp_download(
  "https://raw.githubusercontent.com/mpv-player/mpv/v0.36.0/LICENSE.GPL"
  "8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643"
  "${LTP_NATIVE_DEPS}/LICENSE.mpv.GPL-2.0.txt")
ltp_download(
  "https://raw.githubusercontent.com/mpv-player/mpv/v0.36.0/LICENSE.LGPL"
  "dc626520dcd53a22f727af3ee42c770e56c97a64fe3adb063799d8ab032fe551"
  "${LTP_NATIVE_DEPS}/LICENSE.mpv.LGPL-2.1.txt")
ltp_download(
  "https://raw.githubusercontent.com/google/angle/chromium/5359/LICENSE"
  "bf4da21bd20bcfb5b60b7ecc67fa864a79be049e21d6178076887f178dd6c71a"
  "${LTP_NATIVE_DEPS}/LICENSE.ANGLE.txt")

foreach(pair IN ITEMS "mpv;${LTP_MPV_ARCHIVE}" "angle;${LTP_ANGLE_ARCHIVE}" "video;${LTP_VIDEO_ARCHIVE}")
  list(GET pair 0 name)
  list(GET pair 1 archive)
  set(destination "${LTP_NATIVE_DEPS}/${name}")
  if(NOT EXISTS "${destination}/.extracted")
    file(REMOVE_RECURSE "${destination}")
    file(MAKE_DIRECTORY "${destination}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xzf "${archive}"
      WORKING_DIRECTORY "${destination}" RESULT_VARIABLE extract_result)
    if(NOT extract_result EQUAL 0)
      message(FATAL_ERROR "Failed to extract ${archive}")
    endif()
    file(WRITE "${destination}/.extracted" "verified")
  endif()
endforeach()

# media_kit_video 仅作为已固定摘要的 Windows C++ 源码供应包；移除 Dart 目录，
# 避免 Flutter Analyzer 把 build 下的第三方实现误判为本项目源码。
file(REMOVE_RECURSE
  "${LTP_NATIVE_DEPS}/video/lib"
  "${LTP_NATIVE_DEPS}/video/example"
  "${LTP_NATIVE_DEPS}/video/test")

add_library(ltp_native_runtime STATIC
  "${LTP_NATIVE_DEPS}/video/windows/angle_surface_manager.cc"
  "${LTP_NATIVE_DEPS}/video/windows/utils.cc")
apply_standard_settings(ltp_native_runtime)
target_compile_options(ltp_native_runtime PRIVATE /utf-8)
target_compile_definitions(ltp_native_runtime PRIVATE
  NOMINMAX _DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)
target_include_directories(ltp_native_runtime PUBLIC
  "${LTP_NATIVE_DEPS}/video/windows"
  "${LTP_NATIVE_DEPS}/mpv/include"
  "${LTP_NATIVE_DEPS}/angle/include")
target_link_libraries(ltp_native_runtime PUBLIC
  "${LTP_NATIVE_DEPS}/mpv/libmpv.dll.a"
  "${LTP_NATIVE_DEPS}/angle/lib/libEGL.dll.lib"
  "${LTP_NATIVE_DEPS}/angle/lib/libGLESv2.dll.lib"
  d3d11.lib dxgi.lib)

set(LTP_NATIVE_RUNTIME_DLLS
  "${LTP_NATIVE_DEPS}/mpv/libmpv-2.dll"
  "${LTP_NATIVE_DEPS}/angle/d3dcompiler_47.dll"
  "${LTP_NATIVE_DEPS}/angle/libEGL.dll"
  "${LTP_NATIVE_DEPS}/angle/libGLESv2.dll"
  PARENT_SCOPE)
set(LTP_NATIVE_LICENSE_FILES
  "${LTP_NATIVE_DEPS}/LICENSE.mpv.GPL-2.0.txt"
  "${LTP_NATIVE_DEPS}/LICENSE.mpv.LGPL-2.1.txt"
  "${LTP_NATIVE_DEPS}/LICENSE.ANGLE.txt"
  "${LTP_NATIVE_DEPS}/video/LICENSE"
  "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY_NOTICES.md"
  PARENT_SCOPE)
