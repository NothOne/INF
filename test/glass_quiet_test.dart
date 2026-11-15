import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show GlassContainer;

import 'package:inf_flutter/core/chrome.dart';
import 'package:inf_flutter/core/container_route.dart';
import 'package:inf_flutter/core/liquid_glass.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether a page's glass steps out of the way while a container transform draws it.
///
/// The transform wraps the whole page in `Opacity` and an `ImageFiltered` blur. Glass drawn inside
/// those reads an empty backdrop and comes out as black blocks — at standard as much as at premium,
/// which is why stepping the quality down does nothing here. A flat fill is the only thing that
/// cannot go wrong, and a page being blurred and scaled is not a page whose glass anyone is looking
/// at.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'visual_style': 'liquid'});
    await Prefs.instance.init();
  });

  testWidgets('glass is flat while the page travels and back once it settles', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  ContainerTransformRoute<void>(
                    origin: ContainerOrigin.atTouch(const Size(400, 800)),
                    builder: (_) => const Scaffold(
                      body: Center(child: SizedBox(width: 200, height: 80, child: _GlassProbe())),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Mid-travel: no glass at all inside the page being animated.
    expect(find.byType(GlassContainer), findsNothing, reason: 'the page is inside a translucent layer');
    expect(GlassQuiet.of(tester.element(find.byType(_GlassProbe))), isTrue);

    await tester.pumpAndSettle();

    // Settled: the same page draws its glass again.
    expect(GlassQuiet.of(tester.element(find.byType(_GlassProbe))), isFalse);
    expect(find.byType(GlassContainer), findsOneWidget);
  });

  testWidgets('a page that was never animated keeps its glass from the first frame', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 200, height: 80, child: _GlassProbe()))),
      ),
    );
    expect(GlassQuiet.of(tester.element(find.byType(_GlassProbe))), isFalse);
    expect(find.byType(GlassContainer), findsOneWidget);
  });
}

/// A glass surface drawn the way the liquid style draws one, so the test measures the real thing.
class _GlassProbe extends StatelessWidget {
  const _GlassProbe();

  @override
  Widget build(BuildContext context) => const LiquidChromeProbe();
}

/// The liquid chrome's floating panel, which is one of the surfaces that has to step aside.
class LiquidChromeProbe extends StatelessWidget {
  const LiquidChromeProbe({super.key});

  @override
  Widget build(BuildContext context) =>
      const LiquidChrome().floatingPanel(context, radius: BorderRadius.circular(16), child: SizedBox.expand());
}
