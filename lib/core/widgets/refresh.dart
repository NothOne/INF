import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../haptics.dart';
import 'common.dart';

/// Accepts any vertical scrollable inside a [NestedScrollView]: the outer header (depth 0), a
/// direct inner list (depth 1), or a list inside a [TabBarView] (depth 2). Horizontal pages such
/// as [TabBarView] itself are ignored by axis, and [InfRefreshIndicator] locks onto the depth
/// that actually overscrolls at the top so outer and inner scrolls never double-count.
bool nestedScrollRefreshPredicate(ScrollNotification notification) =>
    notification.metrics.axis == Axis.vertical;

enum _RefreshMode { idle, drag, armed, refreshing, done }

/// Pull-to-refresh built on Material's [RefreshProgressIndicator], with a shorter commit distance
/// (`min(120dp, 20% viewport)`), haptic feedback at the exact commit point, error reporting when
/// [onRefresh] returns `false` or throws, and seamless support for pulling to the top inside a
/// [NestedScrollView] (with or without a [TabBarView]).
class InfRefreshIndicator extends StatefulWidget {
  const InfRefreshIndicator({
    super.key,
    required this.onRefresh,
    this.color,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    required this.child,
  });

  /// Maximum logical-pixel drag needed to arm a refresh; shorter viewports scale down to 20%.
  static const double maxCommitDistance = 120.0;
  static const double commitFraction = 0.20;

  /// Exact drag distance required to commit a refresh for a given [viewport] height.
  static double commitDistance(double viewport) =>
      viewport <= 0 ? maxCommitDistance : math.min(maxCommitDistance, viewport * commitFraction);

  final Future<Object?> Function() onRefresh;
  final Color? color;
  final ScrollNotificationPredicate notificationPredicate;
  final Widget child;

  @override
  State<InfRefreshIndicator> createState() => InfRefreshIndicatorState();
}

class InfRefreshIndicatorState extends State<InfRefreshIndicator> with TickerProviderStateMixin {
  static const double _maxOvershootFactor = 1.5;
  static const double _armedPosition = 1.0 / _maxOvershootFactor; // 0.667
  static const double _maxDisplacement = 82.0;
  static const double _indicatorSize = 42.0;

  late final AnimationController _position = AnimationController(vsync: this);
  late final AnimationController _scale = AnimationController(vsync: this, value: 1.0);
  final HapticThreshold _threshold = HapticThreshold();

  _RefreshMode _mode = _RefreshMode.idle;
  int? _activeDepth;
  double _dragOffset = 0;

  @override
  void dispose() {
    _position.dispose();
    _scale.dispose();
    super.dispose();
  }

  /// Programmatically pulls the indicator down and runs [onRefresh] (e.g. tapping the home tab
  /// while already at the top).
  Future<void> show() async {
    if (_mode == _RefreshMode.refreshing || _mode == _RefreshMode.done) return;
    _activeDepth = null;
    _dragOffset = 0;
    _scale.value = 1.0;
    _mode = _RefreshMode.refreshing;
    await _position.animateTo(_armedPosition, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    await _runRefresh();
  }

  Future<void> _triggerRefresh() async {
    if (_mode == _RefreshMode.refreshing || _mode == _RefreshMode.done) return;
    _mode = _RefreshMode.refreshing;
    _scale.value = 1.0;
    _position.animateTo(_armedPosition, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
    await _runRefresh();
  }

  Future<void> _runRefresh() async {
    Object? result;
    try {
      result = await widget.onRefresh();
    } catch (_) {
      result = false;
    }
    if (!mounted) return;
    if (result == false) {
      Haptic.error.play();
      showMessage(context, '刷新失败');
    }
    _mode = _RefreshMode.done;
    await _scale.animateTo(0.0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    if (!mounted) return;
    _reset();
  }

  Future<void> _cancel() async {
    _mode = _RefreshMode.idle;
    _activeDepth = null;
    _dragOffset = 0;
    _threshold.reset();
    await _position.animateTo(0.0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _reset() {
    _mode = _RefreshMode.idle;
    _activeDepth = null;
    _dragOffset = 0;
    _threshold.reset();
    _position.value = 0.0;
    _scale.value = 1.0;
  }

  bool _onScroll(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification) || notification.metrics.axis != Axis.vertical) return false;
    if (_mode == _RefreshMode.refreshing || _mode == _RefreshMode.done) return false;

    if (notification is OverscrollNotification) {
      // Only a live finger drag at the top edge counts: ballistic flings hitting the top must not
      // trigger a refresh. Starting here (rather than requiring extentBefore == 0 on ScrollStart)
      // also lets a user pull down past the top in one continuous stroke.
      if (notification.overscroll < 0 && notification.dragDetails != null) {
        if (_activeDepth == null) {
          _activeDepth = notification.depth;
          _dragOffset = 0;
          _scale.value = 1.0;
          _threshold.reset();
        }
        if (notification.depth == _activeDepth) {
          _dragOffset += -notification.overscroll;
          _updateDrag(notification.metrics.viewportDimension);
        }
      }
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final bouncingAtTop = notification.metrics.pixels < notification.metrics.minScrollExtent;
      if (bouncingAtTop && notification.dragDetails != null) {
        if (_activeDepth == null && delta < 0) {
          _activeDepth = notification.depth;
          _dragOffset = 0;
          _scale.value = 1.0;
          _threshold.reset();
        }
        if (notification.depth == _activeDepth) {
          _dragOffset = (_dragOffset - delta).clamp(0.0, double.infinity);
          _updateDrag(notification.metrics.viewportDimension);
        }
      } else if (_activeDepth == notification.depth && _dragOffset > 0) {
        if (notification.dragDetails == null) {
          // Bouncing physics released the finger and started springing back.
          final armed = _mode == _RefreshMode.armed;
          _activeDepth = null;
          if (armed) {
            _triggerRefresh();
          } else {
            _cancel();
          }
        } else if (delta > 0) {
          _dragOffset = (_dragOffset - delta).clamp(0.0, double.infinity);
          if (_dragOffset == 0) {
            _cancel();
          } else {
            _updateDrag(notification.metrics.viewportDimension);
          }
        }
      }
      return false;
    }

    if (notification is ScrollEndNotification && _activeDepth == notification.depth) {
      final armed = _mode == _RefreshMode.armed;
      _activeDepth = null;
      if (armed) {
        _triggerRefresh();
      } else if (_mode == _RefreshMode.drag) {
        _cancel();
      }
    }
    return false;
  }

  void _updateDrag(double viewport) {
    final commit = InfRefreshIndicator.commitDistance(viewport);
    final ratio = _dragOffset / commit;
    _position.value = (ratio / _maxOvershootFactor).clamp(0.0, 1.0);
    _threshold.update(ratio);
    _mode = ratio >= 1.0 ? _RefreshMode.armed : _RefreshMode.drag;
  }

  bool _onIndicator(OverscrollIndicatorNotification notification) {
    if (!notification.leading) return false;
    if (_activeDepth != null && notification.depth == _activeDepth) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final edgeOffset = MediaQuery.paddingOf(context).top;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _onIndicator,
        child: Stack(
          children: [
            widget.child,
            Positioned(
              top: edgeOffset,
              left: 0,
              right: 0,
              height: _maxDisplacement + _indicatorSize + 16,
              child: IgnorePointer(
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_position, _scale]),
                    builder: (context, _) {
                      if (_mode == _RefreshMode.idle && _position.value == 0) {
                        return const SizedBox.shrink();
                      }
                      final spinning = _mode == _RefreshMode.refreshing || _mode == _RefreshMode.done;
                      final progress = (_position.value / _armedPosition).clamp(0.0, 1.0);
                      final dy = _position.value * _maxDisplacement - _indicatorSize;
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ScaleTransition(
                            scale: _scale,
                            child: Opacity(
                              opacity: spinning ? 1.0 : progress,
                              child: RefreshProgressIndicator(
                                value: spinning ? null : progress * 0.75,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.color ?? Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
