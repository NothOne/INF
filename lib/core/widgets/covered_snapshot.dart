import 'package:flutter/widgets.dart';

/// A full page, painted from one snapshot while another full page opens over it or closes off it.
/// Nothing on the page changes meanwhile, but liquid glass re-reads and refracts what lies behind
/// it on every frame: drawn live under a transition, the shell's bar and button alone cost the GPU
/// more than a frame has. The page that is moving stays live. Only pages wrapped in this take part,
/// so sheets, dialogs and see-through overlays leave the page under them as it is.
class CoveredSnapshot extends StatefulWidget {
  const CoveredSnapshot({super.key, required this.child});

  final Widget child;

  @override
  State<CoveredSnapshot> createState() => _CoveredSnapshotState();
}

/// The wrapped pages whose route is opening or closing.
class _Moving extends ChangeNotifier {
  final Set<Route<dynamic>> routes = {};

  void mark(Route<dynamic> route, bool moving) {
    if (moving ? routes.add(route) : routes.remove(route)) notifyListeners();
  }
}

final _moving = _Moving();

class _CoveredSnapshotState extends State<CoveredSnapshot> {
  final _controller = SnapshotController();
  ModalRoute<dynamic>? _route;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    _moving.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    _forget();
    _route = route;
    _animation = route?.animation?..addStatusListener(_status);
    _status(_animation?.status ?? AnimationStatus.completed);
    _sync();
  }

  void _status(AnimationStatus status) {
    final route = _route;
    if (route != null) _moving.mark(route, status.isAnimating);
  }

  void _sync() {
    // A fresh picture for every transition: the page may have changed while it was covered.
    _controller.clear();
    _controller.allowSnapshotting = _moving.routes.isNotEmpty && !_moving.routes.contains(_route);
  }

  void _forget() {
    _animation?.removeStatusListener(_status);
    final route = _route;
    if (route != null) _moving.mark(route, false);
  }

  @override
  void dispose() {
    _moving.removeListener(_sync);
    _forget();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SnapshotWidget(controller: _controller, mode: SnapshotMode.permissive, child: widget.child);
}
