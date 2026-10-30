import 'package:flutter/material.dart';

import '../haptics.dart';
import 'common.dart';

/// [RefreshIndicator] plus touch: a tick at the exact drag distance where letting go refreshes,
/// a softer one if the finger backs out of it, and an error buzz with a message when the refresh
/// fails. [onRefresh] may complete with `false` to report a failure it handled itself.
class InfRefreshIndicator extends StatefulWidget {
  const InfRefreshIndicator({
    super.key,
    required this.onRefresh,
    this.color,
    required this.child,
  });

  final Future<Object?> Function() onRefresh;
  final Color? color;
  final Widget child;

  @override
  State<InfRefreshIndicator> createState() => InfRefreshIndicatorState();
}

class InfRefreshIndicatorState extends State<InfRefreshIndicator> {
  // RefreshIndicator only refreshes on release once the drag reaches a quarter of the viewport;
  // its own "armed" state comes earlier and is not the commit point.
  static const double _commitFraction = 0.25;

  final GlobalKey<RefreshIndicatorState> _indicator = GlobalKey<RefreshIndicatorState>();
  final HapticThreshold _threshold = HapticThreshold();
  double? _dragOffset;
  bool _refreshing = false;

  Future<void> show() => _indicator.currentState?.show() ?? Future<void>.value();

  Future<void> _refresh() async {
    _refreshing = true;
    Object? result;
    try {
      result = await widget.onRefresh();
    } catch (_) {
      result = false;
    } finally {
      _refreshing = false;
    }
    if (result == false && mounted) {
      Haptic.error.play();
      showMessage(context, '刷新失败');
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification) {
      final atTop = notification.metrics.extentBefore == 0;
      _dragOffset = (notification.dragDetails != null && atTop && !_refreshing) ? 0 : null;
      _threshold.reset();
      return false;
    }
    final offset = _dragOffset;
    if (offset == null) return false;
    if (notification is ScrollUpdateNotification) {
      _track(offset - (notification.scrollDelta ?? 0), notification.metrics.viewportDimension);
    } else if (notification is OverscrollNotification) {
      _track(offset - notification.overscroll, notification.metrics.viewportDimension);
    } else if (notification is ScrollEndNotification) {
      _dragOffset = null;
    }
    return false;
  }

  void _track(double offset, double viewport) {
    _dragOffset = offset;
    if (viewport <= 0) return;
    _threshold.update(offset / (viewport * _commitFraction));
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: RefreshIndicator(
        key: _indicator,
        onRefresh: _refresh,
        // Below a bar the content scrolls under, not behind it.
        edgeOffset: MediaQuery.paddingOf(context).top,
        color: widget.color,
        child: widget.child,
      ),
    );
  }
}
