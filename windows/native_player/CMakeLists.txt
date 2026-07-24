cmake_minimum_required(VERSION 3.14)

# 固定第三方依赖版本与摘要，禁止回退到Pub Cache或历史build目录。
set(LTP_NATIVE_DEPS "${CMAKE_BINARY_DIR}/ltp_native_deps")
set(LTP_MPV_ARCHIVE "${LTP_NATIVE_DEPS}/mpv.7z")
set(LTP_ANGLE_ARCHIVE "${LTP_NATIVE_DEPS}/angle.7z")
set(LTP_VIDEO_ARCHIVE "${LTP_NATIVE_DEPS}/media_kit_video.tar.gz")
set(LTP_FFMPEG_ARCHIVE "${LTP_NATIVE_DEPS}/ffmpeg-lgpl-shared.zip")
file(MAKE_DIRECTORY "${LTP_NATIVE_DEPS}")

function(ltp_download url sha256 output)
  if(EXISTS "${output}")
    file(SHA256 "${output}" actual)
    if("${actual}" STREQUAL "${sha256}")
      return()
    endif()
    # 最终归档摘要不匹配时必须立即删除，禁止后续解压半成品。
    file(REMOVE "${output}")
  endif()

  set(download_temp "${output}.download")
  file(REMOVE "${download_temp}")
  set(download_verified FALSE)
  foreach(attempt RANGE 1 3)
    # 网络响应只写入临时文件；断线、代理错误或摘要不匹配都不能污染最终缓存。
    file(DOWNLOAD "${url}" "${download_temp}"
      TLS_VERIFY ON
      SHOW_PROGRESS
      TIMEOUT 300
      INACTIVITY_TIMEOUT 30
      STATUS download_status)
    list(GET download_status 0 status_code)
    list(GET download_status 1 status_message)
    if(status_code EQUAL 0 AND EXISTS "${download_temp}")
      file(SHA256 "${download_temp}" actual)
      if("${actual}" STREQUAL "${sha256}")
        file(RENAME "${download_temp}" "${output}")
        set(download_verified TRUE)
        break()
      endif()
      message(STATUS
        "Dependency download attempt ${attempt}/3 returned an invalid SHA256")
    else()
      message(STATUS
        "Dependency download attempt ${attempt}/3 failed: ${status_message}")
    endif()
    file(REMOVE "${download_temp}")
    if(attempt LESS 3)
      execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 2)
    endif()
  endforeach()
  if(NOT download_verified)
    file(REMOVE "${download_temp}")
    message(FATAL_ERROR
      "Failed to download and verify pinned dependency after 3 attempts: ${output}")
  endif()
endfunction()

function(ltp_seed_verified_archive source output sha256)
  if(EXISTS "${output}")
    file(SHA256 "${output}" actual)
    if("${actual}" STREQUAL "${sha256}")
      return()
    endif()
    file(REMOVE "${output}")
  endif()
  # Flutter 插件与原生后端依赖相同归档时复用已校验文件，避免重复访问网络。
  configure_file("${source}" "${output}" COPYONLY)
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
  "https://pub.dev/api/archives/media_kit_video-2.0.1.tar.gz"
  "afaa509e7b7e0bf247557a3a740cde903a52c34ace9810f94500e127bd7b043d"
  "${LTP_VIDEO_ARCHIVE}")
ltp_download(
  "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-07-12-13-16/ffmpeg-n8.1.2-22-g94138f6973-win64-lgpl-shared-8.1.zip"
  "08c967cc9a52e23eec43e7a50dd42b02f64e22d6ee4ef51de684fe55b7f69a75"
  "${LTP_FFMPEG_ARCHIVE}")
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

# media_kit 插件稍后会在同一 CMake binary directory 查找这两个固定文件名。
# 在插件配置前提供项目已校验的副本，避免重复下载及半成品摘要错误。
ltp_seed_verified_archive(
  "${LTP_MPV_ARCHIVE}"
  "${CMAKE_BINARY_DIR}/mpv-dev-x86_64-20230924-git-652a1dd.7z"
  "dce982222d7a23e4a1c6f0fb6cc39f6e899a6714624b95ea49cff6558ee97572")
ltp_seed_verified_archive(
  "${LTP_ANGLE_ARCHIVE}"
  "${CMAKE_BINARY_DIR}/ANGLE.7z"
  "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a")

foreach(pair IN ITEMS "mpv;${LTP_MPV_ARCHIVE}" "angle;${LTP_ANGLE_ARCHIVE}" "video;${LTP_VIDEO_ARCHIVE}" "ffmpeg;${LTP_FFMPEG_ARCHIVE}")
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

# BtbN 归档带版本目录；只接受唯一匹配，避免构建机残留目录导致链接到错误 ABI。
file(GLOB LTP_FFMPEG_ROOTS LIST_DIRECTORIES true
  "${LTP_NATIVE_DEPS}/ffmpeg/ffmpeg-*-win64-lgpl-shared-8.1")
list(LENGTH LTP_FFMPEG_ROOTS LTP_FFMPEG_ROOT_COUNT)
if(NOT LTP_FFMPEG_ROOT_COUNT EQUAL 1)
  message(FATAL_ERROR "Expected exactly one pinned FFmpeg shared root")
endif()
list(GET LTP_FFMPEG_ROOTS 0 LTP_FFMPEG_ROOT)

# media_kit_video 仅作为已固定摘要的 Windows C++ 源码供应包；移除 Dart 目录，
# 避免 Flutter Analyzer 把 build 下的第三方实现误判为本项目源码。
file(REMOVE_RECURSE
  "${LTP_NATIVE_DEPS}/video/lib"
  "${LTP_NATIVE_DEPS}/video/example"
  "${LTP_NATIVE_DEPS}/video/test")

# MediaKit 真正创建渲染 D3D11 设备的位置位于其 ANGLESurfaceManager。这里对已固定
# SHA256 的单个上游源文件做可审计、可失败的构建期补丁：只登记实际设备的 LUID，
# 不修改 Pub Cache，也不按 DXGI 枚举顺序推断活动显卡。
set(LTP_UPSTREAM_ANGLE_SOURCE
  "${LTP_NATIVE_DEPS}/video/windows/angle_surface_manager.cc")
set(LTP_PATCHED_MEDIA_KIT_ANGLE_SOURCE
  "${CMAKE_BINARY_DIR}/ltp_generated/angle_surface_manager_ltp.cc")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/ltp_generated")
file(READ "${LTP_UPSTREAM_ANGLE_SOURCE}" LTP_ANGLE_SOURCE_TEXT)

set(LTP_ANGLE_INCLUDE_MARKER "#include <iostream>\n")
set(LTP_ANGLE_INCLUDE_PATCH [=[#include <iostream>
#include <map>
#include <mutex>
]=])
string(REPLACE "${LTP_ANGLE_INCLUDE_MARKER}" "${LTP_ANGLE_INCLUDE_PATCH}"
  LTP_ANGLE_SOURCE_TEXT "${LTP_ANGLE_SOURCE_TEXT}")

set(LTP_ANGLE_REGISTRY_MARKER "int ANGLESurfaceManager::instance_count_ = 0;\n")
set(LTP_ANGLE_REGISTRY_PATCH [=[int ANGLESurfaceManager::instance_count_ = 0;

namespace {
std::mutex g_ltp_adapter_mutex;
std::map<uint64_t, uint32_t> g_ltp_active_adapter_counts;

uint64_t LtpAdapterKey(const LUID& luid) {
  return (static_cast<uint64_t>(static_cast<uint32_t>(luid.HighPart)) << 32) |
         luid.LowPart;
}

void LtpRegisterActiveAdapter(ID3D11Device* device) {
  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
  DXGI_ADAPTER_DESC description{};
  if (device == nullptr ||
      FAILED(device->QueryInterface(IID_PPV_ARGS(&dxgi_device))) ||
      FAILED(dxgi_device->GetAdapter(&adapter)) ||
      FAILED(adapter->GetDesc(&description))) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_ltp_adapter_mutex);
  ++g_ltp_active_adapter_counts[LtpAdapterKey(description.AdapterLuid)];
}

void LtpUnregisterActiveAdapter(ID3D11Device* device) {
  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
  DXGI_ADAPTER_DESC description{};
  if (device == nullptr ||
      FAILED(device->QueryInterface(IID_PPV_ARGS(&dxgi_device))) ||
      FAILED(dxgi_device->GetAdapter(&adapter)) ||
      FAILED(adapter->GetDesc(&description))) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_ltp_adapter_mutex);
  const auto key = LtpAdapterKey(description.AdapterLuid);
  const auto found = g_ltp_active_adapter_counts.find(key);
  if (found == g_ltp_active_adapter_counts.end()) return;
  if (found->second <= 1) {
    g_ltp_active_adapter_counts.erase(found);
  } else {
    --found->second;
  }
}
}  // namespace

// 1 表示当前模块只有一个活动适配器，0 表示尚未创建，2 表示多个不同 LUID。
extern "C" __declspec(dllexport) int LtpMediaKitQueryActiveAdapterLuid(
    int32_t* high_part, uint32_t* low_part) {
  if (high_part == nullptr || low_part == nullptr) return 0;
  std::lock_guard<std::mutex> lock(g_ltp_adapter_mutex);
  if (g_ltp_active_adapter_counts.empty()) return 0;
  if (g_ltp_active_adapter_counts.size() != 1) return 2;
  const uint64_t key = g_ltp_active_adapter_counts.begin()->first;
  *high_part = static_cast<int32_t>(key >> 32);
  *low_part = static_cast<uint32_t>(key);
  return 1;
}
]=])
string(REPLACE "${LTP_ANGLE_REGISTRY_MARKER}" "${LTP_ANGLE_REGISTRY_PATCH}"
  LTP_ANGLE_SOURCE_TEXT "${LTP_ANGLE_SOURCE_TEXT}")

set(LTP_ANGLE_CREATE_MARKER [=[    CHECK_HRESULT("D3D11CreateDevice");
]=])
set(LTP_ANGLE_CREATE_PATCH [=[    CHECK_HRESULT("D3D11CreateDevice");
    LtpRegisterActiveAdapter(d3d_11_device_);
]=])
string(REPLACE "${LTP_ANGLE_CREATE_MARKER}" "${LTP_ANGLE_CREATE_PATCH}"
  LTP_ANGLE_SOURCE_TEXT "${LTP_ANGLE_SOURCE_TEXT}")

set(LTP_ANGLE_RELEASE_MARKER [=[    if (d3d_11_device_) {
      d3d_11_device_->Release();
]=])
set(LTP_ANGLE_RELEASE_PATCH [=[    if (d3d_11_device_) {
      LtpUnregisterActiveAdapter(d3d_11_device_);
      d3d_11_device_->Release();
]=])
string(REPLACE "${LTP_ANGLE_RELEASE_MARKER}" "${LTP_ANGLE_RELEASE_PATCH}"
  LTP_ANGLE_SOURCE_TEXT "${LTP_ANGLE_SOURCE_TEXT}")

foreach(required_fragment IN ITEMS
    "LtpMediaKitQueryActiveAdapterLuid"
    "LtpRegisterActiveAdapter(d3d_11_device_)"
    "LtpUnregisterActiveAdapter(d3d_11_device_)")
  string(FIND "${LTP_ANGLE_SOURCE_TEXT}" "${required_fragment}" fragment_index)
  if(fragment_index EQUAL -1)
    message(FATAL_ERROR
      "Pinned media_kit_video source no longer matches the active-adapter patch")
  endif()
endforeach()
file(WRITE "${LTP_PATCHED_MEDIA_KIT_ANGLE_SOURCE}"
  "${LTP_ANGLE_SOURCE_TEXT}")
set(LTP_PATCHED_MEDIA_KIT_ANGLE_SOURCE
  "${LTP_PATCHED_MEDIA_KIT_ANGLE_SOURCE}" PARENT_SCOPE)

# media_kit_video 2.0.1 的纹理回调仍会用可变的 texture_id_ 查询描述符映射。
# RegisterTexture 可在映射写入前同步取帧，退出或缩放时也可能切换当前 ID；
# 此时 unordered_map::at 抛出的异常会越过 Flutter 原生回调边界并终止进程。
# 每个回调必须捕获自己描述符的稳定地址，所有权仍由对应 texture ID 的 map
# 持有到 UnregisterTexture 完成；补丁只作用于固定归档，不修改全局 Pub Cache。
set(LTP_UPSTREAM_VIDEO_OUTPUT_SOURCE
  "${LTP_NATIVE_DEPS}/video/windows/video_output.cc")
set(LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE
  "${CMAKE_BINARY_DIR}/ltp_generated/video_output_ltp.cc")
file(READ "${LTP_UPSTREAM_VIDEO_OUTPUT_SOURCE}" LTP_VIDEO_OUTPUT_SOURCE_TEXT)

set(LTP_VIDEO_OUTPUT_GPU_MARKER [=[    auto texture_variant =
        std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle, [&](auto, auto) {
              std::lock_guard<std::mutex> lock(textures_mutex_);
              if (texture_id_) {
                surface_manager_->Read();
                return textures_.at(texture_id_).get();
              } else {
                return (FlutterDesktopGpuSurfaceDescriptor*)nullptr;
              }
            }));
]=])
set(LTP_VIDEO_OUTPUT_GPU_PATCH [=[    // 回调可能在 RegisterTexture 返回前取帧，不能依赖尚未写入 map 的 ID。
    auto* texture_descriptor = texture.get();
    auto texture_variant =
        std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
            [&, texture_descriptor](auto, auto) {
              std::lock_guard<std::mutex> lock(textures_mutex_);
              if (destroyed_ || surface_manager_ == nullptr) {
                return (FlutterDesktopGpuSurfaceDescriptor*)nullptr;
              }
              surface_manager_->Read();
              return texture_descriptor;
            }));
]=])
string(FIND "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}"
  "${LTP_VIDEO_OUTPUT_GPU_MARKER}" LTP_VIDEO_OUTPUT_GPU_MARKER_INDEX)
if(LTP_VIDEO_OUTPUT_GPU_MARKER_INDEX EQUAL -1)
  message(FATAL_ERROR
    "Pinned media_kit_video source no longer matches the GPU texture patch")
endif()
string(REPLACE "${LTP_VIDEO_OUTPUT_GPU_MARKER}"
  "${LTP_VIDEO_OUTPUT_GPU_PATCH}"
  LTP_VIDEO_OUTPUT_SOURCE_TEXT "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}")

set(LTP_VIDEO_OUTPUT_PIXEL_MARKER [=[    auto texture_variant = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture([&](auto, auto) {
          std::lock_guard<std::mutex> lock(textures_mutex_);
          if (texture_id_) {
            return pixel_buffer_textures_.at(texture_id_).get();
          } else {
            return (FlutterDesktopPixelBuffer*)nullptr;
          }
        }));
]=])
set(LTP_VIDEO_OUTPUT_PIXEL_PATCH [=[    // 软件纹理遵循同一所有权规则，避免退出阶段读取已切换的全局 ID。
    auto* pixel_buffer_descriptor = pixel_buffer_texture.get();
    auto texture_variant = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture(
            [&, pixel_buffer_descriptor](auto, auto) {
              std::lock_guard<std::mutex> lock(textures_mutex_);
              if (destroyed_) {
                return (FlutterDesktopPixelBuffer*)nullptr;
              }
              return pixel_buffer_descriptor;
            }));
]=])
string(FIND "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}"
  "${LTP_VIDEO_OUTPUT_PIXEL_MARKER}" LTP_VIDEO_OUTPUT_PIXEL_MARKER_INDEX)
if(LTP_VIDEO_OUTPUT_PIXEL_MARKER_INDEX EQUAL -1)
  message(FATAL_ERROR
    "Pinned media_kit_video source no longer matches the pixel texture patch")
endif()
string(REPLACE "${LTP_VIDEO_OUTPUT_PIXEL_MARKER}"
  "${LTP_VIDEO_OUTPUT_PIXEL_PATCH}"
  LTP_VIDEO_OUTPUT_SOURCE_TEXT "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}")

foreach(required_fragment IN ITEMS
    "[&, texture_descriptor]"
    "return texture_descriptor"
    "[&, pixel_buffer_descriptor]"
    "return pixel_buffer_descriptor")
  string(FIND "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}" "${required_fragment}"
    fragment_index)
  if(fragment_index EQUAL -1)
    message(FATAL_ERROR
      "Pinned media_kit_video source no longer matches the texture lifetime patch")
  endif()
endforeach()
file(WRITE "${LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE}"
  "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}")
set(LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE
  "${LTP_PATCHED_MEDIA_KIT_VIDEO_OUTPUT_SOURCE}" PARENT_SCOPE)
set(LTP_PINNED_MEDIA_KIT_VIDEO_WINDOWS_DIR
  "${LTP_NATIVE_DEPS}/video/windows" PARENT_SCOPE)

add_library(ltp_native_runtime STATIC
  "${LTP_PATCHED_MEDIA_KIT_ANGLE_SOURCE}"
  "${LTP_NATIVE_DEPS}/video/windows/utils.cc")
apply_standard_settings(ltp_native_runtime)
target_compile_options(ltp_native_runtime PRIVATE /utf-8)
target_compile_definitions(ltp_native_runtime PRIVATE
  NOMINMAX _DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)
target_include_directories(ltp_native_runtime PUBLIC
  "${LTP_NATIVE_DEPS}/video/windows"
  "${LTP_NATIVE_DEPS}/mpv/include"
  "${LTP_NATIVE_DEPS}/angle/include"
  "${LTP_FFMPEG_ROOT}/include")
target_link_libraries(ltp_native_runtime PUBLIC
  "${LTP_NATIVE_DEPS}/mpv/libmpv.dll.a"
  "${LTP_NATIVE_DEPS}/angle/lib/libEGL.dll.lib"
  "${LTP_NATIVE_DEPS}/angle/lib/libGLESv2.dll.lib"
  d3d11.lib dxgi.lib)

# avcodec 的共享构建还依赖 swresample/swscale；不打包未调用的 filter/device DLL，
# 避免为了紧凑元数据探测额外增加约 32 MiB 发布体积。
set(LTP_FFMPEG_RUNTIME_DLLS
  "${LTP_FFMPEG_ROOT}/bin/avformat-62.dll"
  "${LTP_FFMPEG_ROOT}/bin/avcodec-62.dll"
  "${LTP_FFMPEG_ROOT}/bin/avutil-60.dll"
  "${LTP_FFMPEG_ROOT}/bin/swresample-6.dll"
  "${LTP_FFMPEG_ROOT}/bin/swscale-9.dll")

set(LTP_NATIVE_RUNTIME_DLLS
  "${LTP_NATIVE_DEPS}/mpv/libmpv-2.dll"
  "${LTP_NATIVE_DEPS}/angle/d3dcompiler_47.dll"
  "${LTP_NATIVE_DEPS}/angle/libEGL.dll"
  "${LTP_NATIVE_DEPS}/angle/libGLESv2.dll"
  ${LTP_FFMPEG_RUNTIME_DLLS}
  PARENT_SCOPE)
set(LTP_NATIVE_LICENSE_FILES
  "${LTP_NATIVE_DEPS}/LICENSE.mpv.GPL-2.0.txt"
  "${LTP_NATIVE_DEPS}/LICENSE.mpv.LGPL-2.1.txt"
  "${LTP_NATIVE_DEPS}/LICENSE.ANGLE.txt"
  "${LTP_NATIVE_DEPS}/video/LICENSE"
  "${LTP_FFMPEG_ROOT}/LICENSE.txt"
  "${CMAKE_CURRENT_SOURCE_DIR}/THIRD_PARTY_NOTICES.md"
  PARENT_SCOPE)
