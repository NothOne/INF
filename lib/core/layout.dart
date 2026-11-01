import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'prefs.dart';

/// The widest a reading column gets; past it, lists centre their content and pad the sides.
const double kContentMaxWidth = 640;

/// Material's window size classes. They go by the width the app has, not by the device, so split
/// screen, a landscape phone and a folding phone opening up all switch layouts on their own.
enum WindowClass {
  compact,
  medium,
  expanded;

  static const mediumWidth = 600.0;
  static const expandedWidth = 840.0;

  /// Anything but [compact]: the shell has a side rail and content is held to a column.
  bool get wide => this != compact;

  static WindowClass of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final byWidth = width >= expandedWidth ? expanded : (width >= mediumWidth ? medium : compact);
    return switch (InfLayout.deviceOf(context)) {
      DeviceLayout.auto => byWidth,
      DeviceLayout.phone => compact,
      DeviceLayout.tablet => byWidth == compact ? medium : byWidth,
    };
  }
}

/// Carries the 设备布局 preference down from the app, the way `InfLook` carries the style.
class InfLayout extends InheritedWidget {
  const InfLayout({super.key, required this.device, required super.child});

  final DeviceLayout device;

  static DeviceLayout deviceOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InfLayout>()?.device ?? DeviceLayout.auto;

  @override
  bool updateShouldNotify(InfLayout oldWidget) => device != oldWidget.device;
}

/// The width pages below it are laid out in, when that is less than the window: the tabs beside
/// the shell's rail.
class ContentArea extends InheritedWidget {
  const ContentArea({super.key, required this.width, required super.child});

  final double width;

  static double widthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentArea>()?.width ?? MediaQuery.sizeOf(context).width;

  @override
  bool updateShouldNotify(ContentArea oldWidget) => width != oldWidget.width;
}

/// Side padding that holds a scrolling list to [kContentMaxWidth]. It goes into the list's own
/// padding rather than around the list, so the margins still scroll it.
double contentGutter(BuildContext context, {double maxWidth = kContentMaxWidth}) {
  if (!WindowClass.of(context).wide) return 0;
  return math.max(0, (ContentArea.widthOf(context) - maxWidth) / 2);
}

/// Holds something that does not scroll (a header, a tab strip, a sheet's body) to the reading
/// column, centred. Does nothing in the phone layout.
class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, this.maxWidth = kContentMaxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowClass.of(context).wide) return child;
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// [ContentColumn] for an app bar's `bottom` (a tab strip), which has to keep its preferred size.
class ContentBar extends StatelessWidget implements PreferredSizeWidget {
  const ContentBar({super.key, required this.child});

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) => ContentColumn(child: child);
}

/// Set by the shell over its tabs: whether its bar floats along the bottom, over their content,
/// or sits beside them as a rail.
class ShellLayout extends InheritedWidget {
  const ShellLayout({super.key, required this.bottomBar, required super.child});

  final bool bottomBar;

  /// Room at the end of a tab's list: [onBar] clears the floating bottom bar; beside a rail
  /// there is nothing to clear.
  static double clearance(BuildContext context, double onBar) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellLayout>();
    return scope == null || scope.bottomBar ? onBar : 24;
  }

  @override
  bool updateShouldNotify(ShellLayout oldWidget) => bottomBar != oldWidget.bottomBar;
}
