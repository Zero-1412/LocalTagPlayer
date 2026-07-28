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
  "https://github.com/zhongfly/mpv-winbuild/releases/download/2026-07-26-48e6c35c0e/mpv-dev-x86_64-20260726-git-48e6c35c0e.7z"
  "72b1b348458f632063ed92a967617a078dc05129635a1b929c61d121b0e3a802"
  "${LTP_MPV_ARCHIVE}")
ltp_download(
  "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"
  "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a"
  "${LTP_ANGLE_ARCHIVE}")
ltp_download(
  "https://pub.dev/api/archives/media_kit_video-2.0.1.tar.gz"
  "afaa509e7b7e0bf247557a3a740cde903a52c34ace9810f94500e127bd7b043d"
  "${LTP_VIDEO_ARCHIVE}")
# BtbN 的普通日构建只保留 14 天；使用月末保留构建，确保固定摘要在干净环境可恢复。
ltp_download(
  "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-06-30-13-34/ffmpeg-n8.1.2-21-gce3c09c101-win64-lgpl-shared-8.1.zip"
  "27bcaf58b5140171dfe838a0b365d12c60607d71fc168424456410bad6a834da"
  "${LTP_FFMPEG_ARCHIVE}")
ltp_download(
  "https://raw.githubusercontent.com/mpv-player/mpv/v0.41.0/LICENSE.GPL"
  "edaef632cbb643e4e7a221717a6c441a4c1a7c918e6e4d56debc3d8739b233f6"
  "${LTP_NATIVE_DEPS}/LICENSE.mpv.GPL-2.0.txt")
ltp_download(
  "https://raw.githubusercontent.com/mpv-player/mpv/v0.41.0/LICENSE.LGPL"
  "72b672113d642cbb8ef5dcc76938db801983c56e50b1400ab930f1a64d6dc8d9"
  "${LTP_NATIVE_DEPS}/LICENSE.mpv.LGPL-2.1.txt")
ltp_download(
  "https://raw.githubusercontent.com/google/angle/chromium/5359/LICENSE"
  "bf4da21bd20bcfb5b60b7ecc67fa864a79be049e21d6178076887f178dd6c71a"
  "${LTP_NATIVE_DEPS}/LICENSE.ANGLE.txt")

# media_kit 插件稍后会在同一 CMake binary directory 查找这两个固定文件名。
# 在插件配置前提供项目已校验的副本，避免重复下载及半成品摘要错误。
ltp_seed_verified_archive(
  "${LTP_MPV_ARCHIVE}"
  "${CMAKE_BINARY_DIR}/mpv-dev-x86_64-20260726-git-48e6c35c0e.7z"
  "72b1b348458f632063ed92a967617a078dc05129635a1b929c61d121b0e3a802")
ltp_seed_verified_archive(
  "${LTP_ANGLE_ARCHIVE}"
  "${CMAKE_BINARY_DIR}/ANGLE.7z"
  "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a")

foreach(pair IN ITEMS "mpv;${LTP_MPV_ARCHIVE}" "angle;${LTP_ANGLE_ARCHIVE}" "video;${LTP_VIDEO_ARCHIVE}" "ffmpeg;${LTP_FFMPEG_ARCHIVE}")
  list(GET pair 0 name)
  list(GET pair 1 archive)
  set(destination "${LTP_NATIVE_DEPS}/${name}")
  file(SHA256 "${archive}" archive_sha256)
  set(extracted_sha256 "")
  if(EXISTS "${destination}/.extracted")
    file(READ "${destination}/.extracted" extracted_sha256)
  endif()
  # 提升固定依赖版本时必须按归档摘要重建目录，不能让旧 `.extracted` 标记复用旧 DLL。
  if(NOT "${extracted_sha256}" STREQUAL "${archive_sha256}")
    file(REMOVE_RECURSE "${destination}")
    file(MAKE_DIRECTORY "${destination}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xzf "${archive}"
      WORKING_DIRECTORY "${destination}" RESULT_VARIABLE extract_result)
    if(NOT extract_result EQUAL 0)
      message(FATAL_ERROR "Failed to extract ${archive}")
    endif()
    file(WRITE "${destination}/.extracted" "${archive_sha256}")
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
set(LTP_UPSTREAM_ANGLE_HEADER
  "${LTP_NATIVE_DEPS}/video/windows/angle_surface_manager.h")
set(LTP_PATCHED_MEDIA_KIT_ANGLE_SOURCE
  "${CMAKE_BINARY_DIR}/ltp_generated/angle_surface_manager_ltp.cc")
set(LTP_PATCHED_MEDIA_KIT_ANGLE_HEADER
  "${CMAKE_BINARY_DIR}/ltp_generated/angle_surface_manager.h")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/ltp_generated")
file(READ "${LTP_UPSTREAM_ANGLE_SOURCE}" LTP_ANGLE_SOURCE_TEXT)
file(READ "${LTP_UPSTREAM_ANGLE_HEADER}" LTP_ANGLE_HEADER_TEXT)

# 本机视频增强原型必须复用 ANGLE 已创建的 D3D11 设备与共享输出纹理。只在固定归档
# 生成的头文件中增加只读借用访问器；所有权仍留在 ANGLESurfaceManager，调用方不得释放。
set(LTP_ANGLE_HEADER_MARKER [=[  const HANDLE handle() const { return handle_; }
]=])
set(LTP_ANGLE_HEADER_PATCH [=[  const HANDLE handle() const { return handle_; }
  ID3D11Device* d3d_11_device() const { return d3d_11_device_; }
  ID3D11DeviceContext* d3d_11_device_context() const {
    return d3d_11_device_context_;
  }
  ID3D11Texture2D* d3d_11_texture() const {
    return d3d_11_texture_2D_.Get();
  }
]=])
string(FIND "${LTP_ANGLE_HEADER_TEXT}" "${LTP_ANGLE_HEADER_MARKER}"
  LTP_ANGLE_HEADER_MARKER_INDEX)
if(LTP_ANGLE_HEADER_MARKER_INDEX EQUAL -1)
  message(FATAL_ERROR
    "Pinned media_kit_video header no longer matches the D3D11 accessor patch")
endif()
string(REPLACE "${LTP_ANGLE_HEADER_MARKER}" "${LTP_ANGLE_HEADER_PATCH}"
  LTP_ANGLE_HEADER_TEXT "${LTP_ANGLE_HEADER_TEXT}")
file(WRITE "${LTP_PATCHED_MEDIA_KIT_ANGLE_HEADER}"
  "${LTP_ANGLE_HEADER_TEXT}")

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

# 该开关只服务隔离 QA：libmpv 必须在创建 OpenGL render context 前知道期望的
# D3D11VA interop，否则 Dart 层在 VideoController 构造完成后再写属性已经太晚。
# 环境变量缺省时不写任何新 mpv 选项，不改变正式播放器的解码与回退行为。
set(LTP_VIDEO_OUTPUT_INTEROP_MARKER [=[  auto future = thread_pool_ref_->Post([&]() {
    mpv_set_option_string(handle_, "video-sync", "audio");
]=])
set(LTP_VIDEO_OUTPUT_INTEROP_PATCH [=[  auto future = thread_pool_ref_->Post([&]() {
    char angle_interop_qa[2] = {};
    const auto angle_interop_qa_length = GetEnvironmentVariableA(
        "LOCAL_TAG_PLAYER_ANGLE_INTEROP_QA", angle_interop_qa,
        static_cast<DWORD>(sizeof(angle_interop_qa)));
    const bool angle_interop_qa_enabled =
        angle_interop_qa_length == 1 && angle_interop_qa[0] == '1';
    if (angle_interop_qa_enabled) {
      // 只提前声明硬件帧互操作，不注入 d3d11vpp 或其它画质滤镜。
      const int hwdec_result =
          mpv_set_option_string(handle_, "hwdec", "d3d11va");
      const int interop_result = mpv_set_option_string(
          handle_, "gpu-hwdec-interop", "d3d11va");
      std::cout << "ltp-angle-interop-qa: pre-render hwdec="
                << hwdec_result << ", gpu-hwdec-interop=" << interop_result
                << std::endl;
    }
    mpv_set_option_string(handle_, "video-sync", "audio");
]=])
string(FIND "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}"
  "${LTP_VIDEO_OUTPUT_INTEROP_MARKER}" LTP_VIDEO_OUTPUT_INTEROP_MARKER_INDEX)
if(LTP_VIDEO_OUTPUT_INTEROP_MARKER_INDEX EQUAL -1)
  message(FATAL_ERROR
    "Pinned media_kit_video source no longer matches the interop QA patch")
endif()
string(REPLACE "${LTP_VIDEO_OUTPUT_INTEROP_MARKER}"
  "${LTP_VIDEO_OUTPUT_INTEROP_PATCH}"
  LTP_VIDEO_OUTPUT_SOURCE_TEXT "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}")

set(LTP_VIDEO_OUTPUT_ANGLE_LOG_MARKER [=[        surface_manager_->MakeCurrent(true);
        Resize(width_.value_or(1), height_.value_or(1));
]=])
set(LTP_VIDEO_OUTPUT_ANGLE_LOG_PATCH [=[        surface_manager_->MakeCurrent(true);
        if (angle_interop_qa_enabled) {
          const auto display = eglGetCurrentDisplay();
          const auto* vendor = eglQueryString(display, EGL_VENDOR);
          const auto* version = eglQueryString(display, EGL_VERSION);
          std::cout << "ltp-angle-interop-qa: EGL vendor="
                    << (vendor == nullptr ? "unavailable" : vendor)
                    << ", version="
                    << (version == nullptr ? "unavailable" : version)
                    << std::endl;
        }
        Resize(width_.value_or(1), height_.value_or(1));
]=])
string(FIND "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}"
  "${LTP_VIDEO_OUTPUT_ANGLE_LOG_MARKER}"
  LTP_VIDEO_OUTPUT_ANGLE_LOG_MARKER_INDEX)
if(LTP_VIDEO_OUTPUT_ANGLE_LOG_MARKER_INDEX EQUAL -1)
  message(FATAL_ERROR
    "Pinned media_kit_video source no longer matches the ANGLE QA log patch")
endif()
string(REPLACE "${LTP_VIDEO_OUTPUT_ANGLE_LOG_MARKER}"
  "${LTP_VIDEO_OUTPUT_ANGLE_LOG_PATCH}"
  LTP_VIDEO_OUTPUT_SOURCE_TEXT "${LTP_VIDEO_OUTPUT_SOURCE_TEXT}")

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
    "LOCAL_TAG_PLAYER_ANGLE_INTEROP_QA"
    "gpu-hwdec-interop"
    "ltp-angle-interop-qa: EGL vendor="
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
  "${LTP_NATIVE_DEPS}/video/windows/utils.cc"
  "${CMAKE_CURRENT_SOURCE_DIR}/../runner/d3d11_adapter_selector.cpp")
apply_standard_settings(ltp_native_runtime)
target_compile_options(ltp_native_runtime PRIVATE /utf-8)
target_compile_definitions(ltp_native_runtime PRIVATE
  NOMINMAX _DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)
target_include_directories(ltp_native_runtime PUBLIC
  "${CMAKE_BINARY_DIR}/ltp_generated"
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

# 正式包始终使用固定摘要的 ANGLE。隔离 QA 可在构建进程中显式提供另一组 DLL，
# 只替换运行时文件，不修改固定归档、import library 或插件 ABI。
set(LTP_ANGLE_RUNTIME_ROOT "${LTP_NATIVE_DEPS}/angle")
if(DEFINED ENV{LOCAL_TAG_PLAYER_ANGLE_QA_ROOT} AND
   NOT "$ENV{LOCAL_TAG_PLAYER_ANGLE_QA_ROOT}" STREQUAL "")
  file(TO_CMAKE_PATH "$ENV{LOCAL_TAG_PLAYER_ANGLE_QA_ROOT}"
    LTP_ANGLE_RUNTIME_ROOT)
  foreach(required_angle_dll IN ITEMS libEGL.dll libGLESv2.dll)
    if(NOT EXISTS "${LTP_ANGLE_RUNTIME_ROOT}/${required_angle_dll}")
      message(FATAL_ERROR
        "ANGLE QA runtime is missing ${required_angle_dll}: ${LTP_ANGLE_RUNTIME_ROOT}")
    endif()
  endforeach()
  message(STATUS "Using isolated ANGLE QA runtime: ${LTP_ANGLE_RUNTIME_ROOT}")
endif()

# 新版 mpv 只允许在隔离 QA 构建中替换运行时 DLL；正式链接仍使用固定 import
# library，因此该门禁不改变 MediaKit 插件 ABI，也不覆盖项目固定归档。
set(LTP_MPV_RUNTIME_DLL "${LTP_NATIVE_DEPS}/mpv/libmpv-2.dll")
if(DEFINED ENV{LOCAL_TAG_PLAYER_MPV_QA_DLL} AND
   NOT "$ENV{LOCAL_TAG_PLAYER_MPV_QA_DLL}" STREQUAL "")
  file(TO_CMAKE_PATH "$ENV{LOCAL_TAG_PLAYER_MPV_QA_DLL}"
    LTP_MPV_RUNTIME_DLL)
  if(NOT EXISTS "${LTP_MPV_RUNTIME_DLL}")
    message(FATAL_ERROR
      "mpv QA runtime does not exist: ${LTP_MPV_RUNTIME_DLL}")
  endif()
  message(STATUS "Using isolated mpv QA runtime: ${LTP_MPV_RUNTIME_DLL}")
endif()

set(LTP_NATIVE_RUNTIME_DLLS
  "${LTP_MPV_RUNTIME_DLL}"
  "${LTP_NATIVE_DEPS}/angle/d3dcompiler_47.dll"
  "${LTP_ANGLE_RUNTIME_ROOT}/libEGL.dll"
  "${LTP_ANGLE_RUNTIME_ROOT}/libGLESv2.dll"
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

# SDK 零分发的本机探针只在显式 QA 构建中产生。目标没有 install 规则，也不会加入
# Flutter 默认 ALL 构建；标准应用包因此不包含探针或任何 NVIDIA 文件。
option(LTP_BUILD_LOCAL_VIDEO_PLUGIN_PROBE
  "Build the local D3D11 video enhancement probe DLL" OFF)
if(LTP_BUILD_LOCAL_VIDEO_PLUGIN_PROBE)
  add_library(ltp_local_video_plugin_probe SHARED
    "${CMAKE_CURRENT_SOURCE_DIR}/../local_video_plugin_probe/local_video_plugin_probe.cpp")
  apply_standard_settings(ltp_local_video_plugin_probe)
  target_compile_options(ltp_local_video_plugin_probe PRIVATE /utf-8)
  target_compile_definitions(ltp_local_video_plugin_probe PRIVATE NOMINMAX)
  target_include_directories(ltp_local_video_plugin_probe PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}")
  set_target_properties(ltp_local_video_plugin_probe PROPERTIES
    OUTPUT_NAME "ltp_local_video_plugin_probe"
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/local_video_plugin_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/local_video_plugin_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/local_video_plugin_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/local_video_plugin_probe")

  add_executable(ltp_local_video_plugin_host_test
    "${CMAKE_CURRENT_SOURCE_DIR}/../local_video_plugin_probe/local_video_plugin_host_test.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner/local_video_enhancement_plugin.cpp")
  apply_standard_settings(ltp_local_video_plugin_host_test)
  target_compile_options(ltp_local_video_plugin_host_test PRIVATE /utf-8)
  target_compile_definitions(ltp_local_video_plugin_host_test PRIVATE NOMINMAX)
  target_include_directories(ltp_local_video_plugin_host_test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner")
  target_link_libraries(ltp_local_video_plugin_host_test PRIVATE d3d11.lib)
  set_target_properties(ltp_local_video_plugin_host_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/local_video_plugin_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/local_video_plugin_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/local_video_plugin_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/local_video_plugin_probe")
endif()

# VapourSynth 插帧宿主探针只验证本机绝对路径、ABI 导出和结构化 `vf` 往返。
# 假 VSScript 不处理视频帧且没有 install 规则，标准应用包不会包含任何运行时。
option(LTP_BUILD_VAPOURSYNTH_MOTION_PROBE
  "Build the local VapourSynth motion runtime probe" OFF)
if(LTP_BUILD_VAPOURSYNTH_MOTION_PROBE)
  add_library(ltp_vsscript_stub SHARED EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_SOURCE_DIR}/../vapoursynth_motion_probe/vsscript_stub.cpp")
  apply_standard_settings(ltp_vsscript_stub)
  target_compile_options(ltp_vsscript_stub PRIVATE /utf-8)
  target_compile_definitions(ltp_vsscript_stub PRIVATE NOMINMAX)
  set_target_properties(ltp_vsscript_stub PROPERTIES
    OUTPUT_NAME "VSScript"
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe")

  add_executable(ltp_vapoursynth_motion_host_test EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_SOURCE_DIR}/../vapoursynth_motion_probe/vapoursynth_motion_host_test.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner/vapoursynth_motion_runtime.cpp")
  apply_standard_settings(ltp_vapoursynth_motion_host_test)
  target_compile_options(ltp_vapoursynth_motion_host_test PRIVATE /utf-8)
  target_compile_definitions(ltp_vapoursynth_motion_host_test PRIVATE NOMINMAX)
  target_include_directories(ltp_vapoursynth_motion_host_test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner")
  target_link_libraries(ltp_vapoursynth_motion_host_test PRIVATE
    ltp_native_runtime)
  set_target_properties(ltp_vapoursynth_motion_host_test PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe")

  add_executable(ltp_vapoursynth_real_frame_probe EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_SOURCE_DIR}/../vapoursynth_motion_probe/vapoursynth_real_frame_probe.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner/vapoursynth_motion_runtime.cpp")
  apply_standard_settings(ltp_vapoursynth_real_frame_probe)
  target_compile_options(ltp_vapoursynth_real_frame_probe PRIVATE /utf-8)
  target_compile_definitions(ltp_vapoursynth_real_frame_probe PRIVATE NOMINMAX)
  target_include_directories(ltp_vapoursynth_real_frame_probe PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner")
  target_link_libraries(ltp_vapoursynth_real_frame_probe PRIVATE
    ltp_native_runtime)
  set_target_properties(ltp_vapoursynth_real_frame_probe PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/vapoursynth_motion_probe")

endif()

# NVOFA 驱动探针只验证系统驱动公开的 API 版本和后端导出，不依赖或分发 SDK 文件。
# 独立开关避免把 NVIDIA 驱动门禁与 VapourSynth 宿主验证错误耦合。
option(LTP_BUILD_NVOFA_DRIVER_PROBE
  "Build the local NVIDIA Optical Flow driver probe" OFF)
if(LTP_BUILD_NVOFA_DRIVER_PROBE)
  add_executable(ltp_nvofa_driver_probe EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe/nvofa_driver_probe.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner/nvidia_optical_flow_driver_probe.cpp")
  apply_standard_settings(ltp_nvofa_driver_probe)
  target_compile_options(ltp_nvofa_driver_probe PRIVATE /utf-8)
  target_compile_definitions(ltp_nvofa_driver_probe PRIVATE NOMINMAX)
  target_include_directories(ltp_nvofa_driver_probe PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner")
  set_target_properties(ltp_nvofa_driver_probe PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe")
endif()

# NVOFA CUDA 执行探针只在显式 QA 构建中使用固定提交的官方公开头文件。
# 头文件目录必须由调用方提供；目标不进入 ALL、install 或 Flutter 发布物，
# 项目因此不会分发 NVIDIA SDK 文件，也不会改变正式播放器的运行时依赖。
option(LTP_BUILD_NVOFA_EXECUTE_PROBE
  "Build the isolated NVIDIA Optical Flow CUDA execute probe" OFF)
set(LTP_NVOFA_PUBLIC_HEADER_DIR "" CACHE PATH
  "Directory containing pinned nvOpticalFlowCommon.h and nvOpticalFlowCuda.h")
if(LTP_BUILD_NVOFA_EXECUTE_PROBE)
  foreach(required_nvofa_header IN ITEMS
      nvOpticalFlowCommon.h
      nvOpticalFlowCuda.h)
    if(NOT EXISTS
        "${LTP_NVOFA_PUBLIC_HEADER_DIR}/${required_nvofa_header}")
      message(FATAL_ERROR
        "NVOFA execute probe is missing ${required_nvofa_header}: "
        "${LTP_NVOFA_PUBLIC_HEADER_DIR}")
    endif()
  endforeach()

  add_executable(ltp_nvofa_cuda_execute_probe EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe/nvofa_cuda_execute_probe.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner/d3d11_adapter_selector.cpp")
  apply_standard_settings(ltp_nvofa_cuda_execute_probe)
  target_compile_features(ltp_nvofa_cuda_execute_probe PRIVATE cxx_std_17)
  target_compile_options(ltp_nvofa_cuda_execute_probe PRIVATE /utf-8)
  target_compile_definitions(ltp_nvofa_cuda_execute_probe PRIVATE NOMINMAX)
  target_include_directories(ltp_nvofa_cuda_execute_probe PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner"
    "${LTP_NVOFA_PUBLIC_HEADER_DIR}")
  target_link_libraries(ltp_nvofa_cuda_execute_probe PRIVATE
    d3d11.lib dxgi.lib)
  set_target_properties(ltp_nvofa_cuda_execute_probe PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe")
endif()

# NVOFA VapourSynth 插帧插件只在显式本机原型构建中生成。调用方必须提供
# 固定公开 NVOFA 头文件和本机 VapourSynth SDK 头目录；目标不进入 ALL、
# install 或 Flutter bundle，因此不分发 NVIDIA/VapourSynth 文件。
option(LTP_BUILD_NVOFA_VAPOURSYNTH_PLUGIN
  "Build the local-only NVOFA VapourSynth interpolation plugin" OFF)
set(LTP_VAPOURSYNTH_INCLUDE_DIR "" CACHE PATH
  "Directory containing VapourSynth4.h for the local interpolation plugin")
if(LTP_BUILD_NVOFA_VAPOURSYNTH_PLUGIN)
  foreach(required_nvofa_header IN ITEMS
      nvOpticalFlowCommon.h
      nvOpticalFlowCuda.h)
    if(NOT EXISTS
        "${LTP_NVOFA_PUBLIC_HEADER_DIR}/${required_nvofa_header}")
      message(FATAL_ERROR
        "NVOFA VapourSynth plugin is missing ${required_nvofa_header}: "
        "${LTP_NVOFA_PUBLIC_HEADER_DIR}")
    endif()
  endforeach()
  if(NOT EXISTS "${LTP_VAPOURSYNTH_INCLUDE_DIR}/VapourSynth4.h")
    message(FATAL_ERROR
      "NVOFA VapourSynth plugin is missing VapourSynth4.h: "
      "${LTP_VAPOURSYNTH_INCLUDE_DIR}")
  endif()

  add_library(ltp_nvofa_vapoursynth_plugin MODULE EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe/nvofa_vapoursynth_plugin.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe/d3d11_midpoint_warper.cpp")
  apply_standard_settings(ltp_nvofa_vapoursynth_plugin)
  target_compile_features(ltp_nvofa_vapoursynth_plugin PRIVATE cxx_std_17)
  target_compile_options(ltp_nvofa_vapoursynth_plugin PRIVATE /utf-8)
  target_compile_definitions(ltp_nvofa_vapoursynth_plugin PRIVATE NOMINMAX)
  target_include_directories(ltp_nvofa_vapoursynth_plugin PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe"
    "${LTP_NVOFA_PUBLIC_HEADER_DIR}"
    "${LTP_VAPOURSYNTH_INCLUDE_DIR}")
  target_link_libraries(ltp_nvofa_vapoursynth_plugin PRIVATE
    d3d11.lib d3dcompiler.lib dxgi.lib)
  set_target_properties(ltp_nvofa_vapoursynth_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "ltp_nvofa_vapoursynth"
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    LIBRARY_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    LIBRARY_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    LIBRARY_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    LIBRARY_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe")

  add_executable(ltp_d3d11_midpoint_warper_probe EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe/d3d11_midpoint_warper_probe.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe/d3d11_midpoint_warper.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner/d3d11_adapter_selector.cpp")
  apply_standard_settings(ltp_d3d11_midpoint_warper_probe)
  target_compile_features(ltp_d3d11_midpoint_warper_probe PRIVATE cxx_std_17)
  target_compile_options(ltp_d3d11_midpoint_warper_probe PRIVATE /utf-8)
  target_compile_definitions(
    ltp_d3d11_midpoint_warper_probe PRIVATE NOMINMAX)
  target_include_directories(ltp_d3d11_midpoint_warper_probe PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia_optical_flow_probe"
    "${CMAKE_CURRENT_SOURCE_DIR}/../runner"
    "${LTP_NVOFA_PUBLIC_HEADER_DIR}")
  target_link_libraries(ltp_d3d11_midpoint_warper_probe PRIVATE
    d3d11.lib d3dcompiler.lib dxgi.lib)
  set_target_properties(ltp_d3d11_midpoint_warper_probe PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO
      "${CMAKE_BINARY_DIR}/nvidia_optical_flow_probe")
endif()
