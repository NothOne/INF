import 'dart:io';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

/// Frame timings in logcat (`INF_PERF …`), for comparing renderers on a device. Compiled in only
/// with `--dart-define=PERF_LOG=true`.
class PerfLog {
  static const enabled = bool.fromEnvironment('PERF_LOG');

  /// Frames longer than this get their own `INF_SLOW` line; lower it to see 120 Hz misses.
  static const slowMs = int.fromEnvironment('PERF_SLOW_MS', defaultValue: 30);

  static final List<FrameTiming> _frames = [];
  static int _window = 0;

  static void start() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      _frames.addAll(timings);
      for (final f in timings.where((f) => f.totalSpan >= const Duration(milliseconds: slowMs))) {
        // Vsync time in ms: gaps between consecutive lines show dropped frames that no single
        // frame's own duration reveals.
        final at = (f.timestampInMicroseconds(FramePhase.vsyncStart) / 1000).toStringAsFixed(1);
        _write('INF_SLOW t=$at build=${(f.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
            'raster=${(f.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
            'total=${(f.totalSpan.inMicroseconds / 1000).toStringAsFixed(1)}');
      }
      if (_frames.length >= 120) _flush();
    });
  }

  static void _flush() {
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = _frames.map((f) => ms(f.buildDuration)).toList()..sort();
    final raster = _frames.map((f) => ms(f.rasterDuration)).toList()..sort();
    final total = _frames.map((f) => ms(f.totalSpan)).toList()..sort();
    double at(List<double> v, double q) => v[((v.length - 1) * q).round()];
    final slow = raster.where((v) => v > 8.33).length;
    final line = 'INF_PERF w=${_window++} n=${_frames.length} '
        'build50=${at(build, .5).toStringAsFixed(2)} build90=${at(build, .9).toStringAsFixed(2)} '
        'raster50=${at(raster, .5).toStringAsFixed(2)} raster90=${at(raster, .9).toStringAsFixed(2)} '
        'raster99=${at(raster, .99).toStringAsFixed(2)} rasterMax=${raster.last.toStringAsFixed(2)} '
        'total90=${at(total, .9).toStringAsFixed(2)} over8ms=$slow';
    // ignore: avoid_print
    print(line);
    _frames.clear();
    _write(line);
  }

  // Some vendors drop app logs from logcat; the file is readable with adb either way.
  // Appends are chained: overlapping writeAsString calls on one file drop and splice lines.
  static void _write(String line) {
    _out ??= getExternalStorageDirectory().then((dir) => dir == null ? null : File('${dir.path}/perf.txt'));
    _chain = _chain.then((_) async {
      final file = await _out;
      await file?.writeAsString('$line\n', mode: FileMode.append);
    });
  }

  static Future<File?>? _out;
  static Future<void> _chain = Future<void>.value();
}
