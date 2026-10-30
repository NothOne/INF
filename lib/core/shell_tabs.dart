import 'package:flutter/widgets.dart';

/// The bottom-bar tab on screen. Tab pages are built ahead of time and kept alive, so they use
/// this (not their own lifecycle) to tell when the reader actually arrives.
final ValueNotifier<int> currentShellTab = ValueNotifier<int>(0);

/// For state inside a bottom-bar tab: [onTabShown] runs the first time that tab is on screen and
/// again whenever the reader switches back to it.
mixin ShellTabAware<T extends StatefulWidget> on State<T> {
  int get shellTab;

  bool _shownOnce = false;

  void onTabShown({required bool first});

  @override
  void initState() {
    super.initState();
    currentShellTab.addListener(_tabChanged);
    if (currentShellTab.value == shellTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tabChanged());
    }
  }

  @override
  void dispose() {
    currentShellTab.removeListener(_tabChanged);
    super.dispose();
  }

  void _tabChanged() {
    if (!mounted || currentShellTab.value != shellTab) return;
    final first = !_shownOnce;
    _shownOnce = true;
    onTabShown(first: first);
  }
}
