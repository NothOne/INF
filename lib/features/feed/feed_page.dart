import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/api.dart';
import '../../core/look.dart';
import '../../core/haptics.dart';
import '../../core/hot_search_store.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/pane.dart';
import '../../core/parse.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';
import '../../core/shell_tabs.dart';
import '../../core/status_store.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/hot_board_bar.dart';
import '../../core/widgets/hot_search_row.dart';
import '../../core/widgets/paged_status_list.dart';
import '../../core/widgets/pager_tail.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/shell_top_bar.dart';
import '../../core/widgets/status_card_host.dart';
import '../../core/widgets/transitions.dart';
import 'feed_controller.dart';
import 'feed_reading_position.dart';
import 'recommend_channels_sheet.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => FeedPageState();
}

/// The three pages under the home bar, left to right. The feed is where the app opens.
enum _HomePage { feed, recommend, board }

class FeedPageState extends State<FeedPage> {
  late final FeedController _controller = FeedController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey<InfRefreshIndicatorState> _refreshKey = GlobalKey<InfRefreshIndicatorState>();
  final GlobalKey<PopupMenuButtonState<FeedSource>> _pickerKey = GlobalKey<PopupMenuButtonState<FeedSource>>();
  final GlobalKey<PopupMenuButtonState<HotSection>> _sectionPickerKey = GlobalKey<PopupMenuButtonState<HotSection>>();
  final PageController _pages = PageController();
  _HomePage _page = _HomePage.feed;

  PagingController<Status>? _hotPager;
  RecommendChannel _channel = Prefs.instance.recommendChannel;
  final ScrollController _hotScroll = ScrollController();
  final GlobalKey<InfRefreshIndicatorState> _hotRefreshKey = GlobalKey<InfRefreshIndicatorState>();

  /// The third page: 微博热搜 or 热门榜单, and within them the board or rank sub-tab last looked at.
  HotSection _hotSection = Prefs.instance.hotSection;
  HotBoard _board = shownBoard(Prefs.instance.hotBoard);
  final ScrollController _boardScroll = ScrollController();
  final GlobalKey<InfRefreshIndicatorState> _boardRefreshKey = GlobalKey<InfRefreshIndicatorState>();
  HotRankTab _rankTab = Prefs.instance.hotRankTab;
  PagingController<Status>? _rankPager;
  final ScrollController _rankScroll = ScrollController();
  final GlobalKey<InfRefreshIndicatorState> _rankRefreshKey = GlobalKey<InfRefreshIndicatorState>();

  /// Whether the 推荐 page is showing 同城, which is drawn for a city rather than for everyone.
  bool get _isLocal => _channel.gid == '1028032222' || _channel.containerId == '102803_2222';

  /// The bottom bar's home button: back to the top of the page shown, or refresh it when already
  /// there.
  Future<void> homeTap() async {
    switch (_page) {
      case _HomePage.feed:
        return _feedHomeTap();
      case _HomePage.recommend:
        if (await _toTop(_hotScroll)) return;
        final indicator = _hotRefreshKey.currentState;
        if (indicator != null) {
          await indicator.show();
          return;
        }
        await _hotPager?.refresh();
      case _HomePage.board:
        if (_hotSection == HotSection.rank) {
          if (await _toTop(_rankScroll)) return;
          final indicator = _rankRefreshKey.currentState;
          if (indicator != null) {
            await indicator.show();
            return;
          }
          await _rankPager?.refresh();
          return;
        }
        if (await _toTop(_boardScroll)) return;
        await _boardRefreshKey.currentState?.show();
    }
  }

  /// The feed's top is below zero: its offsets are measured from the post being read.
  Future<bool> _toTop(ScrollController scroll) async {
    if (!scroll.hasClients || scroll.offset <= scroll.position.minScrollExtent + 8) return false;
    for (var pass = 0; pass < 4 && scroll.hasClients; pass++) {
      final top = scroll.position.minScrollExtent;
      if (scroll.offset <= top + 1) break;
      await scroll.animateTo(top, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
    return true;
  }

  Future<void> _feedHomeTap() async {
    if (await _toTop(_scroll)) return;
    final indicator = _refreshKey.currentState;
    if (indicator != null) {
      await indicator.show();
      return;
    }
    final pager = _controller.pager;
    if (pager != null) {
      await pager.refresh();
    } else if (_controller.mode == FeedMode.unreachable) {
      await _controller.retrySession();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    _controller.start();
    StatusStore.instance.feedRevision.addListener(_refreshFeed);
    Prefs.instance.hotBoardsNotifier.addListener(_onBoardsChanged);
    Prefs.instance.cityNotifier.addListener(_onCityChanged);
    Session.instance.addListener(_onSessionChanged);
    // 我的热搜 is drawn by weibo.com for the account only. An account already known to be signed out
    // opens on 热搜榜 rather than on a page whose one message would be 「登录后查看」.
    if (Session.instance.state == SessionState.loggedOut && _board == HotBoard.mine) _board = HotBoard.realtime;
  }

  @override
  void dispose() {
    Session.instance.removeListener(_onSessionChanged);
    Prefs.instance.cityNotifier.removeListener(_onCityChanged);
    Prefs.instance.hotBoardsNotifier.removeListener(_onBoardsChanged);
    StatusStore.instance.feedRevision.removeListener(_refreshFeed);
    _controller.removeListener(_onController);
    _controller.dispose();
    _scroll.dispose();
    _pages.dispose();
    _hotPager?.dispose();
    _hotScroll.dispose();
    _boardScroll.dispose();
    _rankPager?.dispose();
    _rankScroll.dispose();
    super.dispose();
  }

  /// 我的热搜 answered 「登录后查看」 before the reader signed in. Signing in is the one thing that
  /// can change that answer, so the board is asked for again when the session does. Signing out
  /// takes the board away with the account, and the page moves to 热搜榜 rather than keeping a page
  /// that can only say so.
  void _onSessionChanged() {
    if (!mounted) return;
    final state = Session.instance.state;
    if (state == SessionState.loggedIn) {
      final board = shownBoard(_board);
      if (board.requiresAuth) HotSearchStore.instance.load(board: board, force: true);
      return;
    }
    if (state == SessionState.loggedOut && shownBoard(_board) == HotBoard.mine) {
      setState(() => _board = HotBoard.realtime);
    }
  }

  /// The chosen city is what 同城微博 and 同城热搜 are about. The 同城 board is the store's own to
  /// reload (it hears the same notifier), so only the 推荐 page's 同城 channel is restarted here.
  void _onCityChanged() {
    if (!mounted || !_isLocal) return;
    // The new pager has to reach the page through a rebuild: the list is built from the field, not
    // from a listenable, so assigning it is not enough on its own.
    setState(_startRecommend);
  }

  void _onBoardsChanged() {
    final next = shownBoard(_board);
    if (next == _board) return;
    setState(() => _board = next);
    if (_page == _HomePage.board) HotSearchStore.instance.load(board: next);
  }

  /// A tap on the page already shown opens its picker: groups, channels, sections or boards.
  void _selectPage(_HomePage page) {
    if (page == _page) {
      switch (page) {
        case _HomePage.feed:
          _pickerKey.currentState?.showButtonMenu();
        case _HomePage.recommend:
          showRecommendChannels(context, current: _channel, onSelect: _selectChannel);
        case _HomePage.board:
          // 热搜 and 榜单 have their own pickers: the section menu here, the board editor there.
          if (_hotSection == HotSection.search) {
            showHotBoardEditor(context, current: shownBoard(_board), onSelect: _selectBoard);
          } else {
            _sectionPickerKey.currentState?.showButtonMenu();
          }
      }
      return;
    }
    _pages.animateToPage(page.index, duration: InfMotion.tabIn, curve: Curves.easeOutCubic);
  }

  void _pageChanged(int index) {
    final page = _HomePage.values[index];
    Haptic.selection.play();
    // Each home page has its own bar; swiping to one is not scrolling the page it left.
    showShellBars();
    setState(() {
      _page = page;
      if (page == _HomePage.recommend && _hotPager == null) _startRecommend();
      if (page == _HomePage.board) {
        _board = shownBoard(_board);
        if (_hotSection == HotSection.rank) _startRank();
      }
    });
    if (page == _HomePage.board && _hotSection == HotSection.search) {
      HotSearchStore.instance.load(board: _board);
    }
  }

  void _startRecommend() {
    final channel = _channel;
    final previous = _hotPager;
    _hotPager = PagingController<Status>(
      fetch: (cursor) => WeiboApi.instance.recommendFeed(channel, cursor),
      id: (status) => status.id,
      remember: StatusStore.instance.remember,
    )..refresh();
    previous?.disposeDeferred();
  }

  void _selectChannel(RecommendChannel channel) {
    if (channel.key == _channel.key) return;
    Haptic.selection.play();
    Prefs.instance.setRecommendChannel(channel);
    if (_hotScroll.hasClients) _hotScroll.jumpTo(0);
    setState(() {
      _channel = channel;
      _startRecommend();
    });
  }

  void _selectSection(HotSection section) {
    if (section == _hotSection) return;
    Haptic.selection.play();
    Prefs.instance.setHotSection(section);
    setState(() {
      _hotSection = section;
      if (section == HotSection.rank) _startRank();
    });
    if (section == HotSection.search) HotSearchStore.instance.load(board: shownBoard(_board));
  }

  void _selectBoard(HotBoard board) {
    if (board == _board) return;
    Haptic.selection.play();
    Prefs.instance.setHotBoard(board);
    setState(() => _board = board);
    HotSearchStore.instance.load(board: board);
  }

  void _startRank() {
    if (_rankPager != null) return;
    _rankPager = PagingController<Status>(
      fetch: (cursor) => WeiboApi.instance.hotRankFeed(_rankTab, cursor),
      id: (status) => status.id,
      remember: StatusStore.instance.remember,
    )..refresh();
  }

  void _selectRankTab(HotRankTab tab) {
    if (tab == _rankTab) return;
    Haptic.selection.play();
    Prefs.instance.setHotRankTab(tab);
    if (_rankScroll.hasClients) _rankScroll.jumpTo(0);
    final previous = _rankPager;
    setState(() {
      _rankTab = tab;
      _rankPager = PagingController<Status>(
        fetch: (cursor) => WeiboApi.instance.hotRankFeed(tab, cursor),
        id: (status) => status.id,
        remember: StatusStore.instance.remember,
      )..refresh();
    });
    previous?.disposeDeferred();
  }

  void _refreshFeed() {
    final pager = _controller.pager;
    if (pager != null) pager.refresh(background: true);
  }

  void _onController() {
    if (!mounted) return;
    final message = _controller.message;
    if (message != null) {
      _controller.clearMessage();
      showMessage(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          // The bar stays in the layout when it leaves; the list is padded by it below instead.
          extendBodyBehindAppBar: true,
          appBar: ShellTopBar(
            child: AppBar(
              centerTitle: true,
              titleSpacing: 0,
              leadingWidth: 48,
              leading: const SizedBox.shrink(),
              title: HomeTabs(
                pages: _pages,
                current: _page.index,
                onSelect: (index) => _selectPage(_HomePage.values[index]),
                feedLabel: _SourcePicker(
                  controller: _controller,
                  pickerKey: _pickerKey,
                  enabled: _page == _HomePage.feed,
                  onTapDisabled: () => _selectPage(_HomePage.feed),
                ),
                recommendLabel: HomeTabLabel(
                  title: _channel.personal ? '推荐' : _channel.title,
                  active: _page == _HomePage.recommend,
                ),
                boardLabel: _SectionPicker(
                  section: _hotSection,
                  pickerKey: _sectionPickerKey,
                  enabled: _page == _HomePage.board,
                  onTapDisabled: () => _selectPage(_HomePage.board),
                  onSelect: _selectSection,
                ),
              ),
              actions: InfChrome.of(context).barActions(context, [
                IconButton(
                  onPressed: () => openSearch(context),
                  tooltip: '搜索',
                  icon: const Icon(Icons.search_rounded),
                ),
              ]),
            ),
          ),
          body: PageView(
            controller: _pages,
            onPageChanged: _pageChanged,
            // A swipe between home pages is not scrolling, so it must not leave a bar behind: the
            // bar comes back as the page starts to move.
            children: [
              KeepAlivePage(
                child: _SwipeKeepsBars(
                  pages: _pages,
                  index: _HomePage.feed.index,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    child: _body(),
                  ),
                ),
              ),
              KeepAlivePage(
                child: _SwipeKeepsBars(pages: _pages, index: _HomePage.recommend.index, child: _hotFeed()),
              ),
              KeepAlivePage(
                child: _SwipeKeepsBars(
                  pages: _pages,
                  index: _HomePage.board.index,
                  // Swapped, not cross-faded: 热搜's and 榜单's bars are different rows, and fading
                  // one into the other fades the capsule through paper, which reads as a flash.
                  child: _hotSection == HotSection.rank
                      ? _HotRank(
                          tab: _rankTab,
                          pager: _rankPager,
                          onSelect: _selectRankTab,
                          scroll: _rankScroll,
                          refreshKey: _rankRefreshKey,
                        )
                      : AnimatedBuilder(
                          animation: Prefs.instance.hotBoardsNotifier,
                          builder: (context, _) => _HotBoard(
                            board: shownBoard(_board),
                            onSelect: _selectBoard,
                            scroll: _boardScroll,
                            refreshKey: _boardRefreshKey,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hotFeed() {
    final pager = _hotPager;
    if (pager == null) return const StatusListSkeleton();
    final local = _isLocal;
    return PagedStatusList(
      key: PageStorageKey<String>('home-recommend-${_channel.key}'),
      pager: pager,
      controller: _hotScroll,
      refreshKey: _hotRefreshKey,
      // 同城 is about a place the reader can change; the bar says which one and moves them.
      header: local ? const CityBannerBar() : null,
      bottomInset: ShellLayout.clearance(context, 104),
      emptyText: '「${_channel.title}」暂时没有微博',
    );
  }

  Widget _body() {
    switch (_controller.mode) {
      case FeedMode.checking:
        return const StatusListSkeleton(key: ValueKey('checking'));
      case FeedMode.needsLogin:
        return KeyedSubtree(
          key: const ValueKey('login'),
          child: _LoginPrompt(onLogin: () => openLogin(context)),
        );
      case FeedMode.unreachable:
        return KeyedSubtree(
          key: const ValueKey('unreachable'),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ErrorRetry(message: _controller.unreachable, onRetry: _controller.retrySession),
                const SizedBox(height: 2),
                Text(
                  '请检查网络后重试',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      case FeedMode.timeline:
        return _Timeline(
          key: ValueKey('timeline-${_controller.source.key}'),
          controller: _controller,
          scrollController: _scroll,
          refreshKey: _refreshKey,
        );
    }
  }
}

/// Brings the shell's bars back as soon as its home page starts sliding in or out from under them:
/// leaving is a scroll, arriving is not, so a swipe never ends on a page with no bar.
class _SwipeKeepsBars extends StatefulWidget {
  const _SwipeKeepsBars({required this.pages, required this.index, required this.child});

  final PageController pages;
  final int index;
  final Widget child;

  @override
  State<_SwipeKeepsBars> createState() => _SwipeKeepsBarsState();
}

class _SwipeKeepsBarsState extends State<_SwipeKeepsBars> {
  @override
  void initState() {
    super.initState();
    widget.pages.addListener(_moved);
  }

  @override
  void dispose() {
    widget.pages.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    if (!widget.pages.hasClients || !widget.pages.position.hasContentDimensions) return;
    final page = widget.pages.page ?? widget.index.toDouble();
    if (page != widget.index.toDouble()) showShellBars();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.controller,
    required this.pickerKey,
    required this.enabled,
    required this.onTapDisabled,
  });

  final FeedController controller;
  final GlobalKey<PopupMenuButtonState<FeedSource>> pickerKey;

  /// The group menu only opens from the page it belongs to; elsewhere a tap goes back to it.
  final bool enabled;
  final VoidCallback onTapDisabled;

  @override
  Widget build(BuildContext context) {
    final current = controller.source;
    final title = current.kind == FeedKind.all ? FeedSource.all.name : current.name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? null : onTapDisabled,
      child: PopupMenuButton<FeedSource>(
        key: pickerKey,
        enabled: enabled,
        tooltip: '切换分组',
        onOpened: controller.loadSources,
        onSelected: (source) {
          if (source.key != current.key) Haptic.selection.play();
          controller.selectSource(source);
        },
        position: PopupMenuPosition.under,
        itemBuilder: (context) {
          final sources = controller.sources;
          if (sources == null) {
            return const [
              PopupMenuItem<FeedSource>(
                enabled: false,
                child: Text('加载中…'),
              ),
            ];
          }
          final entries = <PopupMenuEntry<FeedSource>>[];
          for (var index = 0; index < sources.length; index++) {
            final source = sources[index];
            if (index > 0 && _blockOf(sources[index - 1]) != _blockOf(source)) {
              entries.add(const PopupMenuDivider());
            }
            entries.add(
              PopupMenuItem<FeedSource>(
                value: source,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (source.key == current.key)
                      Icon(Icons.check_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            );
          }
          return entries;
        },
        // The bar's tabs give their labels room to tap; this one is inside the popup's own button,
        // so it asks for the same minimum itself rather than shrinking to the words.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 36),
          child: Center(child: HomeTabLabel(title: title, active: enabled)),
        ),
      ),
    );
  }

  /// The menu's three blocks, a divider between them: the system feeds, the groups the account made
  /// (with 悄悄关注 after them), then 我赞过的 and 我的收藏.
  static int _blockOf(FeedSource source) => switch (source.kind) {
        FeedKind.all || FeedKind.followingAll || FeedKind.special || FeedKind.circle => 0,
        FeedKind.group || FeedKind.private => 1,
        FeedKind.liked || FeedKind.favorites || FeedKind.card => 2,
      };
}

/// 微博热搜 or 热门榜单, picked from the bar's third tab. A plain popup menu rather than a sheet: two
/// rows, and it opens and closes in the time a frosted sheet takes just to fade in.
class _SectionPicker extends StatelessWidget {
  const _SectionPicker({
    required this.section,
    required this.pickerKey,
    required this.enabled,
    required this.onTapDisabled,
    required this.onSelect,
  });

  final HotSection section;
  final GlobalKey<PopupMenuButtonState<HotSection>> pickerKey;

  /// The menu only opens from the page it belongs to; elsewhere a tap goes back to it.
  final bool enabled;
  final VoidCallback onTapDisabled;
  final ValueChanged<HotSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? null : onTapDisabled,
      child: PopupMenuButton<HotSection>(
        key: pickerKey,
        enabled: enabled,
        tooltip: '切换热搜与榜单',
        onSelected: onSelect,
        position: PopupMenuPosition.under,
        itemBuilder: (context) => [
          for (final value in HotSection.values)
            PopupMenuItem<HotSection>(
              value: value,
              child: Row(
                children: [
                  Expanded(child: Text(value.label)),
                  if (value == section)
                    Icon(Icons.check_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
        ],
        // The bar's tabs give their labels room to tap; this one is inside the popup's own button,
        // so it asks for the same minimum itself rather than shrinking to the words.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 36),
          child: Center(child: HomeTabLabel(title: section.label, active: enabled)),
        ),
      ),
    );
  }
}

/// A home tab's title with the arrow that says a tap opens its picker, shown on the page in view.
///
/// The arrow takes room only while it is shown, so an unselected tab is nothing but its name and a
/// bar of three fits the longest feed name (特别关注, 我赞过的 — four characters) beside 推荐 and 热搜
/// on a 360dp phone. A four-character name is set a little smaller for the same reason, with its
/// line box kept the same height so the underline below does not move.
class HomeTabLabel extends StatelessWidget {
  const HomeTabLabel({super.key, required this.title, required this.active});

  final String title;
  final bool active;

  static const _long = 4;
  static const _longSize = 16.5;

  @override
  Widget build(BuildContext context) {
    final long = title.runes.length >= _long;
    final style = DefaultTextStyle.of(context).style;
    // The same line box at either size, so a long name does not read as a smaller tab with more
    // room above it and the underline below it never moves.
    final height = long ? (style.fontSize ?? 18) * (style.height ?? 1.2) / _longSize : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: long ? 88 : 72),
          child: Text(
            title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: long ? style.copyWith(fontSize: _longSize, height: height) : null,
          ),
        ),
        // Laid out only while shown, so an unselected tab is no wider than its name; the size
        // change itself is the animation, which is what lets the bar stay centred as it changes.
        AnimatedSize(
          duration: InfMotion.feedback,
          curve: InfMotion.emphasized,
          alignment: Alignment.centerLeft,
          child: active
              ? const Icon(Icons.arrow_drop_down_rounded, size: 22)
              : const SizedBox(width: 0, height: 22),
        ),
      ],
    );
  }
}

/// The feed's name · 推荐 · 热搜, sized to their words rather than to a fixed slot, 推荐 in the
/// middle. Each label follows the swipe: it darkens and underlines as its page slides in, so
/// dragging between pages reads on the bar too.
///
/// The bar used to give every tab 76dp, which cut 特别关注 down to 特别…; intrinsic widths let the
/// widest name have what it needs and leave the two short ones compact. The tabs keep a minimum so
/// each is still a comfortable tap target, and the bar stays centred. [current] is the page shown,
/// which is also the one whose label draws its arrow.
class HomeTabs extends StatelessWidget {
  const HomeTabs({
    super.key,
    required this.pages,
    required this.current,
    required this.onSelect,
    required this.feedLabel,
    required this.recommendLabel,
    required this.boardLabel,
  });

  /// Drives the colour and the underline between pages; null stands still on [current].
  final PageController? pages;
  final int current;
  final ValueChanged<int> onSelect;
  final Widget feedLabel;
  final Widget recommendLabel;
  final Widget boardLabel;

  /// The narrowest a tab may be: two characters plus the room an arrow needs on the selected one.
  static const _minSlot = 52.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = (Theme.of(context).textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    Widget tabs(double position) {
      Widget tab(int index, Widget label) {
        final t = (1 - (position - index).abs()).clamp(0.0, 1.0);
        final color = Color.lerp(scheme.onSurfaceVariant.withValues(alpha: 0.8), scheme.onSurface, t)!;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: index == 0 ? null : () => onSelect(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _minSlot),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle(
                    style: base.copyWith(color: color),
                    child: IconTheme.merge(data: IconThemeData(color: color), child: label),
                  ),
                  const SizedBox(height: 3),
                  Opacity(
                    opacity: t,
                    child: Container(
                      height: 3,
                      width: 6 + 12 * t,
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab(0, feedLabel),
          tab(1, recommendLabel),
          tab(2, boardLabel),
        ],
      );
    }

    final controller = pages;
    if (controller == null) return tabs(current.toDouble());
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settled = controller.hasClients && controller.position.haveDimensions;
        return tabs(settled ? (controller.page ?? current.toDouble()) : current.toDouble());
      },
    );
  }
}

/// weibo.com's boards as a home page: the user's boards behind a row of chips, each entry with
/// its badge, category and time on the board; a tap opens the entry's page.
class _HotBoard extends StatelessWidget {
  const _HotBoard({required this.board, required this.onSelect, required this.scroll, required this.refreshKey});

  final HotBoard board;
  final ValueChanged<HotBoard> onSelect;
  final ScrollController scroll;
  final GlobalKey<InfRefreshIndicatorState> refreshKey;

  static const _capsule = 46.0;

  @override
  Widget build(BuildContext context) {
    // Includes the bar: the list is laid from the top of the screen down in every style.
    final top = MediaQuery.paddingOf(context).top;
    final chrome = InfChrome.of(context);
    // When content runs under the chrome (glass), the chips float over the list as a capsule and
    // the entries scroll beneath it; otherwise they are a plain row on the page.
    final floating = chrome.extendsBehindBars;
    final bandTop = floating ? 6.0 : 0.0;
    final band = floating ? _capsule : 44.0;
    final listTop = top + (floating ? _capsule + 12 : band);
    final gutter = contentGutter(context);
    return AnimatedBuilder(
      animation: HotSearchStore.instance,
      builder: (context, _) {
        final store = HotSearchStore.instance;
        final entries = store.entriesOf(board);
        final at = store.loadedAtOf(board);
        // 同城 is about a city, so it carries the bar that says which one and can change it — above
        // the entries, and also above the states that have none, since an empty 同城 is usually an
        // empty city rather than an empty board.
        final banner = board == HotBoard.city;
        final headerCount = banner ? 2 : 1;
        final Widget list;
        if (entries == null) {
          final error = store.errorOf(board);
          list = StateSwitcher(
            child: error != null
                ? (store.needsLoginOf(board) ? const HotBoardLoginPrompt() : Center(
                    key: const ValueKey('error'),
                    child: ErrorRetry(
                      message: error,
                      onRetry: () => store.load(board: board, force: true),
                    ),
                  ))
                : const RowListSkeleton(key: ValueKey('loading')),
          );
        } else {
          list = InfRefreshIndicator(
            key: refreshKey,
            onRefresh: () => store.load(board: board, force: true),
            child: ListView.builder(
              key: PageStorageKey<String>('home-board-${board.name}'),
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: listTop,
                bottom: ShellLayout.clearance(context, 104) + MediaQuery.paddingOf(context).bottom,
                left: gutter,
                right: gutter,
              ),
              itemCount: entries.isEmpty ? headerCount : entries.length + headerCount,
              itemBuilder: (context, index) {
                if (banner && index == 0) return const CityBannerBar();
                final slot = index - (banner ? 1 : 0);
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 100),
                    child: board == HotBoard.city
                        ? const CityPrompt()
                        : const EmptyHint(text: '这个榜单暂时是空的', icon: Icons.local_fire_department_outlined),
                  );
                }
                if (slot == 0) return _BoardUpdated(at: at);
                final entry = entries[slot - 1];
                return HotSearchRow(
                  entry: entry,
                  detailed: true,
                  onTap: () => openHotTopic(context, query: entry.query, entry: entry),
                );
              },
            ),
          );
        }
        final chips = HotBoardChips(current: board, onSelect: onSelect, floating: floating);
        // Solid on the page, a lifted capsule over it: either way the entries pass underneath, so
        // the row cannot be see-through.
        final row = floating
            ? chrome.floatingPanel(context, radius: BorderRadius.circular(_capsule / 2), child: chips)
            : ColoredBox(color: Theme.of(context).colorScheme.surface, child: ContentColumn(child: chips));
        return Stack(
          children: [
            Positioned.fill(
              // Only the row's own room: states that do not scroll pad by the bar themselves.
              child: entries == null
                  ? Padding(padding: EdgeInsets.only(top: listTop - top), child: list)
                  : list,
            ),
            // The board switcher belongs to the bar, not to the list: it leaves with the bar, and
            // the room it takes is kept, so the entries never move.
            Positioned(
              left: floating ? 12 + gutter : 0,
              right: floating ? 12 + gutter : 0,
              top: top + bandTop,
              height: band,
              child: ShellBarBand(travel: top + bandTop + band, child: row),
            ),
          ],
        );
      },
    );
  }
}

/// When the board shown was fetched, above its first entry.
class _BoardUpdated extends StatelessWidget {
  const _BoardUpdated({required this.at});

  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final time = at;
    if (time == null) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Text(
        '${relativeTime(time)}更新',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// 热门榜单 as a home page: the six sub-tabs behind the same chips capsule the boards use, and the
/// posts they rank. Each tab is its own list, so switching tabs starts where that tab starts.
class _HotRank extends StatelessWidget {
  const _HotRank({
    required this.tab,
    required this.pager,
    required this.onSelect,
    required this.scroll,
    required this.refreshKey,
  });

  final HotRankTab tab;
  final PagingController<Status>? pager;
  final ValueChanged<HotRankTab> onSelect;
  final ScrollController scroll;
  final GlobalKey<InfRefreshIndicatorState> refreshKey;

  static const _capsule = 46.0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final chrome = InfChrome.of(context);
    final floating = chrome.extendsBehindBars;
    final bandTop = floating ? 6.0 : 0.0;
    final band = floating ? _capsule : 44.0;
    final listTop = top + (floating ? _capsule + 12 : band);
    final gutter = contentGutter(context);
    final current = pager;
    final Widget list;
    if (current == null) {
      list = const StatusListSkeleton(key: ValueKey('rank-loading'));
    } else {
      list = PagedStatusList(
        key: PageStorageKey<String>('home-rank-${tab.gid}'),
        pager: current,
        controller: scroll,
        refreshKey: refreshKey,
        emptyText: '「${tab.title}」暂时没有微博',
        // Laid out from the top of the screen like the boards' list, with the chips' room added
        // here: the bar's own inset is part of [listTop], not something to add twice.
        underAppBar: false,
        bottomInset: ShellLayout.clearance(context, 104),
      );
    }
    final chips = HotRankChips(current: tab, onSelect: onSelect, floating: floating);
    final row = floating
        ? chrome.floatingPanel(context, radius: BorderRadius.circular(_capsule / 2), child: chips)
        : ColoredBox(color: Theme.of(context).colorScheme.surface, child: ContentColumn(child: chips));
    return Stack(
      children: [
        Positioned.fill(
          // The list is laid out from the top of the screen like the boards' list, so it pads by
          // the bar and the chips itself ([underAppBar] would add the bar's inset a second time).
          child: Padding(
            padding: EdgeInsets.only(top: listTop),
            child: list,
          ),
        ),
        Positioned(
          left: floating ? 12 + gutter : 0,
          right: floating ? 12 + gutter : 0,
          top: top + bandTop,
          height: band,
          child: ShellBarBand(travel: top + bandTop + band, child: row),
        ),
      ],
    );
  }
}

class _Timeline extends StatefulWidget {
  const _Timeline({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.refreshKey,
  });

  final FeedController controller;
  final ScrollController scrollController;
  final GlobalKey<InfRefreshIndicatorState> refreshKey;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  PagingController<Status>? get pager => widget.controller.pager;

  static const Key _belowKey = ValueKey<String>('feed-below');

  /// Where the reader is in this feed, and what arrived above them. The decision lives in
  /// [FeedReadingPosition]; this page only scrolls to what it asks for and draws what it decides.
  late final FeedReadingPosition _reading = FeedReadingPosition(_sourceKey);

  bool _resuming = false;
  bool _markerRefreshing = false;
  bool _userScrolling = false;
  final ValueNotifier<double> _resumeOpacity = ValueNotifier<double>(1.0);

  PagingController<Status>? _listening;
  final Map<String, BuildContext> _rows = {};
  DateTime _measuredAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saveTimer;

  String get _sourceKey => widget.controller.source.key;
  double get _topInset => MediaQuery.paddingOf(context).top;
  double get _bottomInset => ShellLayout.clearance(context, 104) + MediaQuery.paddingOf(context).bottom;

  @override
  void dispose() {
    _listening?.removeListener(_onPager);
    _saveTimer?.cancel();
    _savePosition();
    _resumeOpacity.dispose();
    super.dispose();
  }

  void _listen(PagingController<Status>? current) {
    if (identical(current, _listening)) return;
    _listening?.removeListener(_onPager);
    _listening = current;
    current?.addListener(_onPager);
    _onPager();
  }

  /// Hands the list to the reading position, which decides whether the centre has to move.
  void _onPager() {
    final current = _listening;
    if (current == null || !mounted) return;
    final moved = _reading.update(current.items, current.refreshedAt, onRecenter: _recenter);
    _resumeOpacity.value = _reading.resumeOpacity;
    if (moved) setState(() {});
  }

  /// Scrolls so [id]'s top sits under the bar, then measures what is actually there.
  void _recenter(String id, double dy) {
    _reading.centerId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scroll = widget.scrollController;
      if (!mounted || !scroll.hasClients) return;
      scroll.jumpTo(-_topInset - dy);
      _measure(force: true);
    });
  }

  /// Finds the top-most visible post, which is both the place to come back to and the newest
  /// one read.
  void _measure({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_measuredAt) < const Duration(milliseconds: 120)) return;
    _measuredAt = now;
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final top = _topInset;
    final bottom = viewport.size.height - _bottomInset;
    String? id;
    var index = 1 << 30;
    var dy = 0.0;
    _rows.forEach((rowId, rowContext) {
      final box = rowContext.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final y = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (y + box.size.height <= top + 24 || y >= bottom) return;
      final at = _reading.ids.indexOf(rowId);
      if (at < 0 || at >= index) return;
      index = at;
      id = rowId;
      dy = y - top;
    });
    final found = id;
    if (found == null) return;
    if (_reading.record(id: found, index: index, dy: dy)) setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _savePosition);
  }

  void _savePosition() => _reading.save(_listening?.items ?? const []);

  Future<void> _toNewest() async {
    final scroll = widget.scrollController;
    if (!scroll.hasClients) return;
    Haptic.selection.play();
    // The sliver above the centre only knows its full height once built, so the first run may
    // stop short of the real top.
    for (var pass = 0; pass < 4; pass++) {
      final top = scroll.position.minScrollExtent;
      if (scroll.offset <= top + 1) break;
      await scroll.animateTo(top, duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic);
      if (!mounted || !scroll.hasClients) return;
    }
    _measure(force: true);
  }

  /// Pages down until the post reading stopped at last time is loaded, then jumps to it.
  Future<void> _resume() async {
    final current = pager;
    final target = Prefs.instance.feedPosition(_sourceKey);
    if (current == null || target == null || _resuming) return;
    Haptic.selection.play();
    setState(() => _resuming = true);
    for (var page = 0; page < 10 && !current.items.any((s) => s.id == target.id); page++) {
      if (!current.hasMore) break;
      await current.loadMore();
      if (!mounted) return;
      if (current.moreError != null) break;
    }
    if (!mounted) return;
    final found = current.items.any((s) => s.id == target.id);
    setState(() {
      _resuming = false;
      if (found) {
        _reading.resumeAt(target.id, target.dy);
      } else {
        _reading.canResume = false;
      }
    });
    _resumeOpacity.value = _reading.resumeOpacity;
    if (found) {
      _recenter(target.id, target.dy);
    } else {
      showMessage(context, '没有找到上次读到的微博');
    }
  }

  /// A pull or a second tap on 首页 asks for the newest posts, so it lands on them.
  Future<bool> _pullRefresh(PagingController<Status> current) async {
    final ok = await current.refresh();
    if (!mounted) return ok;
    if (ok && current.items.isNotEmpty) {
      final topId = current.items.first.id;
      setState(() => _reading.toTop(topId));
      _resumeOpacity.value = _reading.resumeOpacity;
      _recenter(topId, 0);
    }
    return ok;
  }

  Future<void> _refreshFromMarker(PagingController<Status> current) async {
    if (_markerRefreshing) return;
    Haptic.selection.play();
    setState(() => _markerRefreshing = true);
    final ok = await _pullRefresh(current);
    if (!mounted) return;
    setState(() => _markerRefreshing = false);
    if (!ok) {
      Haptic.error.play();
      showMessage(context, '刷新失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, pager, Prefs.instance.blockedNotifier]),
      builder: (context, _) {
        final current = pager;
        _listen(current);
        return RefreshingBar(
          active: current?.backgroundRefreshing ?? false,
          child: StateSwitcher(child: _body(context, current)),
        );
      },
    );
  }

  Widget _body(BuildContext context, PagingController<Status>? current) {
    if (current == null) return const StatusListSkeleton(key: ValueKey('skeleton'));
    final items = current.items;
    if (current.loading && items.isEmpty) {
      return const StatusListSkeleton(key: ValueKey('skeleton'));
    }
    if (current.error != null && items.isEmpty) {
      return Center(
        key: const ValueKey('error'),
        child: ErrorView(error: current.error, onRetry: current.refresh),
      );
    }
    if (items.isEmpty) {
      // No refresh key or scroll controller here: during the cross-fade to the list both states
      // are mounted, and those may only be attached to one of them.
      return InfRefreshIndicator(
        key: const ValueKey('empty'),
        onRefresh: current.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            EmptyHint(
              text: switch (widget.controller.source.kind) {
                FeedKind.all => '暂时没有最新微博',
                FeedKind.followingAll => '暂时没有关注的微博',
                FeedKind.special => '还没有特别关注或暂时没有微博',
                _ => '「${widget.controller.source.name}」里还没有微博',
              },
              icon: Icons.forum_outlined,
            ),
          ],
        ),
      );
    }
    final centerId = _reading.centerId;
    final found = centerId == null ? -1 : items.indexWhere((status) => status.id == centerId);
    final center = found < 0 ? 0 : found;
    final sides = EdgeInsets.symmetric(horizontal: contentGutter(context));
    int? above(Key key) {
      final index = current.indexOfKey(key);
      return index == null || index >= center ? null : center - 1 - index;
    }

    int? below(Key key) {
      final index = current.indexOfKey(key);
      return index == null || index < center ? null : index - center;
    }

    // Two capsules at most, side by side: what arrived on top, and — when the posts being read
    // could not be kept through the refresh — the way back down to them. The second one used to
    // share the first one's place and was never reachable while new posts were counted.
    final pills = <Widget>[
      if (_reading.unread > 0)
        _FeedPill(
          icon: Icons.arrow_upward_rounded,
          label: _reading.unreadOpen ? '${_reading.unread}+ 条新微博' : '${_reading.unread} 条新微博',
          onTap: _toNewest,
        ),
      if (_reading.canResume)
        ValueListenableBuilder<double>(
          valueListenable: _resumeOpacity,
          builder: (context, opacity, child) => Opacity(
            opacity: _resuming ? 1.0 : opacity,
            child: child,
          ),
          child: _FeedPill(
            icon: Icons.arrow_downward_rounded,
            label: _resuming ? '正在找…' : '上次读到',
            onTap: _resume,
            busy: _resuming,
          ),
        ),
    ];
    final pill = pills.isEmpty
        ? null
        : FittedBox(
            key: ValueKey<String>(pills.length == 1 ? 'one' : 'two'),
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < pills.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  pills[index],
                ],
              ],
            ),
          );

    return Stack(
      key: const ValueKey('list'),
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            current.onScroll(notification);
            if (notification.depth == 0) {
              if (notification is ScrollStartNotification) {
                _userScrolling = notification.dragDetails != null;
              } else if (notification is ScrollUpdateNotification) {
                _measure();
                if (_userScrolling && !_resuming && _reading.canResume && notification.scrollDelta != null) {
                  final dismissed = _reading.trackResumeScroll(notification.scrollDelta!);
                  _resumeOpacity.value = _reading.resumeOpacity;
                  if (dismissed) setState(() {});
                }
              } else if (notification is ScrollEndNotification) {
                _userScrolling = false;
                _measure(force: true);
              }
            }
            return false;
          },
          child: InfRefreshIndicator(
            key: widget.refreshKey,
            onRefresh: () => _pullRefresh(current),
            color: Theme.of(context).colorScheme.primary,
            child: CustomScrollView(
              controller: widget.scrollController,
              center: _belowKey,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: _topInset)),
                SliverPadding(
                  padding: sides,
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _row(context, current, center - 1 - index),
                      childCount: center,
                      findChildIndexCallback: above,
                    ),
                  ),
                ),
                SliverPadding(
                  key: _belowKey,
                  padding: sides,
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _row(context, current, center + index),
                      childCount: items.length - center,
                      findChildIndexCallback: below,
                    ),
                  ),
                ),
                SliverPadding(padding: sides, sliver: SliverToBoxAdapter(child: PagerTail(current, gap: 28))),
                SliverToBoxAdapter(child: SizedBox(height: _bottomInset)),
              ],
            ),
          ),
        ),
        Positioned(
          top: _topInset + 10,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: pill ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, PagingController<Status> current, int index) {
    final status = current.items[index];
    if (hiddenByBlock(status)) {
      return SizedBox.shrink(key: ValueKey(status.id));
    }
    return _Tracked(
      key: ValueKey(status.id),
      id: status.id,
      rows: _rows,
      child: AppearIn(
        animate: current.fresh.contains(status.id),
        child: Column(
          children: [
            if (status.id == _reading.markerId && index > 0)
              _ReadMarker(
                refreshing: _markerRefreshing,
                onTap: () => _refreshFromMarker(current),
              ),
            PaneSelected(
              ids: ['status:${status.id}', if (status.repostOf != null) 'status:${status.repostOf!.id}'],
              child: buildStatusCard(context, status, heroScope: '${status.id}-$index'),
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }
}

/// Registers its row while mounted, so the list can tell which posts are on screen.
class _Tracked extends StatefulWidget {
  const _Tracked({super.key, required this.id, required this.rows, required this.child});

  final String id;
  final Map<String, BuildContext> rows;
  final Widget child;

  @override
  State<_Tracked> createState() => _TrackedState();
}

class _TrackedState extends State<_Tracked> {
  @override
  void initState() {
    super.initState();
    widget.rows[widget.id] = context;
  }

  @override
  void didUpdateWidget(_Tracked oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      if (identical(oldWidget.rows[oldWidget.id], context)) oldWidget.rows.remove(oldWidget.id);
      widget.rows[widget.id] = context;
    }
  }

  @override
  void dispose() {
    if (identical(widget.rows[widget.id], context)) widget.rows.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReadMarker extends StatelessWidget {
  const _ReadMarker({required this.refreshing, required this.onTap});

  final bool refreshing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = Expanded(child: Divider(color: scheme.primary.withValues(alpha: 0.35), height: 1));
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: refreshing ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              line,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (refreshing) ...[
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.8, color: scheme.primary),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      refreshing ? '正在刷新…' : '上次看到这里，点击刷新',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ),
              line,
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedPill extends StatelessWidget {
  const _FeedPill({required this.icon, required this.label, required this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final chrome = InfChrome.of(context);
    final ink = chrome.floatingCapsuleInk(context);
    // Keyed by the icon so the switcher above swaps rather than rebuilds it in place.
    return KeyedSubtree(
      key: ValueKey<IconData>(icon),
      child: chrome.floatingCapsule(
        context,
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                    )
                  : Icon(icon, size: 16, color: ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 38),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: InfChrome.of(context).fill(scheme, scheme.primaryContainer, 0.55),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.forum_rounded, size: 38, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              '登录后，首页会显示你关注的人的微博',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 190,
              height: 46,
              child: FilledButton(onPressed: onLogin, child: const Text('登录微博')),
            ),

          ],
        ),
      ),
    );
  }
}