import 'dart:async';

import 'package:flutter/material.dart';

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
import '../../core/status_store.dart';
import '../../core/widgets/comment_sheet.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/hot_board_bar.dart';
import '../../core/widgets/hot_search_row.dart';
import '../../core/widgets/paged_status_list.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/status_card.dart';
import '../../core/widgets/transitions.dart';
import 'feed_controller.dart';
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
  final PageController _pages = PageController();
  _HomePage _page = _HomePage.feed;

  PagingController<Status>? _hotPager;
  RecommendChannel _channel = Prefs.instance.recommendChannel;
  final ScrollController _hotScroll = ScrollController();
  HotBoard _board = shownBoard(HotBoard.realtime);
  final ScrollController _boardScroll = ScrollController();
  final GlobalKey<InfRefreshIndicatorState> _boardRefreshKey = GlobalKey<InfRefreshIndicatorState>();

  /// The bottom bar's home button: back to the top of the page shown, or refresh it when already
  /// there.
  Future<void> homeTap() async {
    switch (_page) {
      case _HomePage.feed:
        return _feedHomeTap();
      case _HomePage.recommend:
        if (await _toTop(_hotScroll)) return;
        await _hotPager?.refresh();
      case _HomePage.board:
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
    } else {
      await _controller.retrySession();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    _controller.start();
    StatusStore.instance.feedRevision.addListener(_refreshFeed);
  }

  @override
  void dispose() {
    StatusStore.instance.feedRevision.removeListener(_refreshFeed);
    _controller.removeListener(_onController);
    _controller.dispose();
    _scroll.dispose();
    _pages.dispose();
    _hotPager?.dispose();
    _hotScroll.dispose();
    _boardScroll.dispose();
    super.dispose();
  }

  /// A tap on the page already shown opens its picker: groups, channels or boards.
  void _selectPage(_HomePage page) {
    if (page == _page) {
      switch (page) {
        case _HomePage.feed:
          _pickerKey.currentState?.showButtonMenu();
        case _HomePage.recommend:
          showRecommendChannels(context, current: _channel, onSelect: _selectChannel);
        case _HomePage.board:
          showHotBoardEditor(context, current: _board, onSelect: _selectBoard);
      }
      return;
    }
    _pages.animateToPage(page.index, duration: InfMotion.tabIn, curve: Curves.easeOutCubic);
  }

  void _pageChanged(int index) {
    final page = _HomePage.values[index];
    Haptic.selection.play();
    setState(() => _page = page);
    if (page == _HomePage.recommend && _hotPager == null) _startRecommend();
    if (page == _HomePage.board) {
      _board = shownBoard(_board);
      HotSearchStore.instance.load(board: _board);
    }
  }

  void _startRecommend() {
    final channel = _channel;
    _hotPager?.dispose();
    _hotPager = PagingController<Status>(
      fetch: (cursor) => WeiboApi.instance.recommendFeed(channel, cursor),
      id: (status) => status.id,
    )..refresh();
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

  void _selectBoard(HotBoard board) {
    if (board == _board) return;
    Haptic.selection.play();
    setState(() => _board = board);
    HotSearchStore.instance.load(board: board);
  }

  void _refreshFeed() {
    final pager = _controller.pager;
    if (pager != null) pager.refresh(quiet: true);
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
          extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
          appBar: AppBar(
            flexibleSpace: lookBarBackground(context),
            centerTitle: true,
            titleSpacing: 0,
            leadingWidth: 56,
            leading: const SizedBox.shrink(),
            title: _HomeTabs(
              pages: _pages,
              current: _page,
              onSelect: _selectPage,
              feedLabel: _SourcePicker(
                controller: _controller,
                pickerKey: _pickerKey,
                enabled: _page == _HomePage.feed,
                onTapDisabled: () => _selectPage(_HomePage.feed),
              ),
              recommendLabel: _ArrowLabel(
                title: _channel.personal ? '推荐' : _channel.title,
                active: _page == _HomePage.recommend,
              ),
              boardLabel: AnimatedBuilder(
                animation: Prefs.instance,
                builder: (context, _) {
                  final board = shownBoard(_board);
                  return _ArrowLabel(
                    title: board == HotBoard.realtime ? '热搜' : board.label,
                    active: _page == _HomePage.board,
                  );
                },
              ),
            ),
            actions: [
              IconButton(
                onPressed: () => openSearch(context),
                tooltip: '搜索',
                icon: const Icon(Icons.search_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: PageView(
            controller: _pages,
            onPageChanged: _pageChanged,
            children: [
              KeepAlivePage(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  child: _body(),
                ),
              ),
              KeepAlivePage(child: _hotFeed()),
              KeepAlivePage(
                child: AnimatedBuilder(
                  animation: Prefs.instance,
                  builder: (context, _) => _HotBoard(
                    board: shownBoard(_board),
                    onSelect: _selectBoard,
                    scroll: _boardScroll,
                    refreshKey: _boardRefreshKey,
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
    return PagedStatusList(
      key: PageStorageKey<String>('home-recommend-${_channel.key}'),
      pager: pager,
      controller: _hotScroll,
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
    final title = current.kind == FeedKind.all ? '关注' : current.name;
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
            if (index > 0 && source.kind != FeedKind.group && sources[index - 1].kind == FeedKind.group) {
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
        child: _ArrowLabel(title: title, active: enabled),
      ),
    );
  }
}

/// A home tab's title with the arrow that says a tap opens its picker, shown on the page in view.
/// The arrow hangs off the label so the label stays centred in its slot.
class _ArrowLabel extends StatelessWidget {
  const _ArrowLabel({required this.title, required this.active});

  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 56),
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        ),
        Positioned(
          right: -19,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0.0,
            duration: InfMotion.feedback,
            child: const Icon(Icons.arrow_drop_down_rounded, size: 22),
          ),
        ),
      ],
    );
  }
}

/// 关注 · 推荐 · 热搜 in equal slots, 推荐 at the centre of the bar. Each label follows the swipe:
/// it darkens and underlines as its page slides in, so dragging between pages reads on the bar too.
class _HomeTabs extends StatelessWidget {
  const _HomeTabs({
    required this.pages,
    required this.current,
    required this.onSelect,
    required this.feedLabel,
    required this.recommendLabel,
    required this.boardLabel,
  });

  final PageController pages;
  final _HomePage current;
  final ValueChanged<_HomePage> onSelect;
  final Widget feedLabel;
  final Widget recommendLabel;
  final Widget boardLabel;

  static const _slot = 76.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = (Theme.of(context).textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    return AnimatedBuilder(
      animation: pages,
      builder: (context, _) {
        final position = pages.hasClients && pages.position.haveDimensions
            ? (pages.page ?? current.index.toDouble())
            : current.index.toDouble();
        Widget tab(_HomePage page, Widget label) {
          final t = (1 - (position - page.index).abs()).clamp(0.0, 1.0);
          final color = Color.lerp(scheme.onSurfaceVariant.withValues(alpha: 0.8), scheme.onSurface, t)!;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: page == _HomePage.feed ? null : () => onSelect(page),
            child: SizedBox(
              width: _slot,
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
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tab(_HomePage.feed, feedLabel),
            tab(_HomePage.recommend, recommendLabel),
            tab(_HomePage.board, boardLabel),
          ],
        );
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
    final top = MediaQuery.paddingOf(context).top;
    final chrome = InfChrome.of(context);
    // When content runs under the chrome (glass), the chips float over the list as a capsule and
    // the entries scroll beneath it; otherwise they are a plain row above the list.
    final floating = chrome.extendsBehindBars;
    final listTop = floating ? _capsule + 12 : 0.0;
    final gutter = contentGutter(context);
    return AnimatedBuilder(
      animation: HotSearchStore.instance,
      builder: (context, _) {
        final store = HotSearchStore.instance;
        final entries = store.entriesOf(board);
        final at = store.loadedAtOf(board);
        final Widget list;
        if (entries == null) {
          list = StateSwitcher(
            child: store.errorOf(board) != null
                ? Center(
                    key: const ValueKey('error'),
                    child: ErrorRetry(
                      message: store.errorOf(board),
                      onRetry: () => store.load(board: board, force: true),
                    ),
                  )
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
                top: floating ? top + listTop : 0,
                bottom: ShellLayout.clearance(context, 104) + MediaQuery.paddingOf(context).bottom,
                left: gutter,
                right: gutter,
              ),
              itemCount: entries.isEmpty ? 1 : entries.length + 1,
              itemBuilder: (context, index) {
                if (entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: EmptyHint(text: '这个榜单暂时是空的', icon: Icons.local_fire_department_outlined),
                  );
                }
                if (index == 0) return _BoardUpdated(at: at);
                final entry = entries[index - 1];
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
        if (!floating) {
          return Padding(
            padding: EdgeInsets.only(top: top),
            child: Column(children: [ContentColumn(child: chips), Expanded(child: list)]),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: entries == null ? Padding(padding: EdgeInsets.only(top: top + listTop), child: list) : list,
            ),
            Positioned(
              left: 12 + gutter,
              right: 12 + gutter,
              top: top + 6,
              height: _capsule,
              child: chrome.floatingPanel(context, radius: BorderRadius.circular(_capsule / 2), child: chips),
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

  /// The post scroll offsets are measured from: at −[_topInset] its top sits just under the bar.
  /// New posts load into the sliver above it, so they never move what is on screen.
  String? _centerId;

  /// Where reading is: the top-most visible post and how far its top sits above the bar's edge.
  ({String id, double dy})? _position;

  /// The newest post before the latest refresh; 上次看到这里 is drawn above it.
  String? _markerId;

  /// Posts above the top-most one seen since they arrived.
  int _unread = 0;

  /// The refresh brought more new posts than one page, so how many is unknown.
  bool _unreadOpen = false;

  /// The position saved last time lies beyond the loaded pages.
  bool _canResume = false;
  bool _resuming = false;

  PagingController<Status>? _listening;
  DateTime? _refreshedAt;
  List<String> _ids = const [];
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
    super.dispose();
  }

  void _listen(PagingController<Status>? current) {
    if (identical(current, _listening)) return;
    _listening?.removeListener(_onPager);
    _listening = current;
    _ids = const [];
    _centerId = null;
    _refreshedAt = current?.refreshedAt;
    current?.addListener(_onPager);
    _onPager();
  }

  /// Keeps the reading place through refreshes and notes what they brought.
  void _onPager() {
    final current = _listening;
    if (current == null || !mounted) return;
    final ids = [for (final status in current.items) status.id];
    if (ids.isEmpty) {
      _ids = ids;
      return;
    }
    if (_ids.isEmpty) {
      _start(ids);
    } else if (current.refreshedAt != _refreshedAt) {
      final previousTop = _ids.first;
      final at = ids.indexOf(previousTop);
      if (at > 0) {
        _markerId = previousTop;
        _unread = at;
        _unreadOpen = false;
      } else if (at < 0) {
        _markerId = null;
        _unread = ids.length;
        _unreadOpen = true;
      }
      if (_centerId == null || !ids.contains(_centerId)) {
        // The refresh did not reach the place being read; it is somewhere further down.
        final position = _position;
        _recenter(ids.first, dy: 0);
        if (position != null && !ids.contains(position.id)) _canResume = true;
      }
    }
    _refreshedAt = current.refreshedAt;
    _ids = ids;
  }

  /// The first page shown: from where reading stopped last time when that page holds it, with
  /// what arrived since then counted against the newest post loaded last time.
  void _start(List<String> ids) {
    final saved = Prefs.instance.feedPosition(_sourceKey);
    if (saved == null) {
      _recenter(ids.first, dy: 0);
      return;
    }
    _position = (id: saved.id, dy: saved.dy);
    if (ids.contains(saved.id)) {
      _recenter(saved.id, dy: saved.dy);
    } else {
      _recenter(ids.first, dy: 0);
      _canResume = saved.id != ids.first;
    }
    final head = saved.head;
    final at = head == null ? -1 : ids.indexOf(head);
    if (at > 0) {
      _markerId = head;
      _unread = at;
    } else if (at < 0 && saved.headAt != null) {
      final items = _listening!.items;
      final newer = items.where((status) => status.createdAt.isAfter(saved.headAt!)).length;
      _unread = newer;
      _unreadOpen = newer == items.length;
    }
  }

  void _recenter(String id, {required double dy}) {
    _centerId = id;
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
      final at = _ids.indexOf(rowId);
      if (at < 0 || at >= index) return;
      index = at;
      id = rowId;
      dy = y - top;
    });
    final found = id;
    if (found == null) return;
    _position = (id: found, dy: dy);
    if (found == _savedId) _canResume = false;
    _scheduleSave();
    final unread = _unread > index ? index : _unread;
    // Reading on from the top drops the offer to go back to last time's place.
    final dropResume = _canResume && index >= 3;
    if (unread != _unread || dropResume) {
      setState(() {
        _unread = unread;
        if (dropResume) _canResume = false;
      });
    }
  }

  String? get _savedId => Prefs.instance.feedPosition(_sourceKey)?.id;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _savePosition);
  }

  void _savePosition() {
    final position = _position;
    final items = _listening?.items ?? const <Status>[];
    if (position == null || _canResume || items.isEmpty) return;
    // The newest post actually seen: posts above it stay new for next time.
    final head = items[_unread.clamp(0, items.length - 1)];
    Prefs.instance.setFeedPosition(
      _sourceKey,
      FeedPosition(id: position.id, dy: position.dy, head: head.id, headAt: head.createdAt),
    );
  }

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
      _canResume = false;
      if (found) _recenter(target.id, dy: target.dy);
    });
    if (!found) showMessage(context, '没有找到上次读到的微博');
  }

  /// A pull or a second tap on 首页 asks for the newest posts, so it lands on them.
  Future<void> _pullRefresh(PagingController<Status> current) async {
    await current.refresh();
    if (!mounted || current.items.isEmpty) return;
    setState(() {
      _unread = 0;
      _unreadOpen = false;
      _recenter(current.items.first.id, dy: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, pager, StatusStore.instance, Prefs.instance]),
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
        child: ErrorRetry(message: current.error.toString(), onRetry: current.refresh),
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
              text: widget.controller.source.kind == FeedKind.all
                  ? '没有微博'
                  : '「${widget.controller.source.name}」里还没有微博',
              icon: Icons.forum_outlined,
            ),
          ],
        ),
      );
    }
    final found = _centerId == null ? -1 : items.indexWhere((status) => status.id == _centerId);
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

    final pill = _unread > 0
        ? _FeedPill(
            icon: Icons.arrow_upward_rounded,
            label: _unreadOpen ? '$_unread+ 条新微博' : '$_unread 条新微博',
            onTap: _toNewest,
          )
        : _canResume
            ? _FeedPill(
                icon: Icons.arrow_downward_rounded,
                label: _resuming ? '正在找上次读到的位置' : '回到上次读到的位置',
                busy: _resuming,
                onTap: _resume,
              )
            : null;

    return Stack(
      key: const ValueKey('list'),
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            current.onScroll(notification);
            if (notification.depth == 0) {
              if (notification is ScrollUpdateNotification) _measure();
              if (notification is ScrollEndNotification) _measure(force: true);
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
                SliverPadding(padding: sides, sliver: SliverToBoxAdapter(child: _Footer(pager: current))),
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
    if (Prefs.instance.isBlocked(status.author.id)) {
      return _Tracked(key: ValueKey(status.id), id: status.id, rows: _rows, child: const SizedBox.shrink());
    }
    return _Tracked(
      key: ValueKey(status.id),
      id: status.id,
      rows: _rows,
      child: AppearIn(
        animate: current.fresh.contains(status.id),
        child: Column(
          children: [
            if (status.id == _markerId && index > 0) const _ReadMarker(),
            PaneSelected(
              ids: ['status:${status.id}', if (status.repostOf != null) 'status:${status.repostOf!.id}'],
              child: StatusCard(
              status: status,
              heroScope: '${status.id}-$index',
              onOpenStatus: (id) => openStatus(
                context,
                statusId: id,
                seed: status,
              ),
              onOpenUser: (uid) => openUser(context, uid),
              onOpenTopic: (name) => openTopic(context, name),
              onOpenUrl: (url) => openLink(context, url),
              onOpenMedia: (media, mediaIndex, heroTag) {
                if (media[mediaIndex].kind == MediaKind.video) {
                  openVideo(context, media[mediaIndex].url, coverUrl: media[mediaIndex].previewUrl);
                } else {
                  openImage(context, media: media, index: mediaIndex, heroTag: heroTag);
                }
              },
              onRepost: () => openCompose(context, type: DraftType.repost, statusId: status.id),
              onComment: () => showCommentSheet(context, statusId: status.id, target: status),
            ),
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
  const _ReadMarker();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = Expanded(child: Divider(color: scheme.primary.withValues(alpha: 0.35), height: 1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '上次看到这里',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary),
            ),
          ),
          line,
        ],
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey<IconData>(icon),
      color: scheme.primary,
      elevation: 3,
      shadowColor: Colors.black38,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                    )
                  : Icon(icon, size: 16, color: scheme.onPrimary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: scheme.onPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.pager});

  final PagingController<Status> pager;

  @override
  Widget build(BuildContext context) {
    if (pager.loadingMore) return const LoadingFooter();
    if (pager.moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: TextButton(
            onPressed: pager.loadMore,
            child: const Text('加载失败，点此重试'),
          ),
        ),
      );
    }
    if (!pager.hasMore && pager.items.isNotEmpty) {
      return const LoadingFooter(text: '没有更多了');
    }
    return const SizedBox(height: 28);
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