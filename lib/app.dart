import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/layout.dart';
import 'core/liquid_glass.dart';
import 'core/look.dart';
import 'core/native.dart';
import 'core/navigation.dart';
import 'core/prefs.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/unread_monitor.dart';
import 'core/widgets/covered_snapshot.dart';
import 'features/shell/root_shell.dart';

class InfApp extends StatefulWidget {
  const InfApp({super.key});

  @override
  State<InfApp> createState() => _InfAppState();
}

typedef _Appearance = ({
  VisualStyle style,
  LiquidTier liquidTier,
  double? blur,
  double? clarity,
  double? refraction,
  double? liquidClarity,
  double? liquidShine,
  AccentTheme accent,
  ThemeMode mode,
  double textScale,
  DeviceLayout layout,
});

_Appearance _appearanceOf(Prefs prefs) => (
      style: prefs.visualStyle,
      liquidTier: prefs.liquidTier,
      blur: prefs.glassBlur,
      clarity: prefs.glassClarity,
      refraction: prefs.liquidRefraction,
      liquidClarity: prefs.liquidClarity,
      liquidShine: prefs.liquidShine,
      accent: prefs.accent,
      mode: prefs.themeMode,
      textScale: prefs.textScale,
      layout: prefs.deviceLayout,
    );

class _InfAppState extends State<InfApp> {
  // Only the appearance preferences rebuild the shell. Anything else Prefs stores (the viewed
  // history, written as a post opens; drafts; search history) would otherwise rebuild the whole
  // MaterialApp, and a fresh ThemeData runs the theme animation across every page for its full
  // length, in the middle of the page transition.
  late _Appearance _appearance = _appearanceOf(Prefs.instance);

  /// Whether the step-down question has already been put this run.
  bool _askedAboutDowngrade = false;

  @override
  void initState() {
    super.initState();
    Prefs.instance.addListener(_onPrefs);
    WeiboApi.captchaSolver = solveCaptcha;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      Native.requestPeakRefreshRate();
      await Session.instance.init();
      await Session.instance.refresh();
      UnreadMonitor.instance.start();
    });
  }

  @override
  void dispose() {
    Prefs.instance.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() {
    final next = _appearanceOf(Prefs.instance);
    if (next != _appearance) setState(() => _appearance = next);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = _appearance;
    final look = InfLook(
      appearance.style,
      blur: appearance.blur ?? InfLook.defaultBlur,
      clarity: appearance.clarity ?? InfLook.defaultClarity,
      refraction: appearance.refraction ?? InfLook.defaultRefraction,
      liquidClarity: appearance.liquidClarity ?? InfLook.defaultLiquidClarity,
      liquidShine: appearance.liquidShine ?? InfLook.defaultLiquidShine,
      liquidTier: appearance.liquidTier,
    );
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'INF',
      debugShowCheckedModeBanner: false,
      theme: infTheme(Brightness.light, appearance.accent, look),
      darkTheme: infTheme(Brightness.dark, appearance.accent, look),
      themeMode: appearance.mode,
      themeAnimationDuration: const Duration(milliseconds: 260),
      themeAnimationCurve: Curves.easeOutCubic,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final platformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final dark = switch (appearance.mode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformDark,
        };
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ));
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
          child: MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(appearance.textScale)),
            child: InfLayout(
              device: appearance.layout,
              child: LiquidGlassTheme(
                child: InfGlassQuality(
                  look: look,
                  onDowngraded: _askAboutDowngrade,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
      home: const CoveredSnapshot(child: RootShell()),
    );
  }

  /// Asks once per choice of ultra whether to drop to the standard glass, when the device turns
  /// out unable to keep the premium one up.
  ///
  /// The answer is remembered on disk: a device that cannot draw the glass fast enough asks on the
  /// first cold start and then not again, rather than on every launch (and every time the scope
  /// steps down a level, which happens twice — frost first, then the tier). Choosing「保持极致」
  /// leaves the tier as it is and is itself an answer, so the question does not come back until
  /// ultra is picked again in the settings.
  void _askAboutDowngrade() {
    if (_askedAboutDowngrade) return;
    _askedAboutDowngrade = true;
    if (Prefs.instance.liquidUltraHinted) return;
    Prefs.instance.setLiquidUltraHinted();
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      final change = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('液态玻璃有点吃力'),
          content: const Text('「极致」的折射和磨砂在这台设备上会让页面卡顿。要改成「标准」吗？\n\n标准档保留玻璃的折射与边缘高光，只是少了立体的厚度和融合；之后也可以在设置里改回来。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('保持极致'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('改为标准'),
            ),
          ],
        ),
      );
      if (change == true) await Prefs.instance.setLiquidTier(LiquidTier.standard);
    });
  }
}
