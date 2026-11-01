import 'package:flutter/material.dart';

import 'layout.dart';

/// A tab in a wide window: its list on the left, and on the right whatever was opened from it, in
/// a Navigator of its own. Pages reach it through `pushInf`, and only those whose `openXxx` says
/// they belong in it; everything else still opens over the whole screen.
///
/// Opening from the list replaces what the pane shows; opening from a page already in the pane
/// stacks on top of it. When the window narrows the shell stops building this, and the pane's
/// pages are simply closed.
class DetailPane extends StatefulWidget {
  const DetailPane({
    super.key,
    required this.list,
    required this.emptyText,
    required this.open,
  });

  final Widget list;

  /// Shown while nothing is open, e.g. 选择一条微博.
  final String emptyText;

  /// Whether the pane has a page to go back from; the shell's back handling reads it.
  final ValueNotifier<bool> open;

  /// How wide the list is beside the pane, out of [width] for both.
  static double listWidth(double width) => (width * 0.42).clamp(360.0, 480.0);

  /// The pane [context] is in or beside, if any.
  static DetailPaneState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PaneScope>()?.pane;

  @override
  State<DetailPane> createState() => DetailPaneState();
}

class DetailPaneState extends State<DetailPane> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  late final _PaneObserver _observer = _PaneObserver(_changed);

  /// What the list opened, so it can mark that entry; null while the pane is empty.
  final ValueNotifier<String?> selected = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.open.value = false);
  }

  @override
  void dispose() {
    final open = widget.open;
    WidgetsBinding.instance.addPostFrameCallback((_) => open.value = false);
    selected.dispose();
    super.dispose();
  }

  void _changed() {
    final depth = _observer.stack.length;
    widget.open.value = depth > 1;
    if (depth <= 1) selected.value = null;
  }

  /// Opens [page] here. [key] names what was opened, for the list's highlight.
  Future<T?> open<T>(BuildContext from, Widget page, {required String key}) {
    final navigator = _navigator.currentState;
    if (navigator == null) return Future<T?>.value();
    final route = _PaneRoute<T>(page: page);
    if (Navigator.maybeOf(from) == navigator) return navigator.push<T>(route);
    final stack = _observer.stack;
    if (key == selected.value && stack.length > 1) {
      // The entry already open: back to its first page rather than a second copy.
      final first = stack[1];
      navigator.popUntil((route) => route == first);
      return Future<T?>.value();
    }
    selected.value = key;
    if (stack.length <= 1) return navigator.push<T>(route);
    if (stack.length == 2) return navigator.pushReplacement<T, Object?>(route);
    return navigator.pushAndRemoveUntil<T>(route, (route) => route.isFirst);
  }

  /// Steps back inside the pane; false when it is already empty.
  bool back() {
    final navigator = _navigator.currentState;
    if (navigator == null || !navigator.canPop()) return false;
    navigator.maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _PaneScope(
      pane: this,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final listWidth = DetailPane.listWidth(constraints.maxWidth);
          final paneWidth = constraints.maxWidth - listWidth - 1;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: listWidth,
                child: _Column(
                  media: media.copyWith(
                    size: Size(listWidth, media.size.height),
                    padding: media.padding.copyWith(right: 0),
                    viewPadding: media.viewPadding.copyWith(right: 0),
                  ),
                  child: widget.list,
                ),
              ),
              ColoredBox(color: scheme.outlineVariant.withValues(alpha: 0.5), child: const SizedBox(width: 1)),
              SizedBox(
                width: paneWidth,
                child: _Column(
                  media: media.copyWith(
                    size: Size(paneWidth, media.size.height),
                    padding: media.padding.copyWith(left: 0),
                    viewPadding: media.viewPadding.copyWith(left: 0),
                  ),
                  child: ClipRect(
                    // The root Navigator's hero controller cannot be shared with this one.
                    child: HeroControllerScope.none(
                      child: Navigator(
                        key: _navigator,
                        observers: [_observer],
                        onGenerateRoute: (_) => PageRouteBuilder<void>(
                          opaque: false,
                          pageBuilder: (context, animation, secondaryAnimation) => _Empty(text: widget.emptyText),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One side of the split, laid out as if it were the whole window.
class _Column extends StatelessWidget {
  const _Column({required this.media, required this.child});

  final MediaQueryData media;
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
        data: media,
        child: ContentArea(width: media.size.width, child: child),
      );
}

class _PaneScope extends InheritedWidget {
  const _PaneScope({required this.pane, required super.child});

  final DetailPaneState pane;

  @override
  bool updateShouldNotify(_PaneScope oldWidget) => pane != oldWidget.pane;
}

class _PaneObserver extends NavigatorObserver {
  _PaneObserver(this.onChanged);

  final VoidCallback onChanged;
  final List<Route<dynamic>> stack = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack.add(route);
    if (stack.length > 1) onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack.remove(route);
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack.remove(route);
    onChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) stack[index] = newRoute;
  }
}

/// A plain cross-fade: a page growing out of a list entry would cross the boundary between the
/// two columns.
class _PaneRoute<T> extends PageRouteBuilder<T> {
  _PaneRoute({required Widget page})
      : super(
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            child: child,
          ),
        );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'INF',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.18),
            ),
          ),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

/// Marks the list entry whose page the pane shows. [ids] are the keys its taps open with.
class PaneSelected extends StatelessWidget {
  const PaneSelected({super.key, required this.ids, required this.child});

  final List<String> ids;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pane = DetailPane.maybeOf(context);
    if (pane == null) return child;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: pane.selected,
      child: child,
      builder: (context, selected, child) {
        final on = selected != null && ids.contains(selected);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          foregroundDecoration: BoxDecoration(
            color: on ? scheme.primary.withValues(alpha: 0.07) : Colors.transparent,
            border: Border(left: BorderSide(color: on ? scheme.primary : Colors.transparent, width: 3)),
          ),
          child: child,
        );
      },
    );
  }
}
