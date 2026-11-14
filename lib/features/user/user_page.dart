import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/image_url.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/parse.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';
import '../../core/share.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/paged_status_list.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/smart_image.dart';
import '../../core/widgets/status_actions.dart';
import '../../core/widgets/status_menu_route.dart';
import '../../core/widgets/transitions.dart';
import '../../core/widgets/viewer_hero.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.uid});

  final String uid;

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> with TickerProviderStateMixin {
  UserProfile? _profile;
  bool _loading = true;
  bool _followBusy = false;
  String? _error;

  /// The page's sections; weibo.com's own list replaces the usual four once it answers.
  List<ProfileTab> _tabs = ProfileTab.fallback;
  late TabController _tabController = _newTabs(0);
  ProfilePostFilter _filter = ProfilePostFilter.all;

  /// Each section's posts, made the first time it is shown; 微博 has one per filter.
  final Map<String, PagingController<Status>> _pagers = {};
  PagingController<ProfilePhoto>? _photos;
  ProfileExtras? _extras;

  /// The header's scroll: 0 open, its max folded away under the bar.
  final ScrollController _outer = ScrollController();

  /// 0 with the header open, 1 once only the bar and the tabs are left.
  final ValueNotifier<double> _folded = ValueNotifier(0);

  /// Once folded away the header stays so while the posts scroll back; tapping the bar opens it.
  final ValueNotifier<bool> _locked = ValueNotifier(false);
  late final ScrollPhysics _outerPhysics = _HeaderLockPhysics(locked: () => _locked.value);
  bool _opening = false;

  /// The header's own height, measured; the bar's open height follows it.
  double? _headerHeight;

  @override
  void initState() {
    super.initState();
    _outer.addListener(_outerMoved);
    _load();
  }

  @override
  void dispose() {
    _outer.dispose();
    _folded.dispose();
    _locked.dispose();
    _tabController.dispose();
    for (final pager in _pagers.values) {
      pager.dispose();
    }
    _photos?.dispose();
    super.dispose();
  }

  TabController _newTabs(int index) =>
      TabController(length: _tabs.length, initialIndex: index, vsync: this)..addListener(_tabChanged);

  void _tabChanged() {
    if (_tabController.indexIsChanging) Haptic.selection.play();
    _start(_tabs[_tabController.index]);
  }

  String _key(ProfileTab tab) => tab == ProfileTab.posts ? 'posts:${_filter.name}' : tab.name;

  void _start(ProfileTab tab) {
    final profile = _profile;
    if (profile == null) return;
    final uid = profile.user.id;
    final api = WeiboApi.instance;
    if (tab == ProfileTab.photos) {
      if (_photos != null) return;
      _photos = PagingController<ProfilePhoto>(fetch: (cursor) => api.profilePhotos(uid, cursor), id: (photo) => photo.media.url)
        ..refresh();
      setState(() {});
      return;
    }
    final key = _key(tab);
    if (_pagers.containsKey(key)) return;
    final filter = _filter;
    _pagers[key] = PagingController<Status>(
      fetch: (cursor) => switch (tab) {
        ProfileTab.posts when filter == ProfilePostFilter.all => api.userTimeline(uid, cursor),
        ProfileTab.posts => api.profilePosts(uid, filter.suffix, cursor),
        ProfileTab.featured => api.profileFeatured(uid, cursor),
        ProfileTab.videos => api.profileVideos(uid, cursor),
        ProfileTab.audio => api.profileAudio(uid, cursor),
        ProfileTab.articles => api.profilePosts(uid, 'ARTICAL', cursor),
        ProfileTab.photos => throw StateError('相册 pages through _photos'),
      },
      id: (status) => status.id,
    )..refresh();
    setState(() {});
  }

  void _outerMoved() {
    if (!_outer.hasClients) return;
    final position = _outer.position;
    final max = position.maxScrollExtent;
    _folded.value = max <= 0 ? 0 : (position.pixels / max).clamp(0.0, 1.0);
    if (!_opening && !_locked.value && max > 0 && position.pixels >= max - 0.5) _locked.value = true;
  }

  Future<void> _openHeader() async {
    if (!_outer.hasClients || _opening) return;
    Haptic.selection.play();
    _opening = true;
    _locked.value = false;
    try {
      await _outer.animateTo(0, duration: InfMotion.push, curve: InfMotion.emphasized);
    } finally {
      _opening = false;
    }
  }

  Future<void> _loadTabs(String uid) async {
    final extras = await WeiboApi.instance.profileExtras(uid);
    if (!mounted) return;
    setState(() => _extras = extras);
    final tabs = extras.tabs;
    if (listEquals(tabs, _tabs)) return;
    final index = tabs.indexOf(_tabs[_tabController.index]);
    final old = _tabController;
    setState(() {
      _tabs = tabs;
      _tabController = _newTabs(index < 0 ? 0 : index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _start(_tabs[_tabController.index]);
  }

  void _selectFilter(ProfilePostFilter filter) {
    if (filter == _filter) return;
    Haptic.selection.play();
    setState(() => _filter = filter);
    _start(ProfileTab.posts);
  }

  Future<bool> _refresh() async {
    final profile = _profile;
    if (profile == null) {
      await _load();
      return _profile != null;
    }
    WeiboApi.instance.userProfile(profile.user.id).then((fresh) {
      if (fresh != null && mounted) setState(() => _profile = fresh);
    }).catchError((_) {});
    final tab = _tabs[_tabController.index];
    if (tab == ProfileTab.photos) return await _photos?.refresh() ?? true;
    return await _pagers[_key(tab)]?.refresh() ?? true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var uid = widget.uid;
      if (!RegExp(r'^\d+$').hasMatch(uid)) {
        final resolved = await WeiboApi.instance.resolveUid(uid);
        if (resolved == null) throw ApiException('找不到用户 ${widget.uid}');
        uid = resolved;
      }
      final profile = await WeiboApi.instance.userProfile(uid);
      if (profile == null) throw ApiException('找不到用户 ${widget.uid}');
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
      _start(_tabs[_tabController.index]);
      _loadTabs(profile.user.id);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '加载失败';
      });
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || _followBusy || profile.user.id == Session.instance.uid) return;
    if (profile.following) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text('不再关注 ${profile.user.screenName}？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('不再关注')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final next = !profile.following;
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    setState(() {
      _followBusy = true;
      _profile = profile.withFollowing(next);
    });
    try {
      await WeiboApi.instance.setFollowing(profile.user.id, next);
      if (mounted) showMessage(context, next ? '已关注' : '已取消关注');
    } catch (error) {
      if (!mounted) return;
      setState(() => _profile = profile);
      Haptic.error.play();
      showMessage(context, error is ApiException ? error.message : '操作失败');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  /// The page's `⋯`: the same menu, in the same place, as the one a post opens, so the app has one
  /// way of offering these rather than one per page.
  void _showMenu(UserProfile profile, bool isSelf, BuildContext anchor) {
    final user = profile.user;
    final blocked = Prefs.instance.isBlocked(user.id);
    showGlassActions(
      context,
      anchor: anchor,
      originRadius: 20,
      // Against the button's own corner: the header is where the finger already is.
      placement: StatusMenuPlacement.anchored,
      actions: [
        StatusAction(
          icon: Icons.ios_share_rounded,
          label: '分享用户',
          run: () async => shareText(userShareText(user)),
        ),
        StatusAction(
          icon: Icons.manage_search_rounded,
          label: '搜索微博',
          run: () async => openUserSearch(context, uid: user.id, name: user.screenName),
        ),
        if (!isSelf)
          StatusAction(
            icon: Icons.person_off_outlined,
            label: '一键拉黑',
            destructive: true,
            startsGroup: true,
            run: () => _blacklist(profile),
          ),
        if (!isSelf)
          StatusAction(
            icon: Icons.report_outlined,
            label: '举报用户',
            destructive: true,
            run: () async => openWeb(context, userReportLink(user.id)),
          ),
        if (!isSelf)
          StatusAction(
            icon: blocked ? Icons.visibility_outlined : Icons.block_rounded,
            label: blocked ? '取消屏蔽' : '屏蔽此人',
            run: () => blocked ? _unblock(user) : confirmBlockUser(context, user),
          ),
      ],
    );
  }

  Future<void> _unblock(User user) async {
    await Prefs.instance.setBlocked(user, false);
    Haptic.success.play();
    if (mounted) showMessage(context, '已取消屏蔽 @${user.screenName}');
  }

  Future<void> _blacklist(UserProfile profile) async {
    final user = profile.user;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('将 @${user.screenName} 加入黑名单？'),
        content: const Text('不看 TA 的微博，TA 不能评论、私信、@ 你，也不能关注你；已有的关注会被解除。可在微博的「设置 · 屏蔽设置」里解除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('拉黑')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await WeiboApi.instance.blacklist(user.id);
      Haptic.success.play();
      if (!mounted) return;
      setState(() => _profile = _profile?.withFollowing(false));
      showMessage(context, '已将 @${user.screenName} 加入黑名单');
    } catch (error) {
      Haptic.error.play();
      if (mounted) showMessage(context, error is ApiException ? error.message : '拉黑失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = _profile;
    final isSelf = profile != null && profile.user.id == Session.instance.uid;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: profile != null
          ? null
          : AppBar(
              flexibleSpace: lookBarBackground(context),
              title: Text(widget.uid, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
      body: StateSwitcher(
        child: Builder(
          key: ValueKey(profile != null ? 'profile' : (_loading ? 'loading' : 'error')),
          builder: (context) {
            if (profile == null && !_loading) {
              return Center(child: ErrorRetry(message: _error, onRetry: _load));
            }
            if (profile == null) return const _ProfileSkeleton();
            return InfRefreshIndicator(
              onRefresh: _refresh,
              notificationPredicate: nestedScrollRefreshPredicate,
              child: NestedScrollView(
                controller: _outer,
                physics: _outerPhysics,
                headerSliverBuilder: (context, _) => [
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                    sliver: _headerBar(context, profile, isSelf),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    for (final tab in _tabs)
                      KeepAlivePage(
                        key: ValueKey(tab),
                        child: Builder(builder: (context) => _section(context, tab, profile.user.id)),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The top bar with the whole header inside it, cover up under the status bar, and the tabs as its
  /// bottom; it folds down to the bar and the tabs.
  Widget _headerBar(BuildContext context, UserProfile profile, bool isSelf) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final header = _SizeReporter(
      onHeight: (height) {
        if (height != _headerHeight) setState(() => _headerHeight = height);
      },
      child: _ProfileHeader(
        profile: profile,
        extras: _extras,
        isSelf: isSelf,
        coverHeight: top + kToolbarHeight + 92,
        followBusy: _followBusy,
        onToggleFollow: _toggleFollow,
        onMessage: () => openChat(context, uid: profile.user.id, name: profile.user.screenName, avatar: profile.user.avatarUrl),
        onRelations: (kind) => openRelations(context, uid: profile.user.id, kind: kind),
      ),
    );
    final openHeight = math.max((_headerHeight ?? top + kToolbarHeight + 320) - top, kToolbarHeight) + _stripHeight;
    final hasCover = (_extras?.coverUrl ?? profile.coverUrl) != null;
    final tabs = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 0.6)),
      ),
      child: ContentColumn(
        child: TabBar(
          controller: _tabController,
          isScrollable: _tabs.length > 5,
          tabAlignment: _tabs.length > 5 ? TabAlignment.start : null,
          indicatorSize: TabBarIndicatorSize.label,
          dividerHeight: 0,
          tabs: [for (final tab in _tabs) Tab(height: _stripHeight - 1, text: tab.label)],
        ),
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: _folded,
      child: header,
      builder: (context, folded, header) {
        final overCover = hasCover && folded < 0.6;
        final foreground = overCover ? Colors.white : scheme.onSurface;
        final icons = IconThemeData(color: foreground, shadows: overCover ? const [Shadow(color: Colors.black45, blurRadius: 6)] : null);
        return SliverAppBar(
          pinned: true,
          expandedHeight: openHeight,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: foreground,
          iconTheme: icons,
          actionsIconTheme: icons,
          systemOverlayStyle: overCover ? SystemUiOverlayStyle.light : null,
          title: Opacity(
            opacity: ((folded - 0.7) / 0.3).clamp(0.0, 1.0),
            child: GestureDetector(
              onTap: _openHeader,
              child: ValueListenableBuilder<bool>(
                valueListenable: _locked,
                builder: (context, locked, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(profile.user.screenName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (locked) Icon(Icons.expand_more_rounded, size: 22, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          actions: chrome.barActions(context, [
            Builder(
              // The button's own context, so the menu anchors to it rather than to the page.
              builder: (buttonContext) => IconButton(
                onPressed: () => _showMenu(profile, isSelf, buttonContext),
                tooltip: '更多',
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ),
          ]),
          flexibleSpace: _HeaderSpace(
            header: header!,
            folded: folded,
            bar: lookBarBackground(context) ?? ColoredBox(color: scheme.surface),
            barCanFade: chrome.panelsCanFade,
            onTapBar: _openHeader,
          ),
          bottom: PreferredSize(preferredSize: const Size.fromHeight(_stripHeight), child: tabs),
        );
      },
    );
  }

  Widget _section(BuildContext context, ProfileTab tab, String uid) {
    if (tab == ProfileTab.photos) {
      final photos = _photos;
      if (photos == null) return const _NestedLoading();
      return _PhotoWall(pager: photos, uid: uid);
    }
    final pager = _pagers[_key(tab)];
    if (pager == null) return const _NestedLoading();
    if (tab == ProfileTab.videos) return _VideoWall(pager: pager);
    return PagedStatusList(
      key: PageStorageKey<String>('user-${_key(tab)}'),
      pager: pager,
      nested: true,
      underAppBar: false,
      refreshable: false,
      hideBlocked: false,
      header: tab == ProfileTab.posts ? _FilterRow(selected: _filter, onSelect: _selectFilter) : null,
      emptyText: switch (tab) {
        ProfileTab.featured => '还没有精选内容',
        ProfileTab.audio => '还没有音频',
        ProfileTab.articles => '还没有文章',
        _ => '还没有微博',
      },
    );
  }
}

const _stripHeight = 45.0;

/// The header sliding up under the bar as it folds, and the bar's own background coming in over
/// it at the end. Folded, the bar is what opens it again.
class _HeaderSpace extends StatelessWidget {
  const _HeaderSpace({
    required this.header,
    required this.folded,
    required this.bar,
    required this.barCanFade,
    required this.onTapBar,
  });

  final Widget header;
  final double folded;
  final Widget bar;
  final bool barCanFade;
  final VoidCallback onTapBar;

  @override
  Widget build(BuildContext context) {
    final settings = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
    final shift = settings.maxExtent - settings.currentExtent;
    final barHeight = settings.minExtent - _stripHeight;
    final barShown = ((folded - 0.75) / 0.25).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(top: -shift, left: 0, right: 0, child: header),
        if (barShown > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: barHeight,
            child: IgnorePointer(
              child: barCanFade ? Opacity(opacity: barShown, child: bar) : (barShown == 1 ? bar : const SizedBox()),
            ),
          ),
        if (folded > 0.95)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: barHeight,
            child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: onTapBar),
          ),
      ],
    );
  }
}

/// While [locked], the header that has folded away does not come back with the posts scrolled
/// back to their top: the outer scroll stays at its end and the rest goes on as the posts'
/// overscroll, which is the refresh pull.
class _HeaderLockPhysics extends ScrollPhysics {
  const _HeaderLockPhysics({required this.locked, super.parent});

  final ValueGetter<bool> locked;

  @override
  _HeaderLockPhysics applyTo(ScrollPhysics? ancestor) => _HeaderLockPhysics(locked: locked, parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final end = position.maxScrollExtent;
    if (locked() && end > 0 && value < position.pixels && position.pixels >= end - 0.5) return value - position.pixels;
    return super.applyBoundaryConditions(position, value);
  }
}

/// Tells [onHeight] its child's height after each layout that changes it.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) => renderObject.onHeight = onHeight;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// A section not loaded yet, below the pinned tabs like the loaded ones.
class _NestedLoading extends StatelessWidget {
  const _NestedLoading();

  @override
  Widget build(BuildContext context) => CustomScrollView(
        slivers: [
          SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
          const SliverToBoxAdapter(child: LoadingFooter()),
        ],
      );
}

/// 全部 / 原创 / 图片 / 视频 above the 微博 section.
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onSelect});

  final ProfilePostFilter selected;
  final ValueChanged<ProfilePostFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (final filter in ProfilePostFilter.values) ...[
            Material(
              color: filter == selected
                  ? chrome.fill(scheme, scheme.primaryContainer, 1)
                  : chrome.fill(scheme, scheme.surfaceContainerHigh, 0.6),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelect(filter),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    filter.label,
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                          color: filter == selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                          fontWeight: filter == selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// A section drawn as a grid of tiles under the pinned tabs, paged like a list.
class _PagedGrid<T> extends StatelessWidget {
  const _PagedGrid({
    required this.pager,
    required this.aspectRatio,
    required this.emptyText,
    required this.emptyIcon,
    required this.itemBuilder,
  });

  final PagingController<T> pager;
  final double aspectRatio;
  final String emptyText;
  final IconData emptyIcon;
  final Widget Function(BuildContext context, int index, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pager,
      builder: (context, _) {
        final gutter = contentGutter(context);
        final Widget content;
        if (pager.items.isEmpty) {
          final Widget state;
          if (pager.error != null) {
            state = ErrorRetry(message: pager.error.toString(), onRetry: pager.refresh);
          } else if (pager.loading || pager.refreshedAt == null) {
            state = const LoadingFooter();
          } else {
            state = EmptyHint(text: emptyText, icon: emptyIcon);
          }
          content = SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: state)));
        } else {
          content = SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter + 3, 3, gutter + 3, 0),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: WindowClass.of(context).wide ? 5 : 3,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
                childAspectRatio: aspectRatio,
              ),
              itemCount: pager.items.length,
              itemBuilder: (context, index) => itemBuilder(context, index, pager.items[index]),
            ),
          );
        }
        final Widget footer;
        if (pager.items.isEmpty) {
          footer = const SizedBox.shrink();
        } else if (pager.loadingMore) {
          footer = const LoadingFooter();
        } else if (pager.moreError != null) {
          footer = Center(child: TextButton(onPressed: pager.loadMore, child: const Text('加载失败，点此重试')));
        } else {
          footer = pager.hasMore ? const SizedBox(height: 24) : const LoadingFooter(text: '没有更多了');
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            pager.onScroll(notification);
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
              content,
              SliverToBoxAdapter(child: footer),
              SliverToBoxAdapter(child: SizedBox(height: 12 + MediaQuery.paddingOf(context).bottom)),
            ],
          ),
        );
      },
    );
  }
}

/// 视频: covers with their length and the post's words; a tap plays, a long press opens the post.
class _VideoWall extends StatelessWidget {
  const _VideoWall({required this.pager});

  final PagingController<Status> pager;

  @override
  Widget build(BuildContext context) {
    return _PagedGrid<Status>(
      pager: pager,
      aspectRatio: 3 / 4,
      emptyText: '还没有视频',
      emptyIcon: Icons.smart_display_outlined,
      itemBuilder: (context, index, status) {
        final video = [...status.media, ...?status.repostOf?.media].where((media) => media.kind == MediaKind.video).firstOrNull;
        void openPost() => openStatus(context, statusId: status.id, seed: status);
        return GestureDetector(
          onTap: video == null
              ? openPost
              : () => openVideo(context, video.url, coverUrl: video.previewUrl, statusId: status.id),
          onLongPress: () {
            Haptic.longPress.play();
            openPost();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                SmartImage(url: video?.previewUrl ?? status.images.firstOrNull?.previewUrl, fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                      stops: [0.55, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 5,
                  child: Text(
                    status.text.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
                  ),
                ),
                if (video != null && video.durationMs > 0)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: _Badge(text: _duration(video.durationMs)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _duration(int ms) {
    final seconds = ms ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

/// 相册: every picture the account has posted; a tap opens the viewer on all of them, a long press
/// the post it came from.
class _PhotoWall extends StatelessWidget {
  const _PhotoWall({required this.pager, required this.uid});

  final PagingController<ProfilePhoto> pager;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _PagedGrid<ProfilePhoto>(
      pager: pager,
      aspectRatio: 1,
      emptyText: '相册里还没有图片',
      emptyIcon: Icons.photo_library_outlined,
      itemBuilder: (context, index, photo) {
        final tag = 'wall-$uid-$index';
        return ViewerHero(
          tag: tag,
          transitionOnUserGestures: true,
          child: GestureDetector(
            onTap: () => openImage(context, media: [for (final item in pager.items) item.media], index: index, heroTag: tag),
            onLongPress: photo.statusId == null
                ? null
                : () {
                    Haptic.longPress.play();
                    openStatus(context, statusId: photo.statusId!);
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                SmartImage(url: photo.media.previewUrl, fit: BoxFit.cover, placeholderColor: scheme.surfaceContainerHigh),
                if (photo.media.isLive) const Positioned(left: 5, bottom: 5, child: _Badge(text: '实况')),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.56), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.2)),
    );
  }
}

/// The profile header's silhouette (cover, avatar, name, counts), so the real one fades in over
/// something of the same shape instead of replacing a spinner.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 170,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: SkeletonBox(radius: 0)),
                Positioned(
                  left: 16,
                  bottom: -30,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                    child: const SkeletonBox(width: 70, height: 70, radius: 35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 42),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 20),
                SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 12),
                SizedBox(height: 12),
                SkeletonBox(width: 200, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.extras,
    required this.isSelf,
    required this.coverHeight,
    required this.followBusy,
    required this.onToggleFollow,
    required this.onMessage,
    required this.onRelations,
  });

  final UserProfile profile;
  final ProfileExtras? extras;
  final bool isSelf;

  /// From the very top of the screen: the cover runs up under the status bar and the top bar.
  final double coverHeight;
  final bool followBusy;
  final VoidCallback onToggleFollow;
  final VoidCallback onMessage;
  final ValueChanged<RelationKind> onRelations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chrome = InfChrome.of(context);
    final user = profile.user;
    final extras = this.extras;
    final interactions = extras?.interactions;
    final facts = extras?.facts ?? const <String>[];
    final cover = extras?.coverUrl ?? profile.coverUrl;
    final avatarTag = 'avatar-${user.id}';
    return ColoredBox(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: coverHeight,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                if (cover == null)
                  ColoredBox(color: scheme.surfaceContainerHigh)
                else
                  SmartImage(url: cover, fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cover == null ? Colors.transparent : Colors.black38,
                        Colors.transparent,
                        Colors.transparent,
                        scheme.surface.withValues(alpha: 0.85),
                      ],
                      stops: const [0, 0.32, 0.55, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -30,
                  child: ContentColumn(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: user.avatarUrl == null
                                ? null
                                : () => openImage(
                                      context,
                                      media: [Media.image(avatarLarge(user.avatarUrl!), previewUrl: user.avatarUrl)],
                                      heroTag: avatarTag,
                                    ),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                              child: ViewerHero(
                                tag: avatarTag,
                                child: Avatar(url: user.avatarUrl, size: 70, verified: user.verified),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 40),
                            child: _actions(context, scheme, chrome),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 38),
          ContentColumn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(user.screenName, style: textTheme.titleLarge),
                      if (extras?.gender case final gender?) _GenderMark(female: gender == 'f'),
                      if (extras?.verified case final badge?) _VerifiedMark(badge: badge),
                      if (extras?.vip case final vip?)
                        SmartImage(
                          url: vip.url,
                          width: 16 * vip.aspect,
                          height: 16,
                          fit: BoxFit.contain,
                          placeholderColor: Colors.transparent,
                        ),
                    ],
                  ),
                  if (profile.verifiedReason != null && profile.verifiedReason!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(profile.verifiedReason!, style: textTheme.bodySmall?.copyWith(color: scheme.primary)),
                  ],
                  if (user.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(user.description, style: textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      _Count(label: '关注', value: user.followingCount, onTap: () => onRelations(RelationKind.following)),
                      _Count(label: '粉丝', value: user.followersCount, onTap: () => onRelations(RelationKind.followers)),
                      _Count(label: '微博', value: user.statusesCount),
                      if (extras?.likes != null) _Count(label: '获赞', value: extras!.likes!),
                    ],
                  ),
                  if (interactions != null && interactions > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      [
                        '转评赞 ${compactCount(interactions)}',
                        if (extras?.comments != null) '评论 ${compactCount(extras!.comments!)}',
                        if (extras?.reposts != null) '转发 ${compactCount(extras!.reposts!)}',
                      ].join(' · '),
                      style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final fact in facts)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: chrome.fill(scheme, scheme.surfaceContainerHigh, 0.7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(fact, style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, ColorScheme scheme, InfChrome chrome) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (profile.followsYou && !isSelf)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: chrome.fill(scheme, scheme.surface, 0.82),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('关注了你', style: Theme.of(context).textTheme.labelSmall),
          ),
        if (!isSelf) ...[
          SizedBox(
            height: 34,
            child: OutlinedButton(
              onPressed: onMessage,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                backgroundColor: chrome.fill(scheme, scheme.surface, 0.72),
              ),
              child: const Text('私信', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            height: 34,
            child: profile.following
                ? OutlinedButton(
                    onPressed: followBusy ? null : onToggleFollow,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      backgroundColor: chrome.fill(scheme, scheme.surface, 0.72),
                    ),
                    child: followBusy
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('已关注', style: TextStyle(fontSize: 12)),
                  )
                : FilledButton(
                    onPressed: followBusy ? null : onToggleFollow,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, 34),
                    ),
                    child: followBusy
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(profile.followsYou ? '回关' : '关注', style: const TextStyle(fontSize: 12)),
                  ),
          ),
        ],
      ],
    );
  }
}

class _GenderMark extends StatelessWidget {
  const _GenderMark({required this.female});

  final bool female;

  @override
  Widget build(BuildContext context) => Icon(
        female ? Icons.female_rounded : Icons.male_rounded,
        size: 18,
        color: female ? const Color(0xFFFF6B9A) : const Color(0xFF3D9BFF),
      );
}

/// The V in weibo.com's colour for the kind of verification.
class _VerifiedMark extends StatelessWidget {
  const _VerifiedMark({required this.badge});

  final VerifiedBadge badge;

  @override
  Widget build(BuildContext context) => Icon(
        Icons.verified_rounded,
        size: 18,
        color: switch (badge) {
          VerifiedBadge.gold => const Color(0xFFE8A200),
          VerifiedBadge.orange => const Color(0xFFFF8200),
          VerifiedBadge.yellow => const Color(0xFFFFC21A),
          VerifiedBadge.blue => const Color(0xFF2D8CF0),
          VerifiedBadge.red => const Color(0xFFE6162D),
          VerifiedBadge.grey => const Color(0xFF9E9E9E),
        },
      );
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, this.onTap});

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          Text(
            compactCount(value),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
