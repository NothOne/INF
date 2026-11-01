import 'package:flutter/material.dart';

import '../../core/container_route.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/liquid_glass.dart';
import '../../core/look.dart';
import '../../core/navigation.dart';
import '../../core/pane.dart';
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
  bool _rail = false;

  /// Expanded windows: the first three tabs keep a [DetailPane] beside their list.
  bool _split = false;
  static const _paneTexts = ['选择一条微博', '选择一条通知', '选择一个会话'];
  final List<GlobalKey> _pageKeys = List.generate(4, (_) => GlobalKey());
  final List<GlobalKey<DetailPaneState>> _paneKeys = List.generate(3, (_) => GlobalKey<DetailPaneState>());
  final List<ValueNotifier<bool>> _paneOpen = List.generate(3, (_) => ValueNotifier<bool>(false));

  bool _hasPane(int index) => _split && index < _paneKeys.length;

  bool get _paneCanGoBack => _hasPane(_index) && _paneOpen[_index].value;

  /// The tabs move between the bar layout and the rail layout without being rebuilt.
  final GlobalKey _tabsKey = GlobalKey();
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
                child: RepaintBoundary(child: _tabBody(index)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The page keeps its state when the window crosses into or out of the split layout.
  Widget _tabBody(int index) {
    final page = KeyedSubtree(key: _pageKeys[index], child: _pages[index]);
    if (!_hasPane(index)) return page;
    return DetailPane(
      key: _paneKeys[index],
      list: page,
      emptyText: _paneTexts[index],
      open: _paneOpen[index],
    );
  }

  bool _onScroll(ScrollNotification notification) {
    // A rail does not cover the content, so it never gets out of the way.
    if (_rail) return false;
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
    for (final open in _paneOpen) {
      open.dispose();
    }
    super.dispose();
  }

  List<int> get _badges => [
        0,
        UnreadMonitor.instance.counts.notifications,
        UnreadMonitor.instance.counts.messages,
        0,
      ];

  void _compose(BuildContext buttonContext) {
    final scheme = Theme.of(buttonContext).colorScheme;
    // The editor grows out of the button.
    ContainerOrigin.capture(buttonContext, radius: 16, color: scheme.primaryContainer);
    openCompose(context);
  }

  Widget _tabsArea({required double width}) {
    return KeyedSubtree(
      key: _tabsKey,
      child: ShellLayout(
        bottomBar: !_rail,
        child: ContentArea(
          width: width,
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: _rail,
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final window = WindowClass.of(context);
    _rail = window.wide;
    _split = window == WindowClass.expanded;
    // Coming back to the bar layout, the bar is where it can be seen.
    if (_rail) _barVisible = true;
    // Back steps out of the open tab's pane first, then to the home tab, then out of the app.
    return ListenableBuilder(
      listenable: Listenable.merge(_paneOpen),
      builder: (context, child) => PopScope(
        canPop: _index == 0 && !_paneCanGoBack,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_hasPane(_index) && _paneKeys[_index].currentState?.back() == true) return;
          if (_index != 0) _select(0, tapped: false);
        },
        child: child!,
      ),
      child: PaperBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: _rail ? _railLayout(context) : _barLayout(context),
        ),
      ),
    );
  }

  Widget _railLayout(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final railWidth = _SideRail.width + padding.left;
    final width = size.width - railWidth;
    // Over the list, not the pane, when there is one: the pane has its own controls down there.
    final listWidth = _split ? DetailPane.listWidth(width - padding.right) : width - padding.right;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: railWidth,
          child: AnimatedBuilder(
            animation: UnreadMonitor.instance,
            builder: (context, _) => _SideRail(
              index: _index,
              tabs: _tabs,
              badges: _badges,
              onSelect: _select,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _tabsArea(width: width)),
              Positioned(
                left: listWidth - 56 - 20,
                bottom: 20 + padding.bottom,
                child: _ComposeButton(visible: _index == 0, onPressed: _compose),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _barLayout(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(child: _tabsArea(width: MediaQuery.sizeOf(context).width)),
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
                  badges: _badges,
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
            child: _ComposeButton(visible: _barVisible, onPressed: _compose),
          ),
      ],
    );
  }
}

/// 发微博, at the bottom right of the home tab's list; it gets out of the way with the bar.
class _ComposeButton extends StatelessWidget {
  const _ComposeButton({required this.visible, required this.onPressed});

  final bool visible;
  final ValueChanged<BuildContext> onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.75,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: InfChrome.of(context).pressable(
            context,
            child: Builder(
              builder: (fabContext) => FloatingActionButton(
                heroTag: null,
                elevation: 2,
                tooltip: '发微博',
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                onPressed: () => onPressed(fabContext),
                child: const Icon(Icons.edit_rounded),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tabs down the left edge, for wide windows: a floating panel marked like the bottom bar, so
/// the two layouts read as one design.
class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.index,
    required this.tabs,
    required this.badges,
    required this.onSelect,
  });

  static const width = 88.0;
  static const _itemHeight = 62.0;
  static const _panelWidth = 64.0;

  final int index;
  final List<({String label, IconData icon, IconData outline})> tabs;
  final List<int> badges;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final liquid = InfLook.of(context).liquid;
    final tabColumn = Column(
      children: [
        for (var i = 0; i < tabs.length; i++)
          SizedBox(
            width: _panelWidth,
            height: _itemHeight,
            child: _BarItem(
              tab: tabs[i],
              selected: i == index,
              badge: badges[i],
              markGap: !liquid,
              onTap: () => onSelect(i),
            ),
          ),
      ],
    );
    final items = SizedBox(
      width: _panelWidth,
      height: _itemHeight * tabs.length + 12,
      child: liquid
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: LiquidTabTrack(
                count: tabs.length,
                index: index,
                onSelect: onSelect,
                axis: Axis.vertical,
                child: tabColumn,
              ),
            )
          : Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: (_panelWidth - 18) / 2,
                top: 6 + index * _itemHeight + _itemHeight - 9,
                width: 18,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: tabColumn,
              ),
            ],
          ),
    );
    final column = Column(
      children: [
        const Spacer(),
        InfChrome.of(context).floatingPanel(
          context,
          radius: BorderRadius.circular(26),
          body: 0.16,
          child: items,
        ),
        const Spacer(),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, padding.top + 14, 0, padding.bottom + 14),
      // A landscape phone can be too short for the tabs; then the rail scrolls.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: column),
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
    final liquid = InfLook.of(context).liquid;
    final row = Row(
      children: [
        for (var i = 0; i < tabs.length; i++)
          Expanded(
            child: _BarItem(
              tab: tabs[i],
              selected: i == index,
              badge: badges[i],
              markGap: !liquid,
              onTap: () => onSelect(i),
            ),
          ),
      ],
    );
    final items = SizedBox(
      height: 58,
      child: liquid
          ? LiquidTabTrack(count: tabs.length, index: index, onSelect: onSelect, child: row)
          : LayoutBuilder(
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
                  row,
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
    this.markGap = true,
  });

  final ({String label, IconData icon, IconData outline}) tab;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  /// Room under the label for the selection mark; liquid glass marks with a drop instead.
  final bool markGap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        // Clears the mark that sits on the bottom edge of the bar.
        padding: EdgeInsets.only(bottom: markGap ? 8 : 0),
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