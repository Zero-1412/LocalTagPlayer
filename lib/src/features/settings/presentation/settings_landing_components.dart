import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';
import '../../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 设置首页宽桌面的导航摘要与分组容器。
 *
 * 这些组件只负责呈现稳定的设置层级和策略快照，不接管二级页导航、设置状态或
 * 持久化命令；独立文件让首页编排保持轻量，也让其他设置入口复用同一分组标准。
 */
class SettingsDesktopRail extends StatelessWidget {
  const SettingsDesktopRail({
    super.key,
    required this.resumeBehavior,
    required this.rendererPreference,
    required this.confirmBeforeDeletingVideo,
    required this.autoRemoveMissingOrUnreadableVideos,
  });

  /** 当前继续观看策略。 */
  final PlaybackResumeBehavior resumeBehavior;

  /** 当前播放器渲染器偏好。 */
  final PlayerRendererPreference rendererPreference;

  /** 删除文件前是否显示确认。 */
  final bool confirmBeforeDeletingVideo;

  /** 扫描后是否清理缺失或不可读记录。 */
  final bool autoRemoveMissingOrUnreadableVideos;

  @override
  Widget build(BuildContext context) {
    final rendererLabel = PlaybackSettings.rendererLabelFor(rendererPreference);
    final resumeLabel = PlaybackSettings.resumeLabelFor(resumeBehavior);
    final deletionLabel = confirmBeforeDeletingVideo ? '删除前提示' : '不再提示';
    final missingLabel =
        autoRemoveMissingOrUnreadableVideos ? '自动清理无效记录' : '保留无效记录';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('settings.home.desktopRail'),
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: librarySurface,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
            border: Border.fromBorderSide(BorderSide(color: libraryBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '设置导航',
                style: TextStyle(
                  color: libraryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '按领域进入设置',
                style: TextStyle(color: libraryTextMuted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const _SettingsRailSection(
                icon: Icons.play_circle_outline_rounded,
                title: '播放设置',
                entryCount: '3 个入口',
                description: '播放、画质与交互',
              ),
              const SizedBox(height: 12),
              const _SettingsRailSection(
                icon: Icons.build_outlined,
                title: '数据与维护',
                entryCount: '3 个入口',
                description: '文件、备份与缓存',
              ),
              const SizedBox(height: 12),
              const _SettingsRailSection(
                icon: Icons.tune_rounded,
                title: '应用',
                entryCount: '2 个入口',
                description: '网络与版本信息',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('settings.home.policySummary'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: librarySurfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: libraryBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前策略',
                style: TextStyle(
                  color: libraryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              _SettingsPolicyRow(label: '渲染器', value: rendererLabel),
              const SizedBox(height: 8),
              _SettingsPolicyRow(label: '继续观看', value: resumeLabel),
              const SizedBox(height: 8),
              _SettingsPolicyRow(label: '文件删除', value: deletionLabel),
              const SizedBox(height: 8),
              _SettingsPolicyRow(label: '无效记录', value: missingLabel),
            ],
          ),
        ),
      ],
    );
  }
}

/** 设置首页同一语义分组中的导航入口容器。 */
class SettingsNavigationGroup extends StatelessWidget {
  const SettingsNavigationGroup({super.key, required this.children});

  /** 分组内按视觉阅读顺序排列的入口。 */
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: librarySurface,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
        border: Border.fromBorderSide(BorderSide(color: libraryBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/** 设置导航栏中的静态领域摘要，帮助用户理解入口分布。 */
class _SettingsRailSection extends StatelessWidget {
  const _SettingsRailSection({
    required this.icon,
    required this.title,
    required this.entryCount,
    required this.description,
  });

  /** 领域图标。 */
  final IconData icon;

  /** 领域名称。 */
  final String title;

  /** 领域下的入口数量。 */
  final String entryCount;

  /** 领域覆盖范围。 */
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: libraryAccent, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: libraryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    entryCount,
                    style: const TextStyle(
                      color: libraryAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(color: libraryTextMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/** 当前策略摘要中的一行键值，保持长文本在窄桌面下可换行。 */
class _SettingsPolicyRow extends StatelessWidget {
  const _SettingsPolicyRow({required this.label, required this.value});

  /** 策略名称。 */
  final String label;

  /** 策略当前值。 */
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(color: libraryTextMuted, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: libraryText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
