import 'package:flutter/services.dart';

import 'native.dart';
import 'prefs.dart';

/// The whole haptic vocabulary. Every vibration in the app is one of these, so the same meaning
/// always feels the same. Each one also has a visible counterpart on screen; haptics only confirm.
enum Haptic {
  /// A choice moved: tabs, segmented options, pickers.
  selection(HapticLevel.standard),

  /// Something switched on (a like, a switch) and its lighter opposite.
  toggleOn(HapticLevel.subtle),
  toggleOff(HapticLevel.subtle),

  /// A long press was recognised and something is about to open.
  longPress(HapticLevel.subtle),

  /// A gesture crossed the point where letting go commits it, and where it backs out again.
  threshold(HapticLevel.subtle),
  thresholdRelease(HapticLevel.subtle),

  /// The outcome of something the user started.
  success(HapticLevel.subtle),
  error(HapticLevel.subtle);

  /// The lowest setting at which this haptic still plays.
  final HapticLevel level;
  const Haptic(this.level);

  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<Haptic, int> _lastPlayed = {};

  void play() => playAt(Prefs.instance.hapticLevel);

  /// Used by the settings preview, which has to sound the level being chosen before it is saved.
  void playAt(HapticLevel current) {
    if (current.index < level.index) return;
    final now = _clock.elapsedMilliseconds;
    final last = _lastPlayed[this];
    if (last != null && now - last < 50) return;
    _lastPlayed[this] = now;
    Native.haptic(name).then((handled) {
      if (!handled) _fallback();
    });
  }

  void _fallback() {
    switch (this) {
      case Haptic.selection:
      case Haptic.toggleOff:
      case Haptic.thresholdRelease:
        HapticFeedback.selectionClick();
      case Haptic.toggleOn:
      case Haptic.success:
        HapticFeedback.lightImpact();
      case Haptic.threshold:
        HapticFeedback.mediumImpact();
      case Haptic.longPress:
      case Haptic.error:
        HapticFeedback.vibrate();
    }
  }
}

/// Tracks a gesture's progress toward its commit point (1.0) and plays [Haptic.threshold] on the
/// way in and [Haptic.thresholdRelease] on the way out. [armed] is the commit decision itself, so
/// what the finger feels and what happens on release can never disagree.
class HapticThreshold {
  HapticThreshold({this.release = 1.0});

  /// Progress below which an armed gesture disarms. Lower than 1.0 gives hysteresis, so a finger
  /// resting on the edge does not flip back and forth.
  final double release;

  bool _armed = false;
  bool get armed => _armed;

  final Stopwatch _sinceChange = Stopwatch();

  void update(double progress) {
    if (!_armed && progress >= 1.0) {
      _set(true);
    } else if (_armed && progress < release) {
      _set(false);
    }
  }

  void reset() {
    _armed = false;
    _sinceChange
      ..stop()
      ..reset();
  }

  void _set(bool armed) {
    _armed = armed;
    // Jitter right at the edge still flips the state, but only the first crossing is felt.
    final quiet = _sinceChange.isRunning && _sinceChange.elapsedMilliseconds < 120;
    _sinceChange
      ..reset()
      ..start();
    if (quiet) return;
    (armed ? Haptic.threshold : Haptic.thresholdRelease).play();
  }
}
