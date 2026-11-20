import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show LiquidGlassWidgets;

import 'app.dart';
import 'core/emoji.dart';
import 'core/image_cache.dart';
import 'core/native.dart';
import 'core/page_cache.dart';
import 'core/perf_log.dart';
import 'core/prefs.dart';
import 'core/temp_files.dart';
import 'core/touches.dart';

/// Starts the app.
///
/// The order below is the whole of it, in one place, and each `await` is there because the next
/// step reads what it produced. It used to be a `Future.wait` of four things followed by one line,
/// which left the dependency — "the emoji store reads the picture-cache limit from preferences" —
/// visible only to whoever remembered it. Anything that must happen before the first frame belongs
/// here; anything that can happen while the first frame is drawn is fired without awaiting.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Touches.ensureInitialized();
  PerfLog.start();

  // 1. Nothing here depends on anything else, so these run together.
  await Future.wait([
    Prefs.instance.init(),
    PageCache.instance.init(),
    Native.init(),
    LiquidGlassWidgets.initialize(enablePerformanceMonitor: false),
  ]);

  // 2. Reads preferences, so it comes after them; not awaited, because the first frame is fine with
  //    emoji still drawn as text codes for a moment.
  EmojiStore.instance.init();

  // 3. Background disk hygiene: depends on Prefs and EmojiStore (emoji URLs are exempt from picture
  //    eviction), and never blocks the first frame.
  InfImageCache.instance.sweep().ignore();
  TempFiles.sweep().ignore();
  DraftFiles.sweep().ignore();

  // 4. Glass follows the app's own light/dark setting, not the system's.
  runApp(LiquidGlassWidgets.wrap(brightnessResolver: Theme.maybeBrightnessOf, child: const InfApp()));
}
