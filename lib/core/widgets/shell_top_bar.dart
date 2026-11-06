import 'package:flutter/material.dart';

import '../look.dart';
import '../motion.dart';
import '../shell_tabs.dart';

/// A shell tab's top bar: an [AppBar] that leaves with the bottom bar ([shellBarsVisible]).
///
/// The tab's body runs behind it in every style, and this keeps its full height whether the bar is
/// in view or not, so hiding it moves nothing below. The toolbar and its tab strip slide up out of
/// the screen, and the material's lower edge rises with them down to the strip over the system
/// status bar, which stays covered — under classic nothing of the page may show behind its icons.
class ShellTopBar extends StatefulWidget implements PreferredSizeWidget {
  const ShellTopBar({super.key, required this.child});

  /// The bar itself, without a `flexibleSpace`: [ShellTopBar] draws the background, so that it can
  /// recede to the status bar strip while the toolbar leaves.
  final AppBar child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  State<ShellTopBar> createState() => _ShellTopBarState();
}

class _ShellTopBarState extends State<ShellTopBar> with SingleTickerProviderStateMixin, _FollowShellBars {
  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).top;
    final bar = AppBar.preferredHeightFor(context, widget.preferredSize);
    final height = inset + bar;
    // What any bar over content is made of: classic's opaque page colour, or glass's frost. Without
    // a background of its own the bar would let the list through as it leaves.
    final background = lookBarBackground(context) ?? ColoredBox(color: Theme.of(context).colorScheme.surface);
    // The bar would add the status bar inset itself; here it sits below that strip, which the
    // material covers on its own.
    final content = MediaQuery.removePadding(context: context, removeTop: true, child: widget.child);
    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: barsShown,
        builder: (context, child) {
          final t = barsShown.value;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Laid out at the height the bar still covers: its lower edge is the bar's lower edge,
              // so under glass the hairline travels up with the toolbar instead of staying behind.
              Positioned(left: 0, right: 0, top: 0, height: inset + bar * t, child: background),
              Positioned.fill(
                child: ClipRect(
                  // Cut off at the strip: the toolbar goes under it, never over its icons.
                  clipper: _BelowInset(inset),
                  child: IgnorePointer(
                    // Only a bar fully in place takes taps: there is nothing to hit while it slides.
                    ignoring: t < 1,
                    child: Transform.translate(
                      offset: Offset(0, bar * (t - 1)),
                      child: Padding(padding: EdgeInsets.only(top: inset), child: child),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: content,
      ),
    );
  }
}

/// A control pinned under a shell tab's top bar, such as the home page's board switcher: it leaves
/// with the bar and comes back with it, never changing the room left for the list below.
class ShellBarBand extends StatefulWidget {
  const ShellBarBand({super.key, required this.travel, required this.child});

  /// How far up it goes: clear of the bar and the status bar above it.
  final double travel;

  final Widget child;

  @override
  State<ShellBarBand> createState() => _ShellBarBandState();
}

class _ShellBarBandState extends State<ShellBarBand> with SingleTickerProviderStateMixin, _FollowShellBars {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: barsShown,
      builder: (context, child) {
        final t = barsShown.value;
        return IgnorePointer(
          ignoring: t < 1,
          child: Transform.translate(offset: Offset(0, widget.travel * (t - 1)), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Keeps everything from [top] down.
class _BelowInset extends CustomClipper<Rect> {
  const _BelowInset(this.top);

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);

  @override
  bool shouldReclip(_BelowInset oldClipper) => oldClipper.top != top;
}

/// Moves with the bottom bar: 1 while [shellBarsVisible], 0 once it is gone, over [InfMotion.bar].
mixin _FollowShellBars<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController barsShown = AnimationController(
    vsync: this,
    duration: InfMotion.bar,
    value: shellBarsVisible.value ? 1 : 0,
  );

  /// Tabs built ahead of time have their tickers paused: theirs skip the slide and arrive in
  /// whatever state the shell asks for.
  bool _ticking = true;

  @override
  void initState() {
    super.initState();
    shellBarsVisible.addListener(_barsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ticking = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    shellBarsVisible.removeListener(_barsChanged);
    barsShown.dispose();
    super.dispose();
  }

  void _barsChanged() {
    final target = shellBarsVisible.value ? 1.0 : 0.0;
    if (!_ticking) {
      barsShown.value = target;
      return;
    }
    barsShown.animateTo(target, duration: InfMotion.bar, curve: InfMotion.barCurve);
  }
}
