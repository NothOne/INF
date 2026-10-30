import 'package:flutter/material.dart';

import 'app.dart';
import 'core/emoji.dart';
import 'core/page_cache.dart';
import 'core/perf_log.dart';
import 'core/prefs.dart';
import 'core/touches.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Touches.ensureInitialized();
  PerfLog.start();
  await Future.wait([Prefs.instance.init(), PageCache.instance.init()]);
  EmojiStore.instance.init();
  runApp(const InfApp());
}