import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/liquid_glass.dart';
import 'package:inf_flutter/core/look.dart';
import 'package:inf_flutter/core/prefs.dart' show VisualStyle;

void main() {
  group('liquid glass numbers', () {
    const liquid = InfLook(VisualStyle.liquid);

    test('the default is thin tint and a light frost', () {
      expect(liquid.liquidTintAlpha(Brightness.light), closeTo(0.285, 1e-9));
      expect(liquid.liquidTintAlpha(Brightness.dark), closeTo(0.26, 1e-9));
      expect(liquid.liquidBlurSigma, closeTo(3.5, 1e-9));
    });

    test('clearer means less tint and less blur, never more', () {
      for (final brightness in Brightness.values) {
        var last = double.infinity;
        for (var i = 0; i <= 10; i++) {
          final alpha = InfLook(VisualStyle.liquid, liquidClarity: i / 10).liquidTintAlpha(brightness);
          expect(alpha, lessThan(last));
          last = alpha;
        }
        // The clear end still tints a little, so text on a bar keeps a floor under it.
        expect(InfLook(VisualStyle.liquid, liquidClarity: 1).liquidTintAlpha(brightness), greaterThan(0));
        expect(InfLook(VisualStyle.liquid, liquidClarity: 0).liquidTintAlpha(brightness), lessThan(0.55));
      }
      var lastSigma = double.infinity;
      for (var i = 0; i <= 10; i++) {
        final sigma = InfLook(VisualStyle.liquid, liquidClarity: i / 10).liquidBlurSigma;
        expect(sigma, lessThan(lastSigma));
        lastSigma = sigma;
      }
    });

    test('each style keeps its own chrome', () {
      expect(InfChrome.forLook(const InfLook(VisualStyle.classic)), isA<ClassicChrome>());
      expect(InfChrome.forLook(const InfLook(VisualStyle.glass)), isA<GlassChrome>());
      expect(InfChrome.forLook(const InfLook(VisualStyle.liquid)), isA<LiquidChrome>());
    });
  });

  testWidgets('only liquid draws its snackbar as a pane', (tester) async {
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
    expect(liquid.content, isA<LiquidSurface>());
  });

  testWidgets('the liquid compose button is a 56 round pane that reports its own context', (tester) async {
    BuildContext? pressed;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [InfLook(VisualStyle.liquid)]),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: const LiquidChrome().floatingButton(
              context,
              tooltip: '发微博',
              icon: Icon(Icons.edit_rounded),
              onPressed: (buttonContext) => pressed = buttonContext,
            ),
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(LiquidSurface)), const Size(56, 56));
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    expect(pressed, isNotNull);
  });
}
