import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/liquid_glass.dart';
import 'package:inf_flutter/core/look.dart';
import 'package:inf_flutter/core/prefs.dart' show VisualStyle;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show GlassButton, GlassContainer, GlassThemeSettings;

void main() {
  group('liquid glass theme', () {
    GlassThemeSettings light(InfLook look) => liquidGlassTheme(look).light.settings!;
    GlassThemeSettings dark(InfLook look) => liquidGlassTheme(look).dark.settings!;

    test('the default sliders are the iOS 27 glass', () {
      const look = InfLook(VisualStyle.liquid);
      for (final (ours, preset) in [
        (light(look), GlassThemeSettings.ios27Light),
        (dark(look), GlassThemeSettings.ios27Dark),
      ]) {
        expect(ours.thickness, closeTo(preset.thickness!, 1e-9));
        expect(ours.refractiveIndex, closeTo(preset.refractiveIndex!, 1e-9));
        expect(ours.frost, closeTo(preset.frost!, 1e-9));
        expect(ours.rimLight, closeTo(preset.rimLight!, 1e-9));
        expect(ours.glassColor!.a, closeTo(preset.glassColor!.a, 0.01));
      }
    });

    test('each slider moves its glass one way only', () {
      var last = (alpha: double.infinity, frost: double.infinity, thickness: 0.0, rim: 0.0);
      for (var i = 0; i <= 10; i++) {
        final t = i / 10;
        final clear = light(InfLook(VisualStyle.liquid, liquidClarity: t));
        final bent = light(InfLook(VisualStyle.liquid, refraction: t));
        final shiny = light(InfLook(VisualStyle.liquid, liquidShine: t));
        if (i > 0) {
          expect(clear.glassColor!.a, lessThan(last.alpha));
          expect(clear.frost!, lessThan(last.frost));
          expect(bent.thickness!, greaterThan(last.thickness));
          expect(shiny.rimLight!, greaterThan(last.rim));
        }
        last = (alpha: clear.glassColor!.a, frost: clear.frost!, thickness: bent.thickness!, rim: shiny.rimLight!);
      }
      // The clear end still tints a little, so text on glass keeps a floor under it.
      expect(light(const InfLook(VisualStyle.liquid, liquidClarity: 1)).glassColor!.a, greaterThan(0));
      expect(dark(const InfLook(VisualStyle.liquid, liquidClarity: 1)).glassColor!.a, greaterThan(0));
    });

    test('a tint replaces the glass colour', () {
      const tint = Color(0xCC112233);
      final theme = liquidGlassTheme(const InfLook(VisualStyle.liquid), tint: tint);
      expect(theme.light.settings!.glassColor, tint);
      expect(theme.dark.settings!.glassColor, tint);
    });

    test('each style keeps its own chrome', () {
      expect(InfChrome.forLook(const InfLook(VisualStyle.classic)), isA<ClassicChrome>());
      expect(InfChrome.forLook(const InfLook(VisualStyle.glass)), isA<GlassChrome>());
      expect(InfChrome.forLook(const InfLook(VisualStyle.liquid)), isA<LiquidChrome>());
    });
  });

  testWidgets('only liquid draws its snackbar as glass', (tester) async {
    Future<SnackBar> capture(InfChrome chrome) async {
      late SnackBar bar;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [InfLook(VisualStyle.liquid)]),
        home: Builder(
          builder: (context) {
            bar = chrome.snackBar(context, const Text('已复制'));
            return const SizedBox.shrink();
          },
        ),
      ));
      return bar;
    }

    for (final chrome in [const ClassicChrome(), const GlassChrome()]) {
      final bar = await capture(chrome);
      expect(bar.backgroundColor, isNull);
      expect(bar.content, isA<Text>());
    }
    final liquid = await capture(const LiquidChrome());
    expect(liquid.backgroundColor, Colors.transparent);
    expect(liquid.elevation, 0);
    expect((liquid.content as LiquidGlassTheme).child, isA<GlassContainer>());
  });

  testWidgets('the liquid compose button is a glass button that reports its own context', (tester) async {
    BuildContext? pressed;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [InfLook(VisualStyle.liquid)]),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: const LiquidChrome().floatingButton(
              context,
              tooltip: '发微博',
              icon: const Icon(Icons.edit_rounded),
              onPressed: (buttonContext) => pressed = buttonContext,
            ),
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(GlassButton)), const Size(56, 56));
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    expect(pressed, isNotNull);
  });
}
