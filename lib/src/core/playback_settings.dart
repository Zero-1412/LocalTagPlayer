part of '../app.dart';

class PlaybackSettings {
  const PlaybackSettings({required this.hwdec});

  static const defaults = PlaybackSettings(hwdec: 'auto-safe');
  static const decoderOptions = <String>[
    'auto',
    'auto-safe',
    'auto-copy',
    'd3d11va',
    'd3d11va-copy',
    'dxva2',
    'dxva2-copy',
    'nvdec',
    'nvdec-copy',
    'cuda',
    'cuda-copy',
    'vulkan',
    'vulkan-copy',
    'no',
  ];

  final String hwdec;

  bool get hardwareDecodingEnabled => hwdec != 'no';

  PlaybackSettings copyWith({String? hwdec}) {
    return PlaybackSettings(hwdec: hwdec ?? this.hwdec);
  }

  Map<String, Object?> toJson() => {'hwdec': hwdec};

  static PlaybackSettings fromJson(Map<String, Object?> json) {
    final value = json['hwdec']?.toString();
    return PlaybackSettings(
      hwdec: decoderOptions.contains(value) ? value! : defaults.hwdec,
    );
  }

  static Future<PlaybackSettings> load() async {
    try {
      final file = await AppPaths.settingsFile();
      if (!await file.exists()) {
        return defaults;
      }
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) {
        return fromJson(json);
      }
    } catch (_) {
      return defaults;
    }
    return defaults;
  }

  Future<void> save() async {
    final file = await AppPaths.settingsFile();
    await file.writeAsString(jsonEncode(toJson()), flush: true);
  }

  static String labelFor(String value) {
    return switch (value) {
      'auto' => 'auto - \u542f\u7528\u4efb\u610f\u53ef\u7528\u89e3\u7801\u5668',
      'auto-safe' => 'auto-safe - \u542f\u7528\u6700\u4f73\u5b89\u5168\u89e3\u7801\u5668',
      'auto-copy' => 'auto-copy - \u542f\u7528\u5e26\u62f7\u8d1d\u7684\u6700\u4f73\u89e3\u7801\u5668',
      'd3d11va' => 'd3d11va - DirectX11',
      'd3d11va-copy' => 'd3d11va-copy - DirectX11 \u975e\u76f4\u901a',
      'dxva2' => 'dxva2 - Windows DXVA2',
      'dxva2-copy' => 'dxva2-copy - DXVA2 \u975e\u76f4\u901a',
      'nvdec' => 'nvdec - NVIDIA',
      'nvdec-copy' => 'nvdec-copy - NVIDIA \u975e\u76f4\u901a',
      'cuda' => 'cuda - NVIDIA CUDA',
      'cuda-copy' => 'cuda-copy - CUDA \u975e\u76f4\u901a',
      'vulkan' => 'vulkan - \u5168\u5e73\u53f0\u5b9e\u9a8c',
      'vulkan-copy' => 'vulkan-copy - Vulkan \u975e\u76f4\u901a',
      'no' => 'no - \u5173\u95ed\u786c\u4ef6\u89e3\u7801',
      _ => value,
    };
  }
}
