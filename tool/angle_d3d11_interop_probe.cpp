/**
 * 验证 ANGLE 的 EGL/D3D11 设备查询与共享纹理 pbuffer 互操作。
 *
 * 该探针不依赖 Flutter、MediaKit 或 libmpv，用于先区分 ANGLE 本身的互操作能力
 * 与播放器渲染边界问题。成功条件包括：D3D11 backend 初始化、EGLDevice 查询、
 * 共享纹理创建、OpenGL ES 清屏，以及从原始 D3D11 设备读回预期像素。
 */

#include <windows.h>

#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

#include <array>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <string>

namespace {

using Microsoft::WRL::ComPtr;

/**
 * 输出 EGL 错误并返回失败码。
 *
 * @param stage 发生错误的验证阶段。
 */
int FailEgl(const char *stage) {
  std::cerr << "FAIL stage=" << stage << " egl=0x" << std::hex << eglGetError()
            << std::dec << std::endl;
  return 1;
}

/**
 * 输出 HRESULT 并返回失败码。
 *
 * @param stage 发生错误的 D3D11 验证阶段。
 * @param result Windows API 返回值。
 */
int FailHr(const char *stage, HRESULT result) {
  std::cerr << "FAIL stage=" << stage << " hresult=0x" << std::hex
            << static_cast<unsigned long>(result) << std::dec << std::endl;
  return 1;
}

/**
 * 查询 D3D11 设备对应适配器的 LUID。
 *
 * @param device 要查询的设备；调用方保留所有权。
 * @param luid 接收适配器身份。
 */
bool QueryAdapterLuid(ID3D11Device *device, LUID *luid) {
  ComPtr<IDXGIDevice> dxgi_device;
  if (FAILED(device->QueryInterface(IID_PPV_ARGS(&dxgi_device)))) {
    return false;
  }
  ComPtr<IDXGIAdapter> adapter;
  if (FAILED(dxgi_device->GetAdapter(&adapter))) {
    return false;
  }
  DXGI_ADAPTER_DESC description{};
  if (FAILED(adapter->GetDesc(&description))) {
    return false;
  }
  *luid = description.AdapterLuid;
  return true;
}

/**
 * 判断空格分隔的 EGL 扩展列表是否包含完整扩展名。
 */
bool HasExtension(const std::string &extensions, const char *extension) {
  const std::string needle(extension);
  std::size_t position = 0;
  while ((position = extensions.find(needle, position)) != std::string::npos) {
    const bool starts_at_boundary =
        position == 0 || extensions[position - 1] == ' ';
    const std::size_t end = position + needle.size();
    const bool ends_at_boundary =
        end == extensions.size() || extensions[end] == ' ';
    if (starts_at_boundary && ends_at_boundary) {
      return true;
    }
    position = end;
  }
  return false;
}

} // namespace

/**
 * 创建一张由原始 D3D11 设备持有的共享纹理，再由 ANGLE D3D11 backend
 * 通过 EGL pbuffer 写入并读回，以验证跨设备共享链路。
 */
int main() {
  constexpr UINT kWidth = 16;
  constexpr UINT kHeight = 16;

  const std::array<D3D_FEATURE_LEVEL, 4> feature_levels = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
  };
  ComPtr<ID3D11Device> host_device;
  ComPtr<ID3D11DeviceContext> host_context;
  D3D_FEATURE_LEVEL selected_feature_level{};
  HRESULT result = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT, feature_levels.data(),
      static_cast<UINT>(feature_levels.size()), D3D11_SDK_VERSION, &host_device,
      &selected_feature_level, &host_context);
  if (FAILED(result)) {
    return FailHr("D3D11CreateDevice", result);
  }

  D3D11_TEXTURE2D_DESC texture_description{};
  texture_description.Width = kWidth;
  texture_description.Height = kHeight;
  texture_description.MipLevels = 1;
  texture_description.ArraySize = 1;
  texture_description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  texture_description.SampleDesc.Count = 1;
  texture_description.Usage = D3D11_USAGE_DEFAULT;
  texture_description.BindFlags =
      D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  texture_description.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  ComPtr<ID3D11Texture2D> shared_texture;
  result = host_device->CreateTexture2D(&texture_description, nullptr,
                                        &shared_texture);
  if (FAILED(result)) {
    return FailHr("CreateSharedTexture", result);
  }
  ComPtr<IDXGIResource> shared_resource;
  result = shared_texture.As(&shared_resource);
  if (FAILED(result)) {
    return FailHr("QuerySharedResource", result);
  }
  HANDLE shared_handle = nullptr;
  result = shared_resource->GetSharedHandle(&shared_handle);
  if (FAILED(result) || shared_handle == nullptr) {
    return FailHr("GetSharedHandle", result);
  }

  const auto get_platform_display =
      reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
          eglGetProcAddress("eglGetPlatformDisplayEXT"));
  const auto query_display_attrib =
      reinterpret_cast<PFNEGLQUERYDISPLAYATTRIBEXTPROC>(
          eglGetProcAddress("eglQueryDisplayAttribEXT"));
  const auto query_device_attrib =
      reinterpret_cast<PFNEGLQUERYDEVICEATTRIBEXTPROC>(
          eglGetProcAddress("eglQueryDeviceAttribEXT"));
  const auto query_device_string =
      reinterpret_cast<PFNEGLQUERYDEVICESTRINGEXTPROC>(
          eglGetProcAddress("eglQueryDeviceStringEXT"));
  if (get_platform_display == nullptr || query_display_attrib == nullptr ||
      query_device_attrib == nullptr || query_device_string == nullptr) {
    std::cerr << "FAIL stage=ResolveEglDeviceFunctions" << std::endl;
    return 1;
  }

  const EGLint display_attributes[] = {
      EGL_PLATFORM_ANGLE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
      EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE,
      EGL_NONE,
  };
  EGLDisplay display = get_platform_display(
      EGL_PLATFORM_ANGLE_ANGLE, EGL_DEFAULT_DISPLAY, display_attributes);
  if (display == EGL_NO_DISPLAY) {
    return FailEgl("eglGetPlatformDisplayEXT");
  }

  EGLint egl_major = 0;
  EGLint egl_minor = 0;
  if (eglInitialize(display, &egl_major, &egl_minor) == EGL_FALSE) {
    return FailEgl("eglInitialize");
  }

  const char *client_extensions_value =
      eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  const char *display_extensions_value =
      eglQueryString(display, EGL_EXTENSIONS);
  const char *vendor_value = eglQueryString(display, EGL_VENDOR);
  const char *version_value = eglQueryString(display, EGL_VERSION);
  const std::string client_extensions =
      client_extensions_value == nullptr ? "" : client_extensions_value;
  const std::string display_extensions =
      display_extensions_value == nullptr ? "" : display_extensions_value;

  EGLAttrib device_attribute = 0;
  if (query_display_attrib(display, EGL_DEVICE_EXT, &device_attribute) ==
      EGL_FALSE) {
    eglTerminate(display);
    return FailEgl("eglQueryDisplayAttribEXT");
  }
  const auto egl_device = reinterpret_cast<EGLDeviceEXT>(device_attribute);
  const char *device_extensions_value =
      query_device_string(egl_device, EGL_EXTENSIONS);
  const std::string device_extensions =
      device_extensions_value == nullptr ? "" : device_extensions_value;
  EGLAttrib d3d_device_attribute = 0;
  if (query_device_attrib(egl_device, EGL_D3D11_DEVICE_ANGLE,
                          &d3d_device_attribute) == EGL_FALSE) {
    eglTerminate(display);
    return FailEgl("eglQueryDeviceAttribEXT");
  }
  auto *angle_device = reinterpret_cast<ID3D11Device *>(d3d_device_attribute);
  if (angle_device == nullptr) {
    eglTerminate(display);
    std::cerr << "FAIL stage=NullAngleD3D11Device" << std::endl;
    return 1;
  }

  LUID host_luid{};
  LUID angle_luid{};
  const bool adapter_luid_available =
      QueryAdapterLuid(host_device.Get(), &host_luid) &&
      QueryAdapterLuid(angle_device, &angle_luid);
  const bool adapter_luid_matches = adapter_luid_available &&
                                    host_luid.HighPart == angle_luid.HighPart &&
                                    host_luid.LowPart == angle_luid.LowPart;

  const EGLint config_attributes[] = {
      EGL_SURFACE_TYPE,
      EGL_PBUFFER_BIT,
      EGL_RENDERABLE_TYPE,
      EGL_OPENGL_ES2_BIT,
      EGL_RED_SIZE,
      8,
      EGL_GREEN_SIZE,
      8,
      EGL_BLUE_SIZE,
      8,
      EGL_ALPHA_SIZE,
      8,
      EGL_NONE,
  };
  EGLConfig config = nullptr;
  EGLint config_count = 0;
  if (eglChooseConfig(display, config_attributes, &config, 1, &config_count) ==
          EGL_FALSE ||
      config_count != 1) {
    eglTerminate(display);
    return FailEgl("eglChooseConfig");
  }

  const EGLint context_attributes[] = {
      EGL_CONTEXT_CLIENT_VERSION,
      2,
      EGL_NONE,
  };
  EGLContext context =
      eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
  if (context == EGL_NO_CONTEXT) {
    eglTerminate(display);
    return FailEgl("eglCreateContext");
  }

  const EGLint surface_attributes[] = {
      EGL_WIDTH,          static_cast<EGLint>(kWidth),
      EGL_HEIGHT,         static_cast<EGLint>(kHeight),
      EGL_TEXTURE_TARGET, EGL_TEXTURE_2D,
      EGL_TEXTURE_FORMAT, EGL_TEXTURE_RGBA,
      EGL_NONE,
  };
  EGLSurface surface = eglCreatePbufferFromClientBuffer(
      display, EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE,
      reinterpret_cast<EGLClientBuffer>(shared_handle), config,
      surface_attributes);
  if (surface == EGL_NO_SURFACE) {
    eglDestroyContext(display, context);
    eglTerminate(display);
    return FailEgl("eglCreatePbufferFromClientBuffer");
  }

  if (eglMakeCurrent(display, surface, surface, context) == EGL_FALSE) {
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);
    return FailEgl("eglMakeCurrent");
  }

  glViewport(0, 0, kWidth, kHeight);
  glClearColor(0.125F, 0.5F, 0.75F, 1.0F);
  glClear(GL_COLOR_BUFFER_BIT);
  glFinish();
  const GLenum gl_error = glGetError();

  D3D11_TEXTURE2D_DESC staging_description = texture_description;
  staging_description.Usage = D3D11_USAGE_STAGING;
  staging_description.BindFlags = 0;
  staging_description.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  staging_description.MiscFlags = 0;
  ComPtr<ID3D11Texture2D> staging_texture;
  result = host_device->CreateTexture2D(&staging_description, nullptr,
                                        &staging_texture);
  if (FAILED(result)) {
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);
    return FailHr("CreateStagingTexture", result);
  }

  host_context->CopyResource(staging_texture.Get(), shared_texture.Get());
  D3D11_MAPPED_SUBRESOURCE mapped{};
  result =
      host_context->Map(staging_texture.Get(), 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(result)) {
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);
    return FailHr("MapStagingTexture", result);
  }

  const auto *pixel = static_cast<const std::uint8_t *>(mapped.pData);
  const std::array<std::uint8_t, 4> bgra = {
      pixel[0],
      pixel[1],
      pixel[2],
      pixel[3],
  };
  host_context->Unmap(staging_texture.Get(), 0);

  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglDestroySurface(display, surface);
  eglDestroyContext(display, context);
  eglTerminate(display);

  const bool pixel_matches = bgra[0] >= 188 && bgra[0] <= 193 &&
                             bgra[1] >= 125 && bgra[1] <= 130 &&
                             bgra[2] >= 30 && bgra[2] <= 34 && bgra[3] == 255;
  const bool required_extensions =
      HasExtension(client_extensions, "EGL_ANGLE_platform_angle") &&
      HasExtension(device_extensions, "EGL_ANGLE_device_d3d") &&
      HasExtension(display_extensions,
                   "EGL_ANGLE_surface_d3d_texture_2d_share_handle");
  const bool success = gl_error == GL_NO_ERROR && adapter_luid_matches &&
                       required_extensions && pixel_matches;

  std::cout << "ANGLE_VENDOR=" << (vendor_value == nullptr ? "" : vendor_value)
            << std::endl;
  std::cout << "ANGLE_EGL_VERSION="
            << (version_value == nullptr ? "" : version_value) << std::endl;
  std::cout << "EGL_INITIALIZED=" << egl_major << "." << egl_minor << std::endl;
  std::cout << "D3D_FEATURE_LEVEL=0x" << std::hex
            << static_cast<unsigned int>(selected_feature_level) << std::dec
            << std::endl;
  std::cout << "EGL_ANGLE_DEVICE_D3D="
            << HasExtension(device_extensions, "EGL_ANGLE_device_d3d")
            << std::endl;
  std::cout << "EGL_ANGLE_SHARED_TEXTURE="
            << HasExtension(display_extensions,
                            "EGL_ANGLE_surface_d3d_texture_2d_share_handle")
            << std::endl;
  std::cout << "ADAPTER_LUID_MATCH=" << adapter_luid_matches << std::endl;
  std::cout << "PIXEL_BGRA=" << static_cast<unsigned int>(bgra[0]) << ","
            << static_cast<unsigned int>(bgra[1]) << ","
            << static_cast<unsigned int>(bgra[2]) << ","
            << static_cast<unsigned int>(bgra[3]) << std::endl;
  std::cout << "RESULT=" << (success ? "PASS" : "FAIL") << std::endl;
  return success ? 0 : 1;
}
