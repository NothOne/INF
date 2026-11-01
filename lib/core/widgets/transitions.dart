import 'package:flutter/material.dart';

import '../layout.dart';
import '../motion.dart';
import 'common.dart';

/// Cross-fades between the states of a screen (skeleton, error, empty, content) instead of
/// cutting. Give each state's child its own key.
class StateSwitcher extends StatelessWidget {
  const StateSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: InfMotion.content,
      reverseDuration: const Duration(milliseconds: 140),
      switchInCurve: InfMotion.enter,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

/// A hairline of progress along the top edge while a list refreshes behind content that is
/// already on screen; it fades rather than pops so a fast refresh barely registers.
class RefreshingBar extends StatelessWidget {
  const RefreshingBar({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.paddingOf(context).top,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: active ? const Duration(milliseconds: 180) : const Duration(milliseconds: 360),
              curve: Curves.easeOut,
              child: TickerMode(
                enabled: active,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: scheme.primary.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A list row that arrived with a refresh grows open and fades in, pushing the rows below down
/// smoothly instead of making them jump.
///
/// With [grow] off the row keeps its full height from the start and only fades and rises into
/// place: for rows that arrive together into empty space, where nothing below needs pushing and
/// relaying out the whole list every frame would cost the frames of a page transition.
class AppearIn extends StatefulWidget {
  const AppearIn({super.key, required this.animate, this.grow = true, required this.child});

  final bool animate;
  final bool grow;
  final Widget child;

  @override
  State<AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<AppearIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: widget.animate ? 0 : 1,
  );
  late final Animation<double> _size = CurvedAnimation(parent: _controller, curve: InfMotion.enter);
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.25, 1, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.grow) {
      return AnimatedBuilder(
        animation: _size,
        builder: (context, child) => Transform.translate(offset: Offset(0, 14 * (1 - _size.value)), child: child),
        child: FadeTransition(opacity: _fade, child: widget.child),
      );
    }
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}

/// Placeholder rows for avatar-and-two-lines lists (notifications, conversations, people).
class RowListSkeleton extends StatelessWidget {
  const RowListSkeleton({super.key, this.count = 9, this.avatar = 44});

  final int count;
  final double avatar;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 6 + MediaQuery.paddingOf(context).top)
            .add(EdgeInsets.symmetric(horizontal: contentGutter(context))),
        itemCount: count,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: [
              SkeletonBox(width: avatar, height: avatar, radius: avatar / 2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 90.0 + (index * 37) % 70, height: 12),
                    const SizedBox(height: 9),
                    SkeletonBox(width: index.isEven ? double.infinity : 190, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
