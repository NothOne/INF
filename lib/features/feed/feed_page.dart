import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/look.dart';
import '../../core/haptics.dart';
import '../../core/hot_search_store.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/parse.dart';
import '../../core/session.dart';
import '../../core/status_store.dart';
import '../../core/widgets/comment_sheet.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/hot_search_row.dart';
import '../../core/widgets/paged_status_list.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/status_card.dart';
import '../../core/widgets/transitions.dart';
import 'feed_controller.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => FeedPageState();
}

/// The three pages under the home bar, left to right. The feed is where the app opens.
enum _HomePage { feed, hot, board }

class FeedPageState extends State<FeedPage> {
  late final FeedController _controller = FeedController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey<InfRefreshIndicatorState> _refreshKey = GlobalKey<InfRefreshIndicatorState>();
  final GlobalKey<PopupMenuButtonState<FeedSource>> _pickerKey = GlobalKey<PopupMenuButtonState<FeedSource>>();
  final PageController _pages = PageController();
  _HomePage _page = _HomePage.feed;

  PagingController<Status>? _hotPager;
  final ScrollController _hotScroll = ScrollController();
  final ScrollController _boardScroll = ScrollController();
  final GlobalKey<InfRefreshIndicatorState> _boardRefreshKey = GlobalKey<InfRefreshIndicatorState>();

  /// The bottom bar's home button: back to the top of the page shown, or refresh it when already
  /// there.
  Future<void> homeTap() async {
    switch (_page) {
      case _HomePage.feed:
        return _feedHomeTap();
      case _HomePage.hot:
        if (await _toTop(_hotScroll)) return;
        await _hotPager?.refresh();
      case _HomePage.board:
        if (await _toTop(_boardScroll)) return;
        await _boardRefreshKey.currentState?.show();
    }
  }

  Future<bool> _toTop(ScrollController scroll) async {
    if (!scroll.hasClients || scroll.offset <= 8) return false;
    await scroll.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
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

  void _selectPage(_HomePage page) {
    if (page == _page) {
      if (page == _HomePage.feed) _pickerKey.currentState?.showButtonMenu();
      return;
    }
    _pages.animateToPage(page.index, duration: InfMotion.tabIn, curve: Curves.easeOutCubic);
  }

  void _pageChanged(int index) {
    final page = _HomePage.values[index];
    Haptic.selection.play();
    setState(() => _page = page);
    if (page == _HomePage.hot && _hotPager == null) {
      _hotPager = PagingController<Status>(
        fetch: (cursor) => WeiboApi.instance.feed(FeedSource.hot, Session.instance.uid ?? '', cursor),
        id: (status) => status.id,
      )..refresh();
    }
    if (page == _HomePage.board) HotSearchStore.instance.load();
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
              KeepAlivePage(child: _HotBoard(scroll: _boardScroll, refreshKey: _boardRefreshKey)),
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
      key: const PageStorageKey<String>('home-hot'),
      pager: pager,
      controller: _hotScroll,
      bottomInset: 104,
      emptyText: '暂时没有热门微博',
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
    final title = current.kind == FeedKind.all ? '首页' : current.name;
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
        // The arrow hangs off the label so the label stays centred in its slot like the others.
        child: Stack(
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
                opacity: enabled ? 1 : 0.0,
                duration: InfMotion.feedback,
                child: const Icon(Icons.arrow_drop_down_rounded, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页 · 热门 · 热搜 in equal slots, 热门 at the centre of the bar. Each label follows the swipe:
/// it darkens and underlines as its page slides in, so dragging between pages reads on the bar too.
class _HomeTabs extends StatelessWidget {
  const _HomeTabs({
    required this.pages,
    required this.current,
    required this.onSelect,
    required this.feedLabel,
  });

  final PageController pages;
  final _HomePage current;
  final ValueChanged<_HomePage> onSelect;
  final Widget feedLabel;

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
            tab(_HomePage.hot, const Text('热门')),
            tab(_HomePage.board, const Text('热搜')),
          ],
        );
      },
    );
  }
}

/// weibo.com's boards as a home page: 热搜 and the 文娱/社会/生活/体育 boards behind a row of
/// chips, each entry with its badge, category and time on the board; a tap opens the entry's page.
class _HotBoard extends StatefulWidget {
  const _HotBoard({required this.scroll, required this.refreshKey});

  final ScrollController scroll;
  final GlobalKey<InfRefreshIndicatorState> refreshKey;

  @override
  State<_HotBoard> createState() => _HotBoardState();
}

class _HotBoardState extends State<_HotBoard> {
  HotBoard _board = HotBoard.realtime;

  void _select(HotBoard board) {
    if (board == _board) return;
    Haptic.selection.play();
    setState(() => _board = board);
    HotSearchStore.instance.load(board: board);
  }

  static const _capsule = 46.0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final chrome = InfChrome.of(context);
    // When content runs under the chrome (glass), the chips float over the list as a capsule and
    // the entries scroll beneath it; otherwise they are a plain row above the list.
    final floating = chrome.extendsBehindBars;
    final listTop = floating ? _capsule + 12 : 0.0;
    return AnimatedBuilder(
      animation: HotSearchStore.instance,
      builder: (context, _) {
        final store = HotSearchStore.instance;
        final board = _board;
        final entries = store.entriesOf(board);
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
            key: widget.refreshKey,
            onRefresh: () => store.load(board: board, force: true),
            child: ListView.builder(
              key: PageStorageKey<String>('home-board-${board.name}'),
              controller: widget.scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: floating ? top + listTop : 0,
                bottom: 104 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: entries.isEmpty ? 1 : entries.length,
              itemBuilder: (context, index) {
                if (entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: EmptyHint(text: '这个榜单暂时是空的', icon: Icons.local_fire_department_outlined),
                  );
                }
                final entry = entries[index];
                return HotSearchRow(
                  entry: entry,
                  detailed: true,
                  onTap: () => openHotTopic(context, query: entry.query, entry: entry),
                );
              },
            ),
          );
        }
        final chips = _BoardChips(
          current: board,
          updatedAt: store.loadedAtOf(board),
          onSelect: _select,
          floating: floating,
        );
        if (!floating) {
          return Padding(
            padding: EdgeInsets.only(top: top),
            child: Column(children: [chips, Expanded(child: list)]),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: entries == null ? Padding(padding: EdgeInsets.only(top: top + listTop), child: list) : list,
            ),
            Positioned(
              left: 12,
              right: 12,
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

class _BoardChips extends StatelessWidget {
  const _BoardChips({required this.current, required this.updatedAt, required this.onSelect, this.floating = false});

  final HotBoard current;
  final DateTime? updatedAt;
  final ValueChanged<HotBoard> onSelect;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final at = updatedAt;
    return Padding(
      padding: floating ? const EdgeInsets.fromLTRB(5, 0, 14, 0) : const EdgeInsets.fromLTRB(12, 8, 14, 4),
      child: Row(
        children: [
          for (final board in HotBoard.values)
            Padding(
              padding: EdgeInsets.only(right: floating ? 2 : 6),
              child: _BoardChip(
                label: board.label,
                selected: board == current,
                floating: floating,
                onTap: () => onSelect(board),
              ),
            ),
          const Spacer(),
          if (at != null)
            Text('${relativeTime(at)}更新', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _BoardChip extends StatelessWidget {
  const _BoardChip({required this.label, required this.selected, required this.onTap, this.floating = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// In a floating capsule an unselected chip is only its word: a fill would sit as a second pane
  /// on the pane.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final idle = floating ? Colors.transparent : chrome.fill(scheme, scheme.surfaceContainerHigh, 0.6);
    return Material(
      color: selected ? chrome.fill(scheme, scheme.primaryContainer, floating ? 0.85 : 1) : idle,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedDefaultTextStyle(
          duration: InfMotion.feedback,
          style: Theme.of(context).textTheme.labelLarge!.copyWith(
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(label),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, pager, StatusStore.instance]),
      builder: (context, _) {
        final current = pager;
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
    return NotificationListener<ScrollNotification>(
      key: const ValueKey('list'),
      onNotification: (notification) {
        current.onScroll(notification);
        return false;
      },
      child: InfRefreshIndicator(
        key: widget.refreshKey,
        onRefresh: current.refresh,
        color: Theme.of(context).colorScheme.primary,
        child: ListView.builder(
          controller: widget.scrollController,
          key: PageStorageKey<String>('feed-${widget.controller.source.key}'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top,
            bottom: 104 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: items.length + 1,
          findChildIndexCallback: current.indexOfKey,
          itemBuilder: (context, index) {
            if (index == items.length) {
              return _Footer(pager: current);
            }
            final status = items[index];
            return AppearIn(
              key: ValueKey(status.id),
              animate: current.fresh.contains(status.id),
              child: Column(
                  children: [
                    StatusCard(
                      status: status,
                      heroScope: '${status.id}-$index',
                      onOpenStatus: (id) => openStatus(
                        context,
                        statusId: id,
                        seed: status,
                      ),
                      onOpenUser: (uid) => openUser(context, uid),
                      onOpenTopic: (name) => openTopic(context, name),
                      onOpenUrl: (url) => openWeb(context, url),
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
                    const Divider(),
                  ],
                ),
            );
          },
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