import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show LiquidGlassWidgets;

import 'app.dart';
import 'core/emoji.dart';
import 'core/native.dart';
import 'core/page_cache.dart';
import 'core/perf_log.dart';
import 'core/prefs.dart';
import 'core/touches.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Touches.ensureInitialized();
  PerfLog.start();
  await Future.wait([
    Prefs.instance.init(),
    PageCache.instance.init(),
    LiquidGlassWidgets.initialize(enablePerformanceMonitor: false),
    Native.init(),
  ]);
  EmojiStore.instance.init();
  // Glass follows the app's own light/dark setting, not the system's.
  runApp(LiquidGlassWidgets.wrap(brightnessResolver: Theme.maybeBrightnessOf, child: const InfApp()));
}