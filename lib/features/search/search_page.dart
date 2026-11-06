import 'dart:async';
import 'dart:math' as math;

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
import '../../core/widgets/user_row.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  late final TextEditingController _input = TextEditingController(text: widget.initialQuery ?? '');
  late final FocusNode _focus = FocusNode();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  PagingController<Status>? _results;
  String? _submitted;
  SearchSort _sort = SearchSort.all;
  List<User>? _users;
  bool _usersLoading = false;
  String? _usersError;
  final Map<String, bool> _following = {};
  final Set<String> _followBusy = {};
  List<String> _history = [];
  bool _historyExpanded = false;
  Timer? _suggestTimer;
  final Map<String, SearchSuggestions> _suggestions = {};

  @override
  void initState() {
    super.initState();
    _history = Prefs.instance.searchHistory;
    _tabs.addListener(_tabChanged);
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
    _results?.dispose();
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
    setState(() {});
    if (_tabs.index == 1 && _submitted != null && _users == null && !_usersLoading) {
      _loadUsers(_submitted!);
    }
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
      _startResults(query);
    });
    _results!.refresh();
    if (_tabs.index == 1) _loadUsers(query);
  }

  /// A fresh pager for [query] in the chosen [SearchSort]; the caller still has to refresh it.
  void _startResults(String query) {
    _results?.dispose();
    _results = PagingController<Status>(
      fetch: (cursor) => WeiboApi.instance.searchStatuses(query, cursor, sort: _sort),
      id: (status) => status.id,
    );
  }

  void _selectSort(SearchSort sort) {
    final query = _submitted;
    if (sort == _sort || query == null) return;
    Haptic.selection.play();
    setState(() {
      _sort = sort;
      _startResults(query);
    });
    _results!.refresh();
  }

  void _clearResults() {
    setState(() {
      _submitted = null;
      _input.clear();
      _results?.dispose();
      _results = null;
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
    final pager = _results;
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: Column(
      key: const ValueKey('results'),
      children: [
        ContentColumn(
          child: TabBar(
            controller: _tabs,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(height: 44, child: Text('微博')),
              Tab(height: 44, child: Text('用户')),
            ],
          ),
        ),
        if (_tabs.index == 0)
          ContentColumn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sort in SearchSort.values)
                    _SortChip(
                      label: sort.label,
                      selected: sort == _sort,
                      onTap: () => _selectSort(sort),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _tabs.index == 0
              ? (pager == null
                  ? const LoadingFooter()
                  : PagedStatusList(
                      pager: pager,
                      emptyText: '没有找到相关微博',
                      bottomInset: 18,
                      underAppBar: false,
                    ))
              : _usersTab(),
        ),
      ],
      ),
    );
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

/// 综合 / 实时 / 热门 above the results, shaped like the chips on the hot-search boards.
class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    return Material(
      color: selected ? chrome.fill(scheme, scheme.primaryContainer, 1) : chrome.fill(scheme, scheme.surfaceContainerHigh, 0.6),
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
