import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/liquid_glass.dart'
    show GlassMerge, InfGlassQuality, glassIsPremium, liquidGlassTheme;
import 'package:inf_flutter/core/look.dart';
import 'package:inf_flutter/core/prefs.dart' show LiquidTier, VisualStyle;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        GlassAdaptiveDiagnostic,
        GlassAdaptiveScope,
        GlassQuality,
        GlassQualityChangeReason,
        GlassThemeSettings;
import 'package:liquid_glass_widgets/utils/glass_quality_adapter.dart' show AdaptivePhase;

void main() {
  group('liquid tier', () {
    test('standard is what a look gets when it names no tier', () {
      expect(const InfLook(VisualStyle.liquid).liquidTier, LiquidTier.standard);
      expect(const InfLook(VisualStyle.liquid).liquidUltra, isFalse);
      expect(
        const InfLook(VisualStyle.liquid, liquidTier: LiquidTier.ultra).liquidUltra,
        isTrue,
      );
    });

    test('only liquid has an ultra, and classic never does', () {
      const ultraTier = LiquidTier.ultra;
      expect(const InfLook(VisualStyle.classic, liquidTier: ultraTier).liquidUltra, isFalse);
      expect(const InfLook(VisualStyle.glass, liquidTier: ultraTier).liquidUltra, isFalse);
      expect(const InfLook(VisualStyle.liquid, liquidTier: ultraTier).liquidUltra, isTrue);
    });

    test('the tier survives copyWith and lerp', () {
      const ultra = InfLook(VisualStyle.liquid, liquidTier: LiquidTier.ultra);
      expect(ultra.copyWith(refraction: 0.9).liquidTier, LiquidTier.ultra);
      // A theme animation between tiers lands on one of them, never half way.
      expect(ultra.lerp(const InfLook(VisualStyle.liquid), 0.2).liquidTier, LiquidTier.ultra);
      expect(ultra.lerp(const InfLook(VisualStyle.liquid), 0.8).liquidTier, LiquidTier.standard);
    });

    test('ultra lifts the rim past what standard draws, nothing else', () {
      GlassThemeSettings light(InfLook look) => liquidGlassTheme(look).light.settings!;

      final a = light(const InfLook(VisualStyle.liquid));
      final b = light(
        const InfLook(VisualStyle.liquid).copyWith(liquidTier: LiquidTier.ultra),
      );

      expect(b.rimLight!, greaterThan(a.rimLight!));
      // The sliders own these, so changing the tier must not move them.
      for (final (ours, theirs) in [
        (b.thickness, a.thickness),
        (b.refractiveIndex, a.refractiveIndex),
        (b.frost, a.frost),
        (b.glassColor!.a, a.glassColor!.a),
      ]) {
        expect(ours, closeTo(theirs!, 1e-9));
      }
    });

    test('the sliders still drive the glass on both tiers', () {
      for (final tier in LiquidTier.values) {
        final look = InfLook(VisualStyle.liquid, liquidTier: tier);
        final clear = liquidGlassTheme(look.copyWith(liquidClarity: 1));
        final solid = liquidGlassTheme(look.copyWith(liquidClarity: 0));
        expect(clear.light.settings!.glassColor!.a, lessThan(solid.light.settings!.glassColor!.a));
        expect(clear.light.settings!.frost!, lessThan(solid.light.settings!.frost!));
        // The clear end still tints a little, so text on glass keeps a floor under it.
        expect(clear.light.settings!.glassColor!.a, greaterThan(0));
      }
    });
  });

  group('the quality scope', () {
    test('only a slow device is worth telling the user about', () {
      // A build that can never draw premium glass (no Impeller, web) is not the user's problem and
      // would nag on every cold start, so the hint is held to the runtime reasons only.
      for (final reason in [
        GlassQualityChangeReason.warmupComplete,
        GlassQualityChangeReason.thermalDegradation,
      ]) {
        expect(InfGlassQuality.isSlowDevice(reason), isTrue, reason: reason.name);
      }
      for (final reason in [
        GlassQualityChangeReason.staticProbe,
        GlassQualityChangeReason.restoredFromCache,
        GlassQualityChangeReason.thermalRecovery,
      ]) {
        expect(InfGlassQuality.isSlowDevice(reason), isFalse, reason: reason.name);
      }
    });

    testWidgets('builds at either tier and keeps its subtree', (tester) async {
      Widget scope(InfLook look) => MaterialApp(
            home: InfGlassQuality(look: look, child: const Text('glass')),
          );

      await tester.pumpWidget(scope(const InfLook(VisualStyle.liquid)));
      expect(find.text('glass'), findsOneWidget);

      await tester.pumpWidget(
        scope(const InfLook(VisualStyle.liquid, liquidTier: LiquidTier.ultra)),
      );
      expect(find.text('glass'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the frame budget follows the panel, not a fixed 120 Hz', (tester) async {
      // The glass costs the same per frame whatever the screen can do, so a panel that runs the
      // app at 60 has a 16 ms budget. A hard-coded 8 ms called a steady 60 fps "too slow" and
      // stepped ultra down on a tablet drawing the glass as fast as its screen allows.
      await tester.pumpWidget(
        MaterialApp(
          home: InfGlassQuality(
            look: const InfLook(VisualStyle.liquid, liquidTier: LiquidTier.ultra),
            child: const SizedBox.shrink(),
          ),
        ),
      );
      // 60 Hz is what the test display reports: the budget must be its frame, not 120 Hz's 8 ms.
      expect(
        tester.widget<GlassAdaptiveScope>(find.byType(GlassAdaptiveScope)).targetFrameMs,
        16,
      );
    });

    testWidgets('the question is put once, and only on ultra', (tester) async {
      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: InfGlassQuality(
            look: const InfLook(VisualStyle.liquid, liquidTier: LiquidTier.ultra),
            onDowngraded: () => asked++,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      final scope = tester.widget<GlassAdaptiveScope>(find.byType(GlassAdaptiveScope));
      // A step down reports on the way to every lower level — frost first, then the tier — and
      // each is another diagnostic. The question is owed once, not once per step.
      final onDiagnostic = scope.onDiagnostic!;
      for (var i = 0; i < 3; i++) {
        onDiagnostic(GlassAdaptiveDiagnostic(
          from: GlassQuality.premium,
          to: GlassQuality.standard,
          reason: GlassQualityChangeReason.thermalDegradation,
          phase: AdaptivePhase.runtime,
        ));
        await tester.pump();
      }
      expect(asked, 1);
    });

    testWidgets('standard is never asked to drop to itself', (tester) async {
      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: InfGlassQuality(
            look: const InfLook(VisualStyle.liquid),
            onDowngraded: () => asked++,
            child: const SizedBox.shrink(),
          ),
        ),
      );
      tester.widget<GlassAdaptiveScope>(find.byType(GlassAdaptiveScope)).onDiagnostic!(
        GlassAdaptiveDiagnostic(
          from: GlassQuality.standard,
          to: GlassQuality.minimal,
          reason: GlassQualityChangeReason.thermalDegradation,
          phase: AdaptivePhase.runtime,
        ),
      );
      await tester.pump();
      // On standard the only thing to offer is the tier already in use.
      expect(asked, 0);
    });
  });

  group('GlassMerge', () {
    testWidgets('is only premium when a layer can actually be drawn', (tester) async {
      late BuildContext probe;
      Future<bool> premium(InfLook look) async {
        await tester.pumpWidget(
          MaterialApp(
            home: InfGlassQuality(
              look: look,
              child: Builder(
                builder: (context) {
                  probe = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        return glassIsPremium(probe);
      }

      // The test host runs no shader filter, which is exactly the case a merged member has to stay
      // out of: it would give up its own layer for one that is never built.
      expect(await premium(const InfLook(VisualStyle.liquid)), isFalse);
      expect(
        await premium(const InfLook(VisualStyle.liquid, liquidTier: LiquidTier.ultra)),
        isFalse,
        reason: 'nothing may be merged into a layer this build cannot draw',
      );
    });

    testWidgets('a row that cannot merge keeps its own glass', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InfGlassQuality(
            look: const InfLook(VisualStyle.liquid),
            child: Builder(
              builder: (context) => glassIsPremium(context)
                  ? const GlassMerge(child: Text('merged'))
                  : const Text('separate'),
            ),
          ),
        ),
      );
      expect(find.text('separate'), findsOneWidget);
      expect(find.text('merged'), findsNothing);
    });
  });

  group('the top bar', () {
    Widget withBackground(InfLook look) => MaterialApp(
          theme: ThemeData(extensions: [look]),
          home: Builder(
            builder: (context) => SizedBox(
              height: 120,
              child: lookBarBackground(context) ?? const SizedBox.shrink(),
            ),
          ),
        );

    testWidgets('is plain on standard, so the page shows through at the top', (tester) async {
      await tester.pumpWidget(withBackground(const InfLook(VisualStyle.liquid)));
      // A ColoredBox, not a GlassSurface: nothing is sampled and nothing is frosted.
      expect(find.byType(GlassSurface), findsNothing);
    });

    testWidgets('frosts on ultra', (tester) async {
      await tester.pumpWidget(
        withBackground(const InfLook(VisualStyle.liquid, liquidTier: LiquidTier.ultra)),
      );
      expect(find.byType(GlassSurface), findsOneWidget);
    });

    testWidgets('rests clear and frosts in once content scrolls under it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [const InfLook(VisualStyle.liquid, liquidTier: LiquidTier.ultra)],
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ScrollNotificationObserver(
                child: Stack(
                  children: [
                    ListView.builder(
                      itemCount: 40,
                      itemBuilder: (_, i) => SizedBox(height: 40, child: Text('$i')),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 80,
                      child: lookBarBackground(context) ?? const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      double strength() => tester.widget<GlassSurface>(find.byType(GlassSurface)).strength;

      // At the top of the list there is nothing under the bar, so it draws nothing.
      expect(strength(), 0);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(strength(), 1);
    });
  });
}
