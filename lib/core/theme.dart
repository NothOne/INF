import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'look.dart';
import 'prefs.dart';

Color accentColor(AccentTheme accent, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (accent) {
    AccentTheme.brand => Color(dark ? 0xFF9DB0FF : 0xFF3B5BDB),
    AccentTheme.orange => Color(dark ? 0xFFFFB866 : 0xFFFF6D00),
    AccentTheme.green => Color(dark ? 0xFF7FD3A3 : 0xFF2E9E5B),
    AccentTheme.purple => Color(dark ? 0xFFCBA8F0 : 0xFF7B3FBF),
  };
}

ThemeData infTheme(Brightness brightness, AccentTheme accent, [InfLook look = InfLook.classic]) {
  final dark = brightness == Brightness.dark;
  final glass = look.glass;
  final seed = accentColor(accent, brightness);
  final base = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final scheme = base.copyWith(
    primary: seed,
    secondary: Color(dark ? 0xFFFFB866 : 0xFFFF8C00),
    surface: Color(dark ? 0xFF111218 : 0xFFFBFAFF),
    surfaceContainerLowest: Color(dark ? 0xFF0C0D11 : 0xFFFFFFFF),
    surfaceContainerLow: Color(dark ? 0xFF16171D : 0xFFF7F5FF),
    surfaceContainer: Color(dark ? 0xFF1B1C23 : 0xFFF3F1FC),
    surfaceContainerHigh: Color(dark ? 0xFF22232C : 0xFFEFEDF9),
    surfaceContainerHighest: Color(dark ? 0xFF2A2B36 : 0xFFE9E6F5),
    onSurface: Color(dark ? 0xFFF3F1FA : 0xFF1B1B21),
    onSurfaceVariant: Color(dark ? 0xFFB8B6C8 : 0xFF666477),
    outlineVariant: Color(dark ? 0xFF353644 : 0xFFE2DFF0),
    surfaceTint: Colors.transparent,
  );

  final textTheme = Typography.material2021(platform: TargetPlatform.android).black.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  final body = textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.62);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [look],
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        // Fade-forwards for taps; while the system back gesture is in progress the page shrinks
        // with the finger and shows the one underneath.
        TargetPlatform.android: const PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
        // HarmonyOS has no predictive back, so it gets the same fade-forwards without it. Found by
        // name: only the OpenHarmony fork of Flutter has this platform.
        for (final platform in TargetPlatform.values)
          if (platform.name == 'ohos') platform: const FadeForwardsPageTransitionsBuilder(),
      },
    ),
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    textTheme: textTheme.copyWith(
      bodyLarge: body,
      bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.55),
      bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.4),
      titleLarge: textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium: textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      titleSmall: textTheme.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      labelLarge: textTheme.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelMedium: textTheme.labelMedium?.copyWith(fontSize: 12),
      labelSmall: textTheme.labelSmall?.copyWith(fontSize: 11),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.7),
      thickness: 0.7,
      space: 0.7,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2D2E3A) : const Color(0xFF2B2B33),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: glass ? scheme.surfaceContainerLow.withValues(alpha: dark ? 0.94 : 0.96) : null,
      surfaceTintColor: Colors.transparent,
      elevation: glass ? 10 : null,
      shadowColor: glass ? Colors.black.withValues(alpha: dark ? 0.5 : 0.18) : null,
      shape: glass
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: GlassSurface.rimOf(scheme), width: 0.8),
            )
          : null,
    ),
    dialogTheme: glass
        ? DialogThemeData(
            backgroundColor: scheme.surfaceContainerLow.withValues(alpha: dark ? 0.95 : 0.97),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(color: GlassSurface.rimOf(scheme), width: 0.8),
            ),
          )
        : null,
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: InfChrome.forLook(look).fill(scheme, scheme.surfaceContainerHigh, 0.7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
    ),
  );
}