import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/hot_search_store.dart';
import '../../core/links.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/parse.dart';
import '../../core/prefs.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/hot_board_bar.dart';
import '../../core/widgets/hot_search_row.dart';
import '../../core/widgets/paged_status_list.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/smart_image.dart';
import '../../core/widgets/user_row.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  late final TextEditingController _input = TextEditingController(text: widget.initialQuery ?? '');
  late final FocusNode _focus = FocusNode();

  /// The result tabs; the search's own list replaces the defaults once its first page says.
  List<SearchChannel> _channels = SearchChannel.defaults;
  late TabController _tabs = _newTabs(0);
  final Map<int, PagingController<Status>> _statusPagers = {};
  final Map<int, PagingController<SearchEntry>> _entryPagers = {};

  String? _submitted;
  List<User>? _users;
  bool _usersLoading = false;
  String? _usersError;
  final Map<String, bool> _following = {};
  final Set<String> _followBusy = {};
  List<String> _history = [];
  bool _historyExpanded = false;
  Timer? _suggestTimer;
  final Map<String, SearchSuggestions> _suggestions = {};

  TabController _newTabs(int index) =>
      TabController(length: _channels.length, initialIndex: index, vsync: this)..addListener(_tabChanged);

  @override
  void initState() {
    super.initState();
    _history = Prefs.instance.searchHistory;
    _input.addListener(_inputChanged);
    _focus.addListener(_inputChanged);
    final initial = widget.initialQuery?.trim();
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit(initial));
    } else {
      _loadHot();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _disposeResults();
    _suggestTimer?.cancel();
    _tabs.removeListener(_tabChanged);
    _input.removeListener(_inputChanged);
    _focus.removeListener(_inputChanged);
    _tabs.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _typed => _input.text.trim();

  /// Suggestions cover whatever is being typed, results included, until it is submitted.
  bool get _suggesting => _focus.hasFocus && _typed.isNotEmpty && _typed != _submitted;

  void _inputChanged() {
    if (!mounted) return;
    setState(() {});
    final query = _typed;
    _suggestTimer?.cancel();
    if (query.isEmpty || _suggestions.containsKey(query) || query == _submitted) return;
    _suggestTimer = Timer(const Duration(milliseconds: 220), () => _loadSuggestions(query));
  }

  Future<void> _loadSuggestions(String query) async {
    try {
      final result = await WeiboApi.instance.searchSuggestions(query);
      if (!mounted) return;
      setState(() => _suggestions[query] = result);
    } catch (_) {}
  }

  /// The suggestion for the longest prefix of [query] already fetched, so the list does not
  /// blank out between keystrokes.
  SearchSuggestions? _suggestionsFor(String query) {
    for (var end = query.length; end > 0; end--) {
      final hit = _suggestions[query.substring(0, end)];
      if (hit != null) return hit;
    }
    return null;
  }

  void _tabChanged() {
    if (!mounted) return;
    if (_tabs.indexIsChanging) Haptic.selection.play();
    _startChannel(_channels[_tabs.index]);
  }

  /// Loads [channel]'s first page the first time it is shown for this query.
  void _startChannel(SearchChannel channel) {
    final query = _submitted;
    if (query == null) return;
    switch (channel.kind) {
      case SearchResultKind.users:
        if (_users == null && !_usersLoading) _loadUsers(query);
      case SearchResultKind.statuses:
        if (_statusPagers.containsKey(channel.type)) return;
        final pager = _statusPagers[channel.type] = PagingController<Status>(
          fetch: (cursor) async {
            final (page, channels) = await WeiboApi.instance.searchStatuses(query, channel.type, cursor);
            if (channels != null) _applyChannels(channels);
            return page;
          },
          id: (status) => status.id,
        );
        pager.refresh();
        setState(() {});
      case SearchResultKind.entries:
        if (_entryPagers.containsKey(channel.type)) return;
        final pager = _entryPagers[channel.type] = PagingController<SearchEntry>(
          fetch: (cursor) => WeiboApi.instance.searchEntries(query, channel.type, cursor),
          id: (entry) => '${entry.title}\u001F${entry.url}',
        );
        pager.refresh();
        setState(() {});
    }
  }

  /// The tabs Weibo offers for this search, keeping the one on screen selected.
  void _applyChannels(List<SearchChannel> channels) {
    if (!mounted || listEquals(channels, _channels)) return;
    final current = _channels[_tabs.index];
    final index = channels.indexWhere((channel) => channel.type == current.type);
    final old = _tabs;
    setState(() {
      _channels = channels;
      _tabs = _newTabs(index < 0 ? 0 : index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    if (index < 0) _startChannel(_channels.first);
  }

  void _disposeResults() {
    for (final pager in _statusPagers.values) {
      pager.dispose();
    }
    for (final pager in _entryPagers.values) {
      pager.dispose();
    }
    _statusPagers.clear();
    _entryPagers.clear();
  }

  HotBoard _board = shownBoard(HotBoard.realtime);

  Future<void> _loadHot() => HotSearchStore.instance.load(board: shownBoard(_board));

  void _selectBoard(HotBoard board) {
    if (board == _board) return;
    Haptic.selection.play();
    setState(() => _board = board);
    HotSearchStore.instance.load(board: board);
  }

  Future<void> _loadUsers(String query) async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });
    try {
      final users = await WeiboApi.instance.searchUsers(query);
      if (mounted) setState(() => _users = users);
    } catch (error) {
      if (mounted) setState(() => _usersError = error is ApiException ? error.message : '加载失败');
    } finally {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _submit([String? value]) async {
    final query = (value ?? _input.text).trim();
    if (query.isEmpty) return;
    _focus.unfocus();
    final link = linkInText(query);
    if (link != null) {
      await openLink(context, link);
      return;
    }
    await Prefs.instance.addSearch(query);
    if (!mounted) return;
    setState(() {
      _input.text = query;
      _input.selection = TextSelection.collapsed(offset: query.length);
      _submitted = query;
      _history = Prefs.instance.searchHistory;
      _users = null;
      _usersError = null;
      _disposeResults();
    });
    _startChannel(_channels[_tabs.index]);
    // 综合 brings the list of tabs; ask for it even when another tab is on screen.
    final all = _channels.where((channel) => channel.type == 1).firstOrNull;
    if (all != null) _startChannel(all);
  }

  void _clearResults() {
    setState(() {
      _submitted = null;
      _input.clear();
      _disposeResults();
    });
    _focus.requestFocus();
    _loadHot();
  }

  Future<void> _toggleFollow(User user) async {
    if (_followBusy.contains(user.id)) return;
    final next = !(_following[user.id] ?? user.following);
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    setState(() {
      _followBusy.add(user.id);
      _following[user.id] = next;
    });
    try {
      await WeiboApi.instance.setFollowing(user.id, next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _following[user.id] = !next);
      Haptic.error.play();
      showMessage(context, error is ApiException ? error.message : '操作失败');
    } finally {
      if (mounted) setState(() => _followBusy.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showing = _submitted != null;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        leading: IconButton(
          onPressed: showing ? _clearResults : () => Navigator.of(context).maybePop(),
          icon: Icon(showing ? Icons.arrow_back_rounded : Icons.arrow_back_rounded),
        ),
        titleSpacing: 0,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _input,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: '搜索微博、用户，或粘贴微博链接',
              filled: false,
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              suffixIcon: _input.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _input.clear();
                        setState(() {});
                      },
                      iconSize: 18,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => _submit(), child: const Text('搜索')),
          const SizedBox(width: 4),
        ],
      ),
      body: Builder(
        builder: (context) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          child: _suggesting
              ? _suggestBody(context)
              : (showing ? _resultsBody(context) : _discoverBody(context)),
        ),
      ),
    );
  }

  Widget _discoverBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('discover'),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24 + MediaQuery.paddingOf(context).bottom,
        left: contentGutter(context),
        right: contentGutter(context),
      ),
      children: [
        if (_history.isNotEmpty) ...[
          SectionHeader(
            title: '搜索历史',
            action: TextButton(onPressed: _confirmClearHistory, child: const Text('清空')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                const spacing = 8.0;
                final widths = [for (final entry in _history) historyChipWidth(context, entry)];
                final toggleWidth = plainChipWidth(context, '收起');
                // Everything already fits in two rows: folding would hide nothing, so show it all.
                final foldable = collapsedChipCount(
                  widths,
                  maxWidth: maxWidth,
                  trailingWidth: toggleWidth,
                  spacing: spacing,
                );
                final canFold = foldable < _history.length;
                final shown = _historyExpanded && canFold ? _history.length : foldable;
                return AnimatedSize(
                  duration: InfMotion.content,
                  curve: InfMotion.emphasized,
                  alignment: Alignment.topCenter,
                  child: Wrap(
                    spacing: spacing,
                    runSpacing: 6,
                    children: [
                      for (final entry in _history.take(shown)) _historyChip(context, entry),
                      if (canFold)
                        ActionChip(
                          label: Text(_historyExpanded ? '收起' : '展开'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            Haptic.selection.play();
                            setState(() => _historyExpanded = !_historyExpanded);
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        const SectionHeader(title: '微博热搜'),
        AnimatedBuilder(
          animation: Listenable.merge([HotSearchStore.instance, Prefs.instance]),
          builder: (context, _) {
            final store = HotSearchStore.instance;
            final board = shownBoard(_board);
            final hot = store.entriesOf(board);
            final Widget rows;
            if (hot == null && store.errorOf(board) != null) {
              rows = Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: ErrorRetry(message: store.errorOf(board), onRetry: () => store.load(board: board, force: true)),
                ),
              );
            } else if (hot == null) {
              rows = const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              );
            } else if (hot.isEmpty) {
              rows = Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text('这个榜单暂时是空的', style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              );
            } else {
              rows = Column(
                children: [
                  for (final entry in hot)
                    HotSearchRow(
                      entry: entry,
                      detailed: true,
                      onTap: () => openHotTopic(context, query: entry.query, entry: entry),
                    ),
                ],
              );
            }
            return Column(
              children: [
                HotBoardChips(current: board, onSelect: _selectBoard),
                rows,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _suggestBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _typed;
    final found = _suggestionsFor(query);
    final users = found?.users.take(3).toList() ?? const <User>[];
    final words = found?.words ?? const <SearchSuggestion>[];
    return ListView(
      key: const ValueKey('suggest'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: 24 + MediaQuery.paddingOf(context).bottom,
        left: contentGutter(context),
        right: contentGutter(context),
      ),
      children: [
        ListTile(
          leading: Icon(Icons.search_rounded, color: scheme.primary),
          title: Text.rich(
            TextSpan(children: [
              const TextSpan(text: '搜索 '),
              TextSpan(text: '「$query」', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _submit(query),
        ),
        for (final user in users)
          ListTile(
            leading: Avatar(url: user.avatarUrl, size: 36, verified: user.verified),
            title: _Highlighted(text: user.screenName, query: query),
            subtitle: Text(
              _userAbout(user),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              _focus.unfocus();
              openUser(context, user.id);
            },
          ),
        for (final word in words)
          ListTile(
            leading: Icon(
              word.hot ? Icons.trending_up_rounded : Icons.search_rounded,
              color: word.hot ? const Color(0xFFFF7A1A) : scheme.onSurfaceVariant,
              size: 22,
            ),
            title: _Highlighted(text: word.word, query: query),
            trailing: IconButton(
              tooltip: '填入搜索框',
              icon: Icon(Icons.north_west_rounded, size: 18, color: scheme.onSurfaceVariant),
              onPressed: () {
                Haptic.selection.play();
                _input.text = word.word;
                _input.selection = TextSelection.collapsed(offset: word.word.length);
              },
            ),
            onTap: () => _submit(word.word),
          ),
      ],
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空搜索历史？'),
        content: const Text('搜索记录只保存在本机，清空后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (confirmed != true) return;
    await Prefs.instance.clearSearchHistory();
    if (!mounted) return;
    setState(() {
      _history = const [];
      _historyExpanded = false;
    });
  }

  Future<void> _removeHistory(String entry) async {
    await Prefs.instance.removeSearch(entry);
    if (mounted) setState(() => _history = Prefs.instance.searchHistory);
  }

  Widget _historyChip(BuildContext context, String entry) {
    return InputChip(
      label: Text(entry, maxLines: 1, overflow: TextOverflow.ellipsis),
      onPressed: () => _submit(entry),
      onDeleted: () => _removeHistory(entry),
      deleteIcon: const Icon(Icons.close_rounded, size: 15),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _resultsBody(BuildContext context) {
    return Padding(
      key: const ValueKey('results'),
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: Column(
        children: [
          ContentColumn(
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.label,
              labelPadding: const EdgeInsets.symmetric(horizontal: 13),
              tabs: [for (final channel in _channels) Tab(height: 44, text: channel.name)],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final channel in _channels)
                  KeepAlivePage(
                    key: ValueKey('$_submitted-${channel.type}'),
                    child: _channelBody(channel),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelBody(SearchChannel channel) {
    switch (channel.kind) {
      case SearchResultKind.users:
        return _usersTab();
      case SearchResultKind.statuses:
        final pager = _statusPagers[channel.type];
        if (pager == null) return const LoadingFooter();
        return PagedStatusList(
          pager: pager,
          emptyText: '没有找到相关${channel.name == '综合' ? '微博' : channel.name}',
          bottomInset: 18,
          underAppBar: false,
        );
      case SearchResultKind.entries:
        final pager = _entryPagers[channel.type];
        if (pager == null) return const LoadingFooter();
        return _EntryList(pager: pager, emptyText: '没有找到相关${channel.name}');
    }
  }

  Widget _usersTab() {
    if (_usersLoading && _users == null) return const LoadingFooter();
    if (_users == null && _usersError != null) {
      return Center(child: ErrorRetry(message: _usersError, onRetry: () => _loadUsers(_submitted ?? '')));
    }
    final users = _users;
    if (users == null) return const LoadingFooter();
    if (users.isEmpty) return const EmptyHint(text: '没有找到相关用户', icon: Icons.person_search_rounded);
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: 22 + MediaQuery.paddingOf(context).bottom,
        left: contentGutter(context),
        right: contentGutter(context),
      ),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return UserListRow(
          user: user,
          following: _following[user.id] ?? user.following,
          busy: _followBusy.contains(user.id),
          onToggleFollow: () => _toggleFollow(user),
          onTap: () => openUser(context, user.id),
        );
      },
    );
  }
}

String _userAbout(User user) {
  final about = [
    if (user.followersCount > 0) '粉丝 ${compactCount(user.followersCount)}',
    if (user.description.trim().isNotEmpty) user.description.trim(),
  ].join(' · ');
  return about.isEmpty ? '用户' : about;
}

/// A channel of topics, super topics, places and the like: one row each.
class _EntryList extends StatelessWidget {
  const _EntryList({required this.pager, required this.emptyText});

  final PagingController<SearchEntry> pager;
  final String emptyText;

  void _open(BuildContext context, SearchEntry entry) {
    if (entry.isTopic) {
      openTopic(context, entry.title);
    } else if (entry.url != null) {
      openLink(context, entry.url!, title: entry.title);
    } else {
      openHotTopic(context, query: entry.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pager,
      builder: (context, _) {
        if (pager.items.isEmpty) {
          if (pager.error != null) return Center(child: ErrorRetry(message: pager.error.toString(), onRetry: pager.refresh));
          if (pager.loading || pager.refreshedAt == null) return const LoadingFooter();
          return EmptyHint(text: emptyText, icon: Icons.manage_search_rounded);
        }
        final scheme = Theme.of(context).colorScheme;
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            pager.onScroll(notification);
            return false;
          },
          child: InfRefreshIndicator(
            onRefresh: pager.refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: 22 + MediaQuery.paddingOf(context).bottom,
                left: contentGutter(context),
                right: contentGutter(context),
              ),
              itemCount: pager.items.length + 1,
              itemBuilder: (context, index) {
                if (index == pager.items.length) {
                  if (pager.loadingMore) return const LoadingFooter();
                  return pager.hasMore ? const SizedBox(height: 24) : const LoadingFooter(text: '没有更多了');
                }
                final entry = pager.items[index];
                final about = [entry.subtitle, entry.detail].whereType<String>().join(' · ');
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: entry.imageUrl == null
                          ? ColoredBox(
                              color: scheme.surfaceContainerHigh,
                              child: Icon(entry.isTopic ? Icons.tag_rounded : Icons.link_rounded, color: scheme.onSurfaceVariant),
                            )
                          : SmartImage(url: entry.imageUrl, fit: BoxFit.cover),
                    ),
                  ),
                  title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: about.isEmpty ? null : Text(about, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _open(context, entry),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// How many of [widths] fit in the first [rows] rows of a [Wrap] whose line is [maxWidth] wide,
/// leaving room on the last of them for a control [trailingWidth] wide. Everything when nothing
/// would be hidden, so the caller can compare with the entry count to know whether to offer the
/// fold at all.
int collapsedChipCount(
  List<double> widths, {
  required double maxWidth,
  required double trailingWidth,
  int rows = 2,
  double spacing = 8,
}) {
  if (maxWidth <= 0) return 0;
  if (_wrapRows(widths, maxWidth: maxWidth, spacing: spacing) <= rows) return widths.length;
  var count = 0;
  for (var shown = 1; shown < widths.length; shown++) {
    if (_wrapRows([...widths.take(shown), trailingWidth], maxWidth: maxWidth, spacing: spacing) <= rows) {
      count = shown;
    }
  }
  // A line too narrow for the control beside any chip still shows one, which reads better than
  // nothing above the fold.
  return math.max(count, 1);
}

int _wrapRows(List<double> widths, {required double maxWidth, double spacing = 8}) {
  var rows = 1;
  var used = 0.0;
  for (final width in widths) {
    final item = math.min(width, maxWidth);
    if (used > 0 && used + spacing + item > maxWidth) {
      rows++;
      used = item;
    } else {
      used += (used > 0 ? spacing : 0) + item;
    }
  }
  return rows;
}

/// What a history chip adds around its label at 1× text: padding, the delete icon and the border.
/// Measured against the app theme; it grows with the text scale, which the label width already
/// carries, so a little more is added on top of it.
const _historyChipChrome = 53.0;

/// The [ActionChip] that folds and unfolds the history, which has no delete icon.
const _plainChipChrome = 34.0;

/// How much a chip's chrome grows per unit of text scale past 1 (measured 53 → 64 from 1× to 2×).
const _chromeGrowth = 11.0;

double _textScale(BuildContext context) => MediaQuery.textScalerOf(context).scale(14) / 14;

/// The width [text] takes as a chip label, one point over so the estimate never comes up short.
double chipLabelWidth(BuildContext context, String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: Theme.of(context).textTheme.labelLarge),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width + 1;
}

double _chipChrome(BuildContext context, double base) => base + _chromeGrowth * math.max(0, _textScale(context) - 1);

/// One history chip as a [Wrap] lays it out: as wide as its label plus [InputChip]'s padding,
/// delete icon and border.
double historyChipWidth(BuildContext context, String entry) =>
    chipLabelWidth(context, entry) + _chipChrome(context, _historyChipChrome);

/// The same for the [ActionChip] that folds and unfolds the history.
double plainChipWidth(BuildContext context, String label) =>
    chipLabelWidth(context, label) + _chipChrome(context, _plainChipChrome);

/// [text] with the characters of [query] it contains picked out, the way completions read.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    final start = needle.isEmpty ? -1 : lower.indexOf(needle);
    // Pinyin typed for Chinese matches nothing literally; picking out stray letters would be noise.
    if (start < 0) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text.substring(0, start)),
        TextSpan(
          text: text.substring(start, start + needle.length),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        TextSpan(text: text.substring(start + needle.length)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
