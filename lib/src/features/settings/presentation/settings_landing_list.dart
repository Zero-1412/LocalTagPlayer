import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';
import '../../../widgets/app_theme_tokens.dart';
import '../../../widgets/design_system/app_interaction_surface.dart';
import 'settings_landing_components.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 设置首页的无状态功能导航列表。
 *
 * 该 Widget 只展示外部传入的设置快照并转发导航回调，不拥有设置状态、持久化命令、
 * Route 或弹窗生命周期。这样可以先建立 feature 边界，同时保持原页面为唯一状态 owner。
 */
class SettingsLandingList extends StatelessWidget {
  const SettingsLandingList({
    super.key,
    required this.resumeBehavior,
    required this.rendererPreference,
    required this.confirmBeforeDeletingVideo,
    this.autoRemoveMissingOrUnreadableVideos = true,
    required this.onOpenPlayback,
    required this.onOpenVideoQuality,
    required this.onOpenPlayerInteraction,
    required this.onOpenFileDeletion,
    required this.onOpenDataBackup,
    required this.onOpenCache,
    required this.onOpenUpdateProxy,
    required this.onOpenAbout,
  });

  /** 首页直接展示的继续观看策略，避免用户必须先进入二级页才能发现当前行为。 */
  final PlaybackResumeBehavior resumeBehavior;

  /** 兼容旧页面调用的历史字段；正式后端名称始终显示 MediaKit Texture。 */
  final PlayerRendererPreference rendererPreference;

  /** 删除动作当前是否保留确认层。 */
  final bool confirmBeforeDeletingVideo;

  /** 扫描后是否自动清理缺失/不可读数据库记录。 */
  final bool autoRemoveMissingOrUnreadableVideos;

  /** 打开播放与解码二级页。 */
  final VoidCallback onOpenPlayback;

  /** 打开视频画质与增强二级页。 */
  final VoidCallback onOpenVideoQuality;

  /** 打开播放器交互二级页。 */
  final VoidCallback onOpenPlayerInteraction;

  /** 打开删除文件与回收站二级页。 */
  final VoidCallback onOpenFileDeletion;

  /** 打开视频数据备份二级页。 */
  final VoidCallback onOpenDataBackup;

  /** 打开缩略图缓存二级页。 */
  final VoidCallback onOpenCache;

  /** 打开应用更新专用网络代理二级页。 */
  final VoidCallback onOpenUpdateProxy;

  /** 打开关于与更新二级页。 */
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final playbackGroup = _buildSettingsGroup(
          title: '播放设置',
          children: [
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.playback'),
              icon: Icons.play_circle_outline_rounded,
              title: '播放与解码',
              subtitle:
                  '${PlaybackSettings.rendererLabelFor(rendererPreference)} · 继续观看：${PlaybackSettings.resumeLabelFor(resumeBehavior)}',
              statusLabel:
                  PlaybackSettings.rendererLabelFor(rendererPreference),
              onTap: onOpenPlayback,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.videoQuality'),
              icon: Icons.auto_awesome_outlined,
              title: '视频画质与增强',
              subtitle: '画面比例、缩放与色彩 · 自动画质、暗部增强与 HDR 转 SDR',
              onTap: onOpenVideoQuality,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.playerInteraction'),
              icon: Icons.tune_rounded,
              title: '播放器交互',
              subtitle: '全屏播放列表、播放器快捷键',
              onTap: onOpenPlayerInteraction,
            ),
          ],
        );
        final maintenanceGroup = _buildSettingsGroup(
          title: '数据与维护',
          children: [
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.fileDeletion'),
              icon: Icons.delete_outline_rounded,
              title: '删除文件',
              subtitle: confirmBeforeDeletingVideo
                  ? '删除前提示 · 始终移入回收站 · ${autoRemoveMissingOrUnreadableVideos ? '自动清理无效记录' : '保留无效记录'}'
                  : '不再提示 · 始终移入回收站 · ${autoRemoveMissingOrUnreadableVideos ? '自动清理无效记录' : '保留无效记录'}',
              onTap: onOpenFileDeletion,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.dataBackup'),
              icon: Icons.backup_outlined,
              title: '视频数据备份',
              subtitle: '备份开关、同步状态、检查与导出',
              onTap: onOpenDataBackup,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.cache'),
              icon: Icons.image_outlined,
              title: '缩略图缓存',
              subtitle: '缓存状态与后台任务统计',
              onTap: onOpenCache,
            ),
          ],
        );
        final appGroup = _buildSettingsGroup(
          title: '应用',
          children: [
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.updateProxy'),
              icon: Icons.lan_outlined,
              title: '网络代理',
              subtitle: '为应用更新检查与安装包下载配置 HTTP 代理',
              onTap: onOpenUpdateProxy,
            ),
            _SettingsNavigationTile(
              key: const ValueKey('settings.category.about'),
              icon: Icons.info_outline_rounded,
              title: '关于 Local Tag Player',
              subtitle: '版本信息、正式版更新与安装',
              onTap: onOpenAbout,
            ),
          ],
        );

        final List<Widget> pageChildren = wide
            ? [
                const SettingsLandingHeader(),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 238,
                      child: SettingsDesktopRail(
                        resumeBehavior: resumeBehavior,
                        rendererPreference: rendererPreference,
                        confirmBeforeDeletingVideo: confirmBeforeDeletingVideo,
                        autoRemoveMissingOrUnreadableVideos:
                            autoRemoveMissingOrUnreadableVideos,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          playbackGroup,
                          const SizedBox(height: 20),
                          maintenanceGroup,
                          const SizedBox(height: 20),
                          appGroup,
                        ],
                      ),
                    ),
                  ],
                ),
              ]
            : [
                const SettingsLandingHeader(),
                const SizedBox(height: 20),
                playbackGroup,
                const SizedBox(height: 24),
                maintenanceGroup,
                const SizedBox(height: 24),
                appGroup,
              ];

        return ListView(
          key: const ValueKey('settings.home'),
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
          children: pageChildren,
        );
      },
    );
  }

  /** 构建设置分组；入口顺序和每个 section 的回调由调用方明确提供。 */
  Widget _buildSettingsGroup({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroupTitle(title: title),
        const SizedBox(height: 8),
        SettingsNavigationGroup(children: children),
      ],
    );
  }
}

/**
 * 设置页面复用的功能分组标题。
 *
 * 该无状态视觉组件不读取设置或触发命令，允许迁移期旧页面与新 feature 共用同一呈现。
 */
class SettingsGroupTitle extends StatelessWidget {
  const SettingsGroupTitle({super.key, required this.title});

  /** 分组名称。 */
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: libraryTextMuted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/** 设置首页的稳定上下文头部，不持有设置状态或导航命令。 */
class SettingsLandingHeader extends StatelessWidget {
  const SettingsLandingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: appAccentViolet.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: appAccentViolet.withValues(alpha: 0.20)),
          ),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.tune_rounded, color: libraryAccent, size: 20),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置工作区',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              const Text(
                '按功能进入设置，当前播放与数据状态会保留在对应入口。',
                style: TextStyle(color: libraryTextMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/** 设置首页中打开二级页的单个功能入口。 */
class _SettingsNavigationTile extends StatelessWidget {
  const _SettingsNavigationTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.statusLabel,
  });

  /** 功能类型图标。 */
  final IconData icon;

  /** 功能名称。 */
  final String title;

  /** 功能范围摘要。 */
  final String subtitle;

  /** 需要在设置首屏直接暴露的关键当前状态；普通入口保持为空。 */
  final String? statusLabel;

  /** 点击后进入对应二级页。 */
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppInteractionSurface(
      onTap: onTap,
      semanticLabel: '打开$title',
      backgroundColor: librarySurfaceAlt,
      borderRadius: AppRadius.card,
      showBorder: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 460;
          return Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: appAccentViolet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: SizedBox.square(
                  dimension: 42,
                  child: Icon(icon, color: appAccentViolet),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: libraryTextMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (statusLabel != null && !compact) ...[
                Chip(
                  key: const ValueKey('settings.resumeBehavior.summary'),
                  label: Text(statusLabel!),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, color: libraryTextMuted),
            ],
          );
        },
      ),
    );
  }
}
