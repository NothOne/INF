import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassTab, GlassTabBar, GlassVerticalBar, GlassVerticalBarData, GlassVerticalBarEdge, GlassVerticalBarMetrics;

import '../../core/container_route.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/links.dart';
import '../../core/liquid_glass.dart' show GlassDuring;
import '../../core/look.dart';
import '../../core/motion.dart';
import '../../core/native.dart';
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

class _RootShellState extends State<RootShell> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  /// Whether a tab switch is under way, so the glass can stand down to standard while it runs.
  final ValueNotifier<bool> _tabSwitching = ValueNotifier(false);
  late final Animation<double> _leaveFade = CurvedAnimation(
    parent: _tabFade,
    // The page arriving carries its own opaque paper, so it hides this one as it comes up; this
    // fade only softens the frames where both are still on screen. It used to be the sole thing
    // keeping them apart, which it could not do: both pages let the shell's shared background
    // through wherever they were empty, so their content mixed in the middle of the screen.
    curve: const Interval(0, 0.45, curve: Curves.easeInCubic),
  );
  late final Animation<double> _leaveOpacity = ReverseAnimation(_leaveFade);

  /// The page leaving shrinks back a touch as it goes, as a page does when it is left behind.
  late final Animation<double> _leaveScale = Tween<double>(begin: 1, end: 0.97).animate(
    CurvedAnimation(parent: _tabFade, curve: const Interval(0, 0.45, curve: Curves.easeOutCubic)),
  );

  /// The page arriving comes up over it from below, whole from its first frame: the motion is the
  /// slide, and a page that is opaque throughout is what keeps two screens of content from being
  /// seen at once.
  ///
  /// The travel is deliberately short. Whatever the entering page does not yet cover shows the one
  /// being left underneath, and at a sixth of the screen that strip read as the two pages
  /// overlapping.
  late final Animation<Offset> _enterOffset = Tween<Offset>(
    begin: const Offset(0, 0.018),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _tabFade, curve: const Interval(0.05, 1, curve: Curves.easeOutCubic)));

  /// The scale the entering page is drawn at. Fixed at 1: the slide carries the motion here, and a
  /// page that also grew would read as a dialog rather than a tab.
  static const Animation<double> _enterScale = kAlwaysCompleteAnimation;
  bool _rail = false;

  /// The bottom bar and each tab's own top bar share this: [shellBarsVisible].
  bool get _barVisible => shellBarsVisible.value;

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
    WidgetsBinding.instance.addObserver(this);
    _tabFade.addStatusListener(_tabSettled);
    // The tabs' own top bars read this; a shell built again starts with its bars in view.
    shellBarsVisible.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIncomingLink());
    // Build the other tabs offstage once the feed has had its start: they open on their cached
    // pages with avatars already decoded, and only touch the network once shown.
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _visited.addAll([1, 2, 3]));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _openIncomingLink();
  }

  /// A link handed over as `inf://open?url=…` (a browser bookmarklet, adb), a Weibo address the
  /// system opened here, or text shared here with a link in it.
  Future<void> _openIncomingLink() async {
    final text = await Native.takeLink();
    final url = text == null ? null : linkInText(text);
    if (url != null && mounted) await openLink(context, url);
  }

  void _select(int index, {bool tapped = true}) {
    if (index == 0 && _index == 0) {
      final now = DateTime.now();
      final last = _lastHomeAction;
      _setBarsVisible(true);
      if (last != null && now.difference(last).inMilliseconds < 350) return;
      _lastHomeAction = now;
      Haptic.selection.play();
      _feedKey.currentState?.homeTap();
      return;
    }
    if (index == _index) {
      _setBarsVisible(true);
      return;
    }
    if (tapped) Haptic.selection.play();
    _lastHomeAction = null;
    setState(() {
      _previous = _index;
      _index = index;
      _visited.add(index);
      _downAccum = 0;
      _upAccum = 0;
    });
    // The bar is the way back to every other tab.
    _setBarsVisible(true);
    currentShellTab.value = index;
    // Premium glass cannot be cross-faded: it draws through its own layer, which re-reads the
    // backdrop every frame and does not take the page's opacity with it, so the bar and the strip
    // under a title flicker for as long as the fade runs. Standard paints inside the page and fades
    // as one piece. Held only for the length of the switch.
    _tabSwitching.value = true;
    _tabFade.forward(from: 0);
    if (index == 1 || index == 2) UnreadMonitor.instance.refresh(force: true);
  }

  /// Puts the switch away once the shell's own animation has finished.
  ///
  /// A status listener rather than `forward().whenComplete`: a second tap restarts the controller,
  /// which leaves the first call's future pending forever. Its `whenComplete` never ran, so the
  /// glass stayed at standard and the leaving page stayed onstage for good.
  void _tabSettled(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_tabSwitching.value) _tabSwitching.value = false;
    if (_previous != null) setState(() => _previous = null);
  }

  /// Every tab keeps exactly this widget shape whether it is entering, leaving or hidden, and
  /// is keyed by its index: a tab whose shape or position changed would lose its state, which
  /// is what used to make a tab reload from scratch every time it was opened.
  Widget _tabSlot(int index) {
    final current = index == _index;
    final leaving = index == _previous && !current;
    // The arriving page stays opaque: it slides up over the one being left, which shrinks and
    // fades behind it. Fading both at once is what showed two screens of content together.
    final opacity = leaving ? _leaveOpacity : kAlwaysCompleteAnimation;
    final scale = leaving ? _leaveScale : _enterScale;
    final offset = current ? _enterOffset : const AlwaysStoppedAnimation<Offset>(Offset.zero);
    return Positioned.fill(
      key: ValueKey<int>(index),
      child: Offstage(
        offstage: !current && !leaving,
        child: IgnorePointer(
          ignoring: !current,
          child: FadeTransition(
            opacity: opacity,
            child: SlideTransition(
              position: offset,
              child: ScaleTransition(
                scale: scale,
                // TickerMode pauses page-local animations while the page is leaving or hidden,
                // but the fades and moves above are driven by the shell controller.
                child: TickerMode(
                  enabled: current,
                  child: RepaintBoundary(child: _tabBody(index)),
                ),
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
    // Every tab carries its own paper, not just the shell: a tab that is only transparent lets
    // the one it replaces show through wherever it is empty — a glass bar, the space under a
    // short list — so the two pages' content mixed in the middle of the screen during a switch.
    // One layer per tab means the entering page covers the leaving one as it moves over it.
    // `PaperBackground` rather than a bare fill so each style's backdrop (glass's pools of light
    // included) travels with its own page instead of sitting behind all of them.
    final paper = PaperBackground(child: page);
    if (!_hasPane(index)) return paper;
    return DetailPane(
      key: _paneKeys[index],
      list: paper,
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
    // How far the list has gone past its own top. The feed is measured from the post being read, so
    // at the top its offset is negative rather than zero.
    final metrics = notification.metrics;
    final scrolled = metrics.pixels - metrics.minScrollExtent;
    // Back at the top the bar belongs in view, however the list got there: a fling carries on
    // without a finger on it.
    if (!_barVisible && scrolled <= 40) _setBarsVisible(true);
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
    if (_barVisible && _downAccum > 28 && scrolled > 40) {
      _setBarsVisible(false);
    } else if (!_barVisible && _upAccum > 10) {
      _setBarsVisible(true);
    }
    return false;
  }

  /// The bottom bar and the tabs' top bars all follow [shellBarsVisible]; the shell is not rebuilt.
  void _setBarsVisible(bool visible) {
    shellBarsVisible.value = visible;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabFade.dispose();
    _tabSwitching.dispose();
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
    final chrome = InfChrome.of(buttonContext);
    // The editor grows out of the button, so the disc it grows from is the button's own fill.
    ContainerOrigin.capture(buttonContext, radius: 16, color: chrome.floatingButtonTint(buttonContext));
    openCompose(context);
  }

  Widget _tabsArea({required double width}) {
    return KeyedSubtree(
      key: _tabsKey,
      // The glass inside stands down to standard for the length of a tab switch; see `_select`.
      child: ValueListenableBuilder<bool>(
        valueListenable: _tabSwitching,
        builder: (context, switching, child) => GlassDuring(active: switching, child: child!),
        child: ShellLayout(
          bottomBar: !_rail,
          child: ContentArea(
            width: width,
            // Read below the Scaffold, which has already taken the keyboard out of the insets: the
            // shell's own MediaQuery still has it, and the tab's Scaffold would shrink for it again.
            child: Builder(
              builder: (context) => MediaQuery.removePadding(
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final window = WindowClass.of(context);
    // A landscape phone is too short for a bar along the bottom, whatever the layout setting.
    _rail = window.wide || MediaQuery.orientationOf(context) == Orientation.landscape;
    _split = window == WindowClass.expanded;    // The rail does not cover anything, so a window that becomes wide shows the bars again.
    if (_rail && !shellBarsVisible.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _rail) _setBarsVisible(true);
      });
    }
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
    // Glass cannot fade: a blur inside a translucent layer only sees that layer and goes clear (see
    // GlassChrome.panelsCanFade). Those styles slide the bar out instead, so the fade below is dead
    // weight there — and not harmless: an opacity is a render pass of its own, which keeps the bar's
    // glass out of a GlassBackdropGroup above it and costs a full-screen composite every frame.
    final fades = InfChrome.of(context).panelsCanFade;
    return Stack(
      children: [
        Positioned.fill(child: _tabsArea(width: MediaQuery.sizeOf(context).width)),
        // Only this part of the shell listens: the tabs are not rebuilt as the bar moves.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: shellBarsVisible,
            builder: (context, visible, child) => AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 1.25),
              duration: InfMotion.bar,
              curve: InfMotion.barCurve,
              child: fades
                  ? AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: InfMotion.barFade,
                      child: child,
                    )
                  : child!,
            ),
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
        if (_index == 0)
          Positioned(
            right: 18,
            bottom: 78 + bottomInset,
            child: ValueListenableBuilder<bool>(
              valueListenable: shellBarsVisible,
              builder: (context, visible, _) => _ComposeButton(visible: visible, onPressed: _compose),
            ),
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
    final button = InfChrome.of(context).floatingButton(
      context,
      tooltip: '发微博',
      icon: const Icon(Icons.edit_rounded),
      onPressed: onPressed,
    );
    // Glass cannot fade — a blur inside a translucent layer only sees that layer — so on those
    // styles the button shrinks away instead, as the bottom bar slides away for the same reason.
    // Keeping an AnimatedOpacity there at 1 put its glass in a render pass of its own and kept it
    // out of the shell's GlassBackdropGroup for no gain.
    if (!InfChrome.of(context).panelsCanFade) {
      return IgnorePointer(
        ignoring: !visible,
        child: AnimatedScale(
          scale: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: visible ? Curves.easeOutBack : Curves.easeInCubic,
          child: button,
        ),
      );
    }
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.75,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: button,
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
              onTap: () => onSelect(i),
            ),
          ),
      ],
    );
    final panel = InfLook.of(context).liquid
        ? _liquidRail(context)
        : InfChrome.of(context).floatingPanel(
            context,
            radius: BorderRadius.circular(26),
            body: 0.16,
            child: SizedBox(
              width: _panelWidth,
              height: _itemHeight * tabs.length + 12,
              child: Stack(
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
            ),
          );
    final column = Column(
      children: [
        const Spacer(),
        panel,
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

  /// The bottom bar's own glass, standing up: [GlassTabBar] lays itself out as the vertical capsule
  /// it uses in a side strip. The capsule shows icons; a finger on it lifts a lens that follows
  /// along, brings the labels out, and picks the tab under it on release.
  Widget _liquidRail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The strip's control is 48 wide, 12 in from the strip's inner edge: a strip this wide
    // centres it in the rail.
    const strip = (width + GlassVerticalBarMetrics.controlExtent) / 2 + GlassVerticalBarMetrics.inset;
    return SizedBox(
      width: width,
      height: 12 + tabs.length * GlassVerticalBarMetrics.itemExtent,
      child: GlassVerticalBar(
        data: const GlassVerticalBarData(edge: GlassVerticalBarEdge.leading, width: strip, top: 0, bottom: 0),
        child: GlassTabBar.bottom(
          selectedIndex: index,
          onTabSelected: onSelect,
          selectedIconColor: scheme.primary,
          unselectedIconColor: scheme.onSurfaceVariant,
          iconSize: 24,
          tabs: [
            for (var i = 0; i < tabs.length; i++)
              GlassTab(
                icon: _badged(i, tabs[i].outline),
                activeIcon: _badged(i, tabs[i].icon),
                label: tabs[i].label,
              ),
          ],
        ),
      ),
    );
  }

  Widget _badged(int i, IconData icon) => Badge.count(
        count: badges[i],
        isLabelVisible: badges[i] > 0,
        offset: const Offset(8, -3),
        child: Icon(icon),
      );
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
    final padding = EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom : 10);
    if (InfLook.of(context).liquid) {
      return Padding(
        padding: padding,
        child: _LiquidBottomBar(index: index, tabs: tabs, badges: badges, onSelect: onSelect),
      );
    }
    final radius = BorderRadius.circular(26);
    // A short mark under the label, never a wash behind the icon and the word.
    // A tinted capsule sat on the glyphs and, once translucent, let the feed
    // show through them — worse under glass, where the blur stacked on top.
    final row = Row(
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
    );
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
              row,
            ],
          );
        },
      ),
    );
    return Padding(
      padding: padding,
      // Small glyphs need a thicker frost than a title does.
      child: InfChrome.of(context).floatingPanel(context, radius: radius, body: 0.16, child: items),
    );
  }
}

/// The bar of the other styles, drawn by [GlassTabBar]: the same 58 high and inset. The bar picks
/// a tab as the finger lands, and its glass goes there at once; the shell only follows once the
/// finger lifts. A drag along the bar picks its tab when the drag ends, after the finger is up.
class _LiquidBottomBar extends StatefulWidget {
  const _LiquidBottomBar({required this.index, required this.tabs, required this.badges, required this.onSelect});

  final int index;
  final List<({String label, IconData icon, IconData outline})> tabs;
  final List<int> badges;
  final ValueChanged<int> onSelect;

  @override
  State<_LiquidBottomBar> createState() => _LiquidBottomBarState();
}

class _LiquidBottomBarState extends State<_LiquidBottomBar> {
  bool _down = false;

  /// The tab picked under a finger that is still down: the bar shows it, the shell has not gone.
  int? _pending;

  @override
  void didUpdateWidget(_LiquidBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index && !_down) _pending = null;
  }

  void _picked(int index) {
    if (_down) {
      setState(() => _pending = index);
    } else {
      _pending = null;
      widget.onSelect(index);
    }
  }

  void _lifted() {
    _down = false;
    // A drag ends after the pointer is up, in the same event: let it pick its own tab first.
    scheduleMicrotask(() {
      final pending = _pending;
      if (pending == null || !mounted) return;
      // Hand the shell the tab before dropping `_pending`: `selectedIndex` is `_pending ??
      // widget.index`, so clearing it first would point the indicator back at the old tab for a
      // frame, then forward again once the shell rebuilt — the bar would flick there and back.
      widget.onSelect(pending);
      setState(() => _pending = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => _down = true,
      onPointerUp: (_) => _lifted(),
      onPointerCancel: (_) => setState(() {
        _down = false;
        _pending = null;
      }),
      child: GlassTabBar.bottom(
        barHeight: 58,
        horizontalPadding: 0,
        verticalPadding: 0,
        selectedIndex: _pending ?? widget.index,
        onTabSelected: _picked,
        selectedIconColor: scheme.primary,
        selectedLabelColor: scheme.primary,
        iconSize: 22,
        tabs: [
          for (var i = 0; i < widget.tabs.length; i++)
            GlassTab(
              icon: _badged(i, widget.tabs[i].outline),
              activeIcon: _badged(i, widget.tabs[i].icon),
              label: widget.tabs[i].label,
            ),
        ],
      ),
    );
  }

  Widget _badged(int i, IconData icon) => Badge.count(
        count: widget.badges[i],
        isLabelVisible: widget.badges[i] > 0,
        offset: const Offset(8, -3),
        child: Icon(icon),
      );
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
    // No ink: the mark moving under the tab is the answer to a tap, and the ink's square, drawn on
    // the page's Material rather than the bar, stood out past the capsule's round ends while held.
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
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