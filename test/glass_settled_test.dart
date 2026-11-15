import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show GlassAdaptiveScopeData, GlassQuality;

import 'package:inf_flutter/core/liquid_glass.dart';

/// Whether a page's glass knows it is part of a transition.
///
/// Premium glass draws through a compositing layer of its own and re-reads the backdrop every
/// frame; a route transition puts that layer inside a translucent one, and the two disagree frame by
/// frame — the glass comes out as black blocks. The settings page's liquid preview did exactly that
/// on the way back into settings from a pushed page, so what matters here is the *return*: coming
/// back, the page underneath is not the one animating, and reading only its own animation misses
/// the whole transition.
void main() {
  /// The quality the glass under [key] would resolve to right now.
  GlassQuality qualityAt(WidgetTester tester, Key key) {
    final context = tester.element(find.byKey(key, skipOffstage: false));
    return GlassAdaptiveScopeData.of(context).effectiveQuality;
  }

  /// A page whose body reports the quality in force around [probe], inside a [GlassSettled].
  Widget page(Key probe) => Scaffold(
        body: Center(
          child: GlassSettled(
            child: Builder(
              builder: (context) => SizedBox(key: probe, width: 10, height: 10),
            ),
          ),
        ),
      );

  testWidgets('a page at rest leaves the glass alone', (tester) async {
    const probe = ValueKey('probe');
    await tester.pumpWidget(MaterialApp(home: page(probe)));
    await tester.pumpAndSettle();
    // Nothing is pushing a cap down while the page sits still: no adaptive scope at all, so the
    // glass resolves through its own theme.
    expect(GlassAdaptiveScopeData.maybeOf(tester.element(find.byKey(probe, skipOffstage: false))), isNull);
  });

  testWidgets('a page being pushed over steps its glass down', (tester) async {
    const probe = ValueKey('probe');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (context) => const Scaffold(body: Text('next'))),
                  ),
                  child: const Text('push'),
                ),
                Expanded(child: GlassSettled(child: SizedBox(key: probe, width: 10, height: 10))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Mid-transition: the page underneath is inside a fading layer, so its glass is held down.
    expect(qualityAt(tester, probe), GlassQuality.standard);

    await tester.pumpAndSettle();
    // Once the page above has arrived, the page underneath is out of sight; no cap needed.
    expect(GlassAdaptiveScopeData.maybeOf(tester.element(find.byKey(probe, skipOffstage: false))), isNull);
  });

  testWidgets('coming back to a page steps its glass down until the page above has gone', (tester) async {
    const probe = ValueKey('probe');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (context) => const Scaffold(body: Text('next'))),
                  ),
                  child: const Text('push'),
                ),
                Expanded(child: GlassSettled(child: SizedBox(key: probe, width: 10, height: 10))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    // On the page above: the one underneath is not on screen.
    expect(GlassAdaptiveScopeData.maybeOf(tester.element(find.byKey(probe, skipOffstage: false))), isNull);

    // Pop back. This is the case that showed black blocks: the page underneath is not the one
    // animating, so reading only its own animation would leave it at premium through the return.
    Navigator.of(tester.element(find.text('next'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      qualityAt(tester, probe),
      GlassQuality.standard,
      reason: 'the glass under a returning page is inside a fading layer too',
    );

    await tester.pumpAndSettle();
    expect(GlassAdaptiveScopeData.maybeOf(tester.element(find.byKey(probe, skipOffstage: false))), isNull);
  });
}
