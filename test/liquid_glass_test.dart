import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/liquid_glass.dart';
import 'package:inf_flutter/core/look.dart';
import 'package:inf_flutter/core/prefs.dart' show VisualStyle;

void main() {
  tearDown(() => LiquidShader.debugForceShaded = false);

  testWidgets('a lens pane composites what it holds', (tester) async {
    LiquidShader.debugForceShaded = true;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [InfLook(VisualStyle.liquid)]),
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: const SizedBox(
            width: 40,
            height: 40,
            child: LiquidSurface(child: ColoredBox(color: Color(0xFFFF0000))),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage());
    final bytes = await tester.runAsync(() => image!.toByteData());
    final centre = bytes!.getUint32((20 * 40 + 20) * 4);
    // RGBA: red from the child, under whatever tint the pane lays on top.
    expect(centre >> 24, greaterThan(0xC0));
  });
}
