part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/** 兼容性优先的 4K H.264 代理文件命令，不覆盖源文件。 */
const _proxy4kCommand =
    'ffmpeg -i input.mp4 -map 0:v:0 -map 0:a? -vf scale=3840:-2 '
    '-c:v libx264 -preset medium -crf 20 -c:a copy output.proxy-4k.mp4';

/** 空间优先的 4K HEVC 转码命令，不覆盖源文件。 */
const _transcode4kHevcCommand =
    'ffmpeg -i input.mp4 -map 0:v:0 -map 0:a? -vf scale=3840:-2 '
    '-c:v libx265 -preset medium -crf 22 -c:a copy output.hevc-4k.mp4';

/**
 * 在播放器创建前提示已确认无法硬解的超规格视频。
 *
 * 已确认会退回 8K 软件解码时不允许继续创建播放器，避免单个会话持续占满
 * CPU、私有内存和 UI 线程。返回值保留给调用方统一处理取消路径。
 */
Future<bool> showPlayerHardwareDecodeWarningDialog(
  BuildContext context,
  HardwareDecodeCompatibilityAssessment assessment,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('player.hwdecWarning.dialog'),
      title: const Text('该视频无法可靠硬件解码'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assessment.specification,
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Text(assessment.reason ?? '当前规格不在可用硬解范围内。'),
              const SizedBox(height: 10),
              const Text(
                '为避免 CPU、内存和界面持续卡顿，已阻止直接播放该文件。',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text(
                '建议先保留原文件，并生成代理文件：',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('• 流畅度优先：生成 3840×2160 H.264 代理，兼容性最好。'),
              const Text('• 空间优先：转为 4K HEVC；本机真实样本已确认可以硬解。'),
              const Text('• 不建议覆盖源文件；先抽查画质、音轨和字幕后再决定是否长期保留代理。'),
              const SizedBox(height: 12),
              const SelectableText(
                _proxy4kCommand,
                key: ValueKey('player.hwdecWarning.proxyCommand'),
              ),
              const SizedBox(height: 8),
              const SelectableText(
                _transcode4kHevcCommand,
                key: ValueKey('player.hwdecWarning.transcodeCommand'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('player.hwdecWarning.copyProxy'),
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: _proxy4kCommand));
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('已复制 4K 代理命令')),
              );
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('复制代理命令'),
        ),
        TextButton(
          key: const ValueKey('player.hwdecWarning.cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消播放'),
        ),
      ],
    ),
  );
  return result == true;
}
