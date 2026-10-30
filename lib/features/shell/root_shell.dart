import 'package:flutter/material.dart';

import '../../core/container_route.dart';
import '../../core/haptics.dart';
import '../../core/look.dart';
import '../../core/navigation.dart';
import '../../core/shell_tabs.dart';
import '../../core/unread_monitor.dart';
import '../../core/widgets/paper.dart';
import '../feed/feed_page.dart';
import '../message/message_page.dart';
import '../notify/notify_page.dart';
import '../profile/profile_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with SingleTickerProviderStateMixin {
  int _index = 0;
  int? _previous;
  DateTime? _lastHomeAction;
  final GlobalKey<FeedPageState> _feedKey = GlobalKey<FeedPageState>();
  final Set<int> _visited = {0};
  late final List<Widget> _pages = [
    FeedPage(key: _feedKey),
    const NotifyPage(),
    const MessagePage(),
    const ProfilePage(),
  ];
  late final AnimationController _tabFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final Animation<double> _enterFade = CurvedAnimation(
    parent: _tabFade,
    curve: const Interval(0.28, 1, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _leaveFade = CurvedAnimation(
    parent: _tabFade,
    curve: const Interval(0, 0.28, curve: Curves.easeInCubic),
  );
  late final Animation<double> _leaveOpacity = ReverseAnimation(_leaveFade);
  late final Animation<double> _enterScale = Tween<double>(begin: 0.985, end: 1).animate(_enterFade);
  late final Animation<double> _leaveScale = Tween<double>(begin: 1, end: 1.015).animate(_leaveFade);
  bool _barVisible = true;
  double _downAccum = 0;
  double _upAccum = 0;

  static const _tabs = [
    (label: '首页', icon: Icons.home_rounded, outline: Icons.home_outlined),
    (label: '通知', icon: Icons.notifications_rounded, outline: Icons.notifications_none_rounded),
    (label: '私信', icon: Icons.mail_rounded, outline: Icons.mail_outline_rounded),
    (label: '我', icon: Icons.person_rounded, outline: Icons.person_outline_rounded),
  ];

  @override
  void initState() {
    super.initState();
    // Build the other tabs offstage once the feed has had its start: they open on their cached
    // pages with avatars already decoded, and only touch the network once shown.
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _visited.addAll([1, 2, 3]));
    });
  }

  void _select(int index, {bool tapped = true}) {
    if (index == 0 && _index == 0) {
      final now = DateTime.now();
      final last = _lastHomeAction;
      setState(() => _barVisible = true);
      if (last != null && now.difference(last).inMilliseconds < 350) return;
      _lastHomeAction = now;
      Haptic.selection.play();
      _feedKey.currentState?.homeTap();
      return;
    }
    if (index == _index) {
      setState(() => _barVisible = true);
      return;
    }
    if (tapped) Haptic.selection.play();
    _lastHomeAction = null;
    setState(() {
      _previous = _index;
      _index = index;
      _visited.add(index);
      _barVisible = true;
      _downAccum = 0;
      _upAccum = 0;
    });
    currentShellTab.value = index;
    _tabFade.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _previous = null);
    });
    if (index == 1 || index == 2) UnreadMonitor.instance.refresh(force: true);
  }

  /// Every tab keeps exactly this widget shape whether it is entering, leaving or hidden, and
  /// is keyed by its index: a tab whose shape or position changed would lose its state, which
  /// is what used to make a tab reload from scratch every time it was opened.
  Widget _tabSlot(int index) {
    final current = index == _index;
    final leaving = index == _previous && !current;
    final opacity = current ? _enterFade : (leaving ? _leaveOpacity : kAlwaysCompleteAnimation);
    final scale = current ? _enterScale : (leaving ? _leaveScale : kAlwaysCompleteAnimation);
    return Positioned.fill(
      key: ValueKey<int>(index),
      child: Offstage(
        offstage: !current && !leaving,
        child: IgnorePointer(
          ignoring: !current,
          child: FadeTransition(
            opacity: opacity,
            child: ScaleTransition(
              scale: scale,
              // TickerMode pauses page-local animations while the page is leaving or hidden,
              // but the fade/scale above is driven by the shell controller.
              child: TickerMode(
                enabled: current,
                child: RepaintBoundary(child: _pages[index]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification && notification is! OverscrollNotification) {
      return false;
    }
    // Swiping between the home pages is not scrolling the content.
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification && notification.dragDetails == null) {
      return false;
    }
    final delta = notification is ScrollUpdateNotification ? notification.scrollDelta ?? 0 : 0;
    if (delta > 0) {
      _downAccum += delta;
      _upAccum = 0;
    } else if (delta < 0) {
      _upAccum += -delta;
      _downAccum = 0;
    }
    if (_barVisible && _downAccum > 28 && notification.metrics.pixels > 40) {
      setState(() => _barVisible = false);
    } else if (!_barVisible && _upAccum > 10) {
      setState(() => _barVisible = true);
    }
    return false;
  }

  @override
  void dispose() {
    _tabFade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) _select(0, tapped: false);
      },
      child: PaperBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: Stack(
                    children: [
                      // The entering tab is painted last, over the one leaving.
                      for (var i = 0; i < _tabs.length; i++)
                        if (_visited.contains(i) && i != _index) _tabSlot(i),
                      _tabSlot(_index),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSlide(
                  offset: _barVisible ? Offset.zero : const Offset(0, 1.25),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _barVisible || !InfChrome.of(context).panelsCanFade ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: AnimatedBuilder(
                      animation: UnreadMonitor.instance,
                      builder: (context, _) => _BottomBar(
                        index: _index,
                        tabs: _tabs,
                        badges: [
                          0,
                          UnreadMonitor.instance.counts.notifications,
                          UnreadMonitor.instance.counts.messages,
                          0,
                        ],
                        onSelect: _select,
                      ),
                    ),
                  ),
                ),
              ),
              if (_index == 0)
                Positioned(
                  right: 18,
                  bottom: 78 + bottomInset,
                  child: IgnorePointer(
                    ignoring: !_barVisible,
                    child: AnimatedScale(
                      scale: _barVisible ? 1 : 0.75,
                    duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: _barVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: Builder(
                          builder: (fabContext) => FloatingActionButton(
                            heroTag: null,
                            elevation: 2,
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            onPressed: () {
                              // The editor grows out of the button.
                              ContainerOrigin.capture(fabContext, radius: 16, color: scheme.primaryContainer);
                              openCompose(context);
                            },
                            child: const Icon(Icons.edit_rounded),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.tabs,
    required this.badges,
    required this.onSelect,
  });

  final int index;
  final List<({String label, IconData icon, IconData outline})> tabs;
  final List<int> badges;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final radius = BorderRadius.circular(26);
    // A short mark under the label, never a wash behind the icon and the word.
    // A tinted capsule sat on the glyphs and, once translucent, let the feed
    // show through them — worse under glass, where the blur stacked on top.
    final items = SizedBox(
      height: 58,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / tabs.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: index * itemWidth + (itemWidth - 18) / 2,
                bottom: 6,
                width: 18,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _BarItem(
                        tab: tabs[i],
                        selected: i == index,
                        badge: badges[i],
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom : 10),
      // Small glyphs need a thicker frost than a title does.
      child: InfChrome.of(context).floatingPanel(context, radius: radius, body: 0.16, child: items),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.tab,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final ({String label, IconData icon, IconData outline}) tab;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        // Clears the mark that sits on the bottom edge of the bar.
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge.count(
              count: badge,
              isLabelVisible: badge > 0,
              offset: const Offset(8, -3),
              backgroundColor: scheme.error,
              textColor: scheme.onError,
              child: Icon(selected ? tab.icon : tab.outline, size: 22, color: color),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 11,
                height: 1.05,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(tab.label),
            ),
          ],
        ),
      ),
    );
  }
}