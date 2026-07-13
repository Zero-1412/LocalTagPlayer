import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

part 'core/app_paths.dart';
part 'core/layout_size.dart';
part 'core/playback_settings.dart';
part 'core/tag_rules.dart';
part 'models/video_item.dart';
part 'models/media_details.dart';
part 'models/platform_models.dart';
part 'repositories/repository_interfaces.dart';
part 'services/library_metadata_persistence.dart';
part 'services/library_load_diagnostics.dart';
part 'services/library_scan_ui_diagnostics.dart';
part 'services/library_scan_backend.dart';
part 'services/library_scan_coordinator.dart';
part 'services/library_count_refresh_coordinator.dart';
part 'services/library_tag_persistence.dart';
part 'services/library_tag_maintenance.dart';
part 'services/library_video_persistence.dart';
part 'services/library_store.dart';
part 'services/playback_snapshot_write_queue.dart';
part 'services/desktop_window_state_service.dart';
part 'services/bulk_path_relink_service.dart';
part 'services/library_scan_service.dart';
part 'services/tag_query_service.dart';
part 'services/external_media_tools.dart';
part 'services/media_probe_backend.dart';
part 'services/thumbnail_service.dart';
part 'services/media_details_service.dart';
part 'services/player_hardware_acceleration.dart';
part 'services/player_hardware_compatibility.dart';
part 'services/media_kit_player_backend.dart';
part 'services/windows_native_player_backend.dart';
part 'services/player_memory_diagnostics.dart';
part 'platform/platform_interfaces.dart';
part 'platform/desktop_file_location_service.dart';
part 'pages/library_page_helpers.dart';
part 'pages/library_page.dart';
part 'pages/missing_relink_page.dart';
part 'pages/tag_manager_page.dart';
part 'pages/player_context_panel.dart';
part 'pages/player_dialog_content.dart';
part 'pages/player_delete_dialog.dart';
part 'pages/player_hardware_decode_warning_dialog.dart';
part 'pages/player_diagnostics_dialog.dart';
part 'pages/player_open_request_controller.dart';
part 'pages/player_resume_dialog.dart';
part 'pages/player_open_failure_panel.dart';
part 'pages/player_playback_mode.dart';
part 'pages/player_playback_controller.dart';
part 'pages/player_queue_sidebar.dart';
part 'pages/player_page.dart';
part 'widgets/library_smoke_keys.dart';
part 'widgets/library_sort_control.dart';
part 'widgets/library_tag_discovery_panel.dart';
part 'widgets/library_local_view.dart';
part 'widgets/library_video_results.dart';
part 'widgets/library_widgets.dart';

const _appAccent = Color(0xff0f766e);
const _appAccentStrong = Color(0xff0b5d57);
const _appAccentViolet = Color(0xff6d5dfc);
const _appShell = Color(0xff111827);
const _appBackground = Color(0xfff4f7fb);
const _appSurface = Color(0xfffbfdfc);
const _appSurfaceAlt = Color(0xfff4f8f7);
const _appPanel = Color(0xffffffff);
const _appBorder = Color(0xffdce4ee);
const _appTextMuted = Color(0xff62706d);
const _appText = Color(0xff17202e);
const _appSoftShadow = [
  BoxShadow(
    color: Color(0x140f172a),
    blurRadius: 24,
    offset: Offset(0, 12),
  ),
];
const _motionDuration = Duration(milliseconds: 180);
const _motionCurve = Curves.easeOutCubic;
const _thumbnailWidth = 384;
const _thumbnailFfmpegTimeout = Duration(seconds: 10);
const _thumbnailPlayerTimeout = Duration(seconds: 8);
const _mediaProbeTimeout = Duration(seconds: 6);

Route<T> _smoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: _motionCurve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.018, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Future<void> bootstrapLocalTagPlayer() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await DesktopWindowStateService.instance.initialize();
  runApp(const LocalTagPlayerApp());
}

class LocalTagPlayerApp extends StatelessWidget {
  const LocalTagPlayerApp({super.key});
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff2f6f73),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: '\u672c\u5730\u6807\u7b7e\u64ad\u653e\u5668',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        fontFamilyFallback: const [
          'Microsoft YaHei',
          'Microsoft YaHei UI',
          'SimHei',
          'Segoe UI',
        ],
        useMaterial3: true,
        scaffoldBackgroundColor: _appBackground,
        cardTheme: const CardThemeData(
          elevation: 0,
          color: _appSurface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: _appBorder),
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: _appSurface,
          foregroundColor: Color(0xff1d2725),
          centerTitle: false,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _appSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _appBorder),
          ),
          titleTextStyle: const TextStyle(
            color: Color(0xff1d2725),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: _appSurface,
          surfaceTintColor: Colors.transparent,
          textStyle: const TextStyle(color: _appText, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _appBorder),
          ),
        ),
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(_appSurface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: _appBorder),
              ),
            ),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: _appSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _appShell,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _appAccent,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 40),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _appAccentStrong,
            side: const BorderSide(color: _appBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 40),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: _appAccentStrong,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _appSurfaceAlt,
          selectedColor: const Color(0xffd7eeea),
          disabledColor: const Color(0xffe7ecea),
          side: const BorderSide(color: _appBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelStyle: const TextStyle(
              color: Color(0xff20302d), fontWeight: FontWeight.w600),
          secondaryLabelStyle: const TextStyle(
              color: _appAccentStrong, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          showCheckmark: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: _appSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: _appBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: _appBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: _appAccent, width: 1.4),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: const WidgetStatePropertyAll(BorderSide(color: _appBorder)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? const Color(0xffd7eeea)
                  : _appSurface;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? _appAccentStrong
                  : _appTextMuted;
            }),
          ),
        ),
      ),
      home: const LibraryPage(),
    );
  }
}
