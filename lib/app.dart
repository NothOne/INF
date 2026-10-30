import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/look.dart';
import 'core/native.dart';
import 'core/prefs.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/unread_monitor.dart';
import 'features/shell/root_shell.dart';

class InfApp extends StatefulWidget {
  const InfApp({super.key});

  @override
  State<InfApp> createState() => _InfAppState();
}

typedef _Appearance = ({
  VisualStyle style,
  double? blur,
  double? clarity,
  AccentTheme accent,
  ThemeMode mode,
  double textScale,
});

_Appearance _appearanceOf(Prefs prefs) => (
      style: prefs.visualStyle,
      blur: prefs.glassBlur,
      clarity: prefs.glassClarity,
      accent: prefs.accent,
      mode: prefs.themeMode,
      textScale: prefs.textScale,
    );

class _InfAppState extends State<InfApp> {
  // Only the appearance preferences rebuild the shell. Anything else Prefs stores (the viewed
  // history, written as a post opens; drafts; search history) would otherwise rebuild the whole
  // MaterialApp, and a fresh ThemeData runs the theme animation across every page for its full
  // length, in the middle of the page transition.
  late _Appearance _appearance = _appearanceOf(Prefs.instance);

  @override
  void initState() {
    super.initState();
    Prefs.instance.addListener(_onPrefs);
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
    );
    return MaterialApp(
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
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const RootShell(),
    );
  }
}
