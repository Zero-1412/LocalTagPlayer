part of '../main.dart';

const _appAccent = Color(0xff0f766e);
const _appAccentStrong = Color(0xff0b5d57);
const _appBackground = Color(0xffeef3f1);
const _appSurface = Color(0xfffbfdfc);
const _appSurfaceAlt = Color(0xfff4f8f7);
const _appBorder = Color(0xffd6e2df);
const _appTextMuted = Color(0xff62706d);
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
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
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _appAccent,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 40),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _appAccentStrong,
            side: const BorderSide(color: _appBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 40),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: _appAccentStrong,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _appSurfaceAlt,
          selectedColor: const Color(0xffd7eeea),
          disabledColor: const Color(0xffe7ecea),
          side: const BorderSide(color: _appBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelStyle: const TextStyle(color: Color(0xff20302d), fontWeight: FontWeight.w600),
          secondaryLabelStyle: const TextStyle(color: _appAccentStrong, fontWeight: FontWeight.w700),
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





