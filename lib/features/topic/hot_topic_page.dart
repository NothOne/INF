import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/hot_search_store.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/parse.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/hot_search_row.dart';
import '../../core/widgets/paged_status_list.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/smart_image.dart';

/// A hashtag or a hot-search keyword: what the board and the topic head say about it, related
/// searches and accounts, then its posts by stream.
class HotTopicPage extends StatefulWidget {
  const HotTopicPage({super.key, required this.query, this.entry});

  /// `#话题#` for a hashtag, the bare words for a keyword.
  final String query;
  final HotSearch? entry;

  @override
  State<HotTopicPage> createState() => _HotTopicPageState();
}

class _HotTopicPageState extends State<HotTopicPage> with SingleTickerProviderStateMixin {
  static const _tabs = HotTopicTab.values;

  late final TabController _tabController = TabController(length: _tabs.length, vsync: this);
  final ScrollController _outer = ScrollController();
  late final Map<HotTopicTab, PagingController<Status>> _pagers = {
    for (final tab in _tabs)
      tab: PagingController<Status>(fetch: (cursor) => _fetch(tab, cursor), id: (status) => status.id),
  };
  final Set<HotTopicTab> _started = {};
  late HotSearch? _entry = widget.entry ?? HotSearchStore.instance.lookup(widget.query);
  TopicInfo? _head;
  TopicInfo? _detail;
  List<TopicTrendPoint>? _trend;
  SearchSuggestions? _related;

  TopicInfo? get _info => _detail?.merge(_head) ?? _head;

  bool get _isTopic => widget.query.startsWith('#') && widget.query.endsWith('#') && widget.query.length > 2;
  String get _name => widget.query.replaceAll('#', '').trim();
  String get _title => _isTopic ? '#$_name#' : _name;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_tabChanged);
    _start(_tabs.first);
    _loadRelated();
    _loadDetail();
    if (_entry == null) {
      HotSearchStore.instance.load().then((_) {
        final found = HotSearchStore.instance.lookup(widget.query);
        if (found != null && mounted) setState(() => _entry = found);
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_tabChanged);
    _tabController.dispose();
    _outer.dispose();
    for (final pager in _pagers.values) {
      pager.dispose();
    }
    super.dispose();
  }

  void _tabChanged() {
    if (_tabController.indexIsChanging) Haptic.selection.play();
    _start(_tabs[_tabController.index]);
  }

  void _start(HotTopicTab tab) {
    if (_started.add(tab)) _pagers[tab]!.refresh();
  }

  Future<PageResult<Status>> _fetch(HotTopicTab tab, String? cursor) async {
    final (page, info) = await WeiboApi.instance.hotTopicPage(widget.query, tab, cursor);
    if (info != null && mounted) setState(() => _head = info.merge(_head));
    return page;
  }

  /// Only hashtags have a topic card; a plain keyword is searched, not hosted.
  Future<void> _loadDetail() async {
    if (!_isTopic) return;
    final topic = '#$_name#';
    await Future.wait<void>([
      WeiboApi.instance
          .topicDetail(topic)
          .then((detail) {
            if (detail != null && mounted) setState(() => _detail = detail);
          })
          .catchError((_) {}),
      WeiboApi.instance
          .topicTrend(topic)
          .then((trend) {
            if (mounted) setState(() => _trend = trend);
          })
          .catchError((_) {}),
    ]);
  }

  Future<void> _loadRelated() async {
    try {
      final related = await WeiboApi.instance.searchSuggestions(_name);
      if (mounted) setState(() => _related = related);
    } catch (_) {}
  }

  Future<bool> _refresh() async {
    final tab = _tabs[_tabController.index];
    _loadDetail();
    final results = await Future.wait<bool>([
      _pagers[tab]!.refresh(),
      HotSearchStore.instance.load(force: true).then((ok) {
        final found = HotSearchStore.instance.lookup(widget.query);
        if (found != null && mounted) setState(() => _entry = found);
        return ok;
      }),
    ]);
    return results.first;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: AnimatedBuilder(
          animation: _outer,
          builder: (context, child) {
            final shown = _outer.hasClients && _outer.offset > 56;
            return AnimatedOpacity(opacity: shown ? 1 : 0, duration: InfMotion.feedback, child: child);
          },
          child: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            onPressed: () => openSearch(context, query: _name),
            tooltip: '全站搜索',
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: InfRefreshIndicator(
        onRefresh: _refresh,
        child: NestedScrollView(
          controller: _outer,
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: _TopicHead(
                title: _title,
                name: _name,
                isTopic: _isTopic,
                entry: _entry,
                info: _info,
                trend: _trend,
                related: _related,
              ),
            ),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _TabStrip(
                  color: scheme.surface,
                  divider: scheme.outlineVariant.withValues(alpha: 0.5),
                  tabBar: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerHeight: 0,
                    tabs: [for (final tab in _tabs) Tab(height: 44, text: tab.label)],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              for (final tab in _tabs)
                KeepAlivePage(
                  child: Builder(
                    builder: (context) => PagedStatusList(
                      key: PageStorageKey<String>('topic-${tab.name}'),
                      pager: _pagers[tab]!,
                      nested: true,
                      underAppBar: false,
                      refreshable: false,
                      emptyText: tab == HotTopicTab.video ? '还没有相关视频' : '还没有相关微博',
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

class _TabStrip extends SliverPersistentHeaderDelegate {
  _TabStrip({required this.tabBar, required this.color, required this.divider});

  final TabBar tabBar;
  final Color color;
  final Color divider;

  @override
  double get minExtent => 45;

  @override
  double get maxExtent => 45;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border(bottom: BorderSide(color: divider, width: 0.6)),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabStrip oldDelegate) =>
      oldDelegate.tabBar != tabBar || oldDelegate.color != color || oldDelegate.divider != divider;
}

class _TopicHead extends StatelessWidget {
  const _TopicHead({
    required this.title,
    required this.name,
    required this.isTopic,
    required this.entry,
    required this.info,
    required this.trend,
    required this.related,
  });

  final String title;
  final String name;
  final bool isTopic;
  final HotSearch? entry;
  final TopicInfo? info;
  final List<TopicTrendPoint>? trend;
  final SearchSuggestions? related;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final entry = this.entry;
    final info = this.info;
    final cover = info?.coverUrl;
    final heat = _HeatData(entry: entry, info: info, trend: trend);

    final words = [
      for (final word in related?.words ?? const <SearchSuggestion>[])
        if (word.word.replaceAll('#', '') != name) word,
    ].take(10).toList();
    final users = related?.users.take(10).toList() ?? const <User>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: AnimatedSize(
        duration: InfMotion.feedback,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (cover != null && cover.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SmartImage(url: cover, width: 52, height: 52, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (entry != null)
                            _Pill(
                              icon: Icons.local_fire_department_rounded,
                              text: entry.rankText,
                              color: rankColor(context, entry.pinned ? null : (entry.rank ?? 1)),
                            ),
                          if (entry != null) HotLabel(entry: entry, size: 18),
                          _Pill(
                            icon: isTopic ? Icons.tag_rounded : Icons.manage_search_rounded,
                            text: isTopic ? '话题' : '关键词',
                            color: scheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (info?.lead != null && info!.lead!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _LeadText(text: info.lead!),
            ],
            if (info?.host != null || info?.note != null) ...[const SizedBox(height: 4), _HostLine(info: info!)],
            if (heat.isNotEmpty) ...[const SizedBox(height: 8), _HeatBar(heat: heat, title: title)],
            if (words.isNotEmpty) ...[const SizedBox(height: 10), _RelatedWords(words: words)],
            if (users.isNotEmpty) ...[const SizedBox(height: 10), _UserStrip(users: users)],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: _compactButton,
                    onPressed: () => openCompose(context, initialText: isTopic ? '$title ' : '$name '),
                    icon: const Icon(Icons.edit_rounded, size: 17),
                    label: Text(isTopic ? '参与讨论' : '发微博'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: _compactButton,
                    onPressed: () => openSearch(context, query: name),
                    icon: const Icon(Icons.search_rounded, size: 17),
                    label: const Text('全站搜索'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final _compactButton = ButtonStyle(
  visualDensity: VisualDensity.compact,
  minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
);

/// Everything about how hot a topic is; the head shows one line of it, the sheet the rest.
class _HeatData {
  _HeatData({required this.entry, required this.info, required List<TopicTrendPoint>? trend})
    : trend = trend != null && trend.any((point) => point.value > 0) ? trend : null;

  final HotSearch? entry;
  final TopicInfo? info;
  final List<TopicTrendPoint>? trend;

  late final List<(String, String)> stats = [
    if (entry?.heatValue != null && entry!.heatValue! > 0) (compactCount(entry!.heatValue!), '热度'),
    if (info?.reads != null) (compactCount(info!.reads!), '阅读'),
    if (info?.discussions != null) (compactCount(info!.discussions!), '讨论'),
    if (info?.originals != null) (compactCount(info!.originals!), '原创'),
    if (info?.interactions != null) (compactCount(info!.interactions!), '互动'),
  ];

  String? get rawStats => stats.isEmpty ? info?.stats : null;
  String? get category => entry?.category ?? info?.category;

  bool get isNotEmpty =>
      stats.isNotEmpty ||
      rawStats != null ||
      info?.highlight != null ||
      trend != null ||
      (info?.boards.isNotEmpty ?? false) ||
      (info?.contributors.isNotEmpty ?? false) ||
      (info?.media.isNotEmpty ?? false);
}

/// One line of figures with the trend as a sparkline; tap for the whole picture.
class _HeatBar extends StatelessWidget {
  const _HeatBar({required this.heat, required this.title});

  final _HeatData heat;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final trend = heat.trend;
    final summary = heat.stats.isNotEmpty
        ? heat.stats.take(trend == null ? 3 : 2).map((stat) => '${stat.$2} ${stat.$1}').join('  ·  ')
        : heat.rawStats ?? heat.info?.highlight ?? '热点数据';
    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Haptic.selection.play();
          _showHeatSheet(context, heat: heat, title: title);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
          child: Row(
            children: [
              Icon(Icons.insights_rounded, size: 17, color: rankColor(context, 2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 54,
                  height: 18,
                  child: CustomPaint(
                    painter: _TrendPainter(points: trend, color: scheme.primary),
                  ),
                ),
              ],
              Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showHeatSheet(BuildContext context, {required _HeatData heat, required String title}) {
  return showActionSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: _HeatSheet(heat: heat, title: title),
    ),
  );
}

class _HeatSheet extends StatelessWidget {
  const _HeatSheet({required this.heat, required this.title});

  final _HeatData heat;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final entry = heat.entry;
    final info = heat.info;
    final trend = heat.trend;
    final category = heat.category;
    final meta = <Widget>[
      if (category != null && category.isNotEmpty)
        _Pill(icon: Icons.category_outlined, text: category, color: scheme.tertiary),
      if (entry?.onboardAt != null)
        _Pill(
          icon: Icons.schedule_rounded,
          text: '${relativeTime(entry!.onboardAt!)}上榜',
          color: scheme.onSurfaceVariant,
        ),
      if (info?.createdAt != null)
        _Pill(icon: Icons.event_rounded, text: '创建于${relativeTime(info!.createdAt!)}', color: scheme.onSurfaceVariant),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('热点数据', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (meta.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 6, runSpacing: 6, children: meta)],
          if (info?.highlight != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.emoji_events_rounded, size: 16, color: rankColor(context, 2)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    info!.highlight!,
                    style: text.bodySmall?.copyWith(color: rankColor(context, 2), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          if (heat.stats.isNotEmpty) ...[const SizedBox(height: 12), _StatsRow(stats: heat.stats.take(4).toList())],
          if (heat.rawStats != null) ...[
            const SizedBox(height: 12),
            Text(heat.rawStats!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (trend != null)
            _Section(
              title: '24小时阅读趋势',
              trailing: '峰值 ${compactCount(trend.map((p) => p.value).reduce((a, b) => a > b ? a : b))}/小时',
              child: _TrendChart(points: trend),
            ),
          if (info != null && info.boards.isNotEmpty)
            _Section(
              title: '上榜记录',
              child: Column(children: [for (final stint in info.boards) _BoardLine(stint: stint)]),
            ),
          if (info != null && info.contributors.isNotEmpty)
            _Section(
              title: '话题贡献者',
              child: _UserStrip(users: info.contributors),
            ),
          if (info != null && info.media.isNotEmpty)
            _Section(
              title: info.note?.replaceFirst('发布', '') ?? '参与媒体',
              child: _UserStrip(users: info.media),
            ),
        ],
      ),
    );
  }
}

class _RelatedWords extends StatelessWidget {
  const _RelatedWords({required this.words});

  final List<SearchSuggestion> words;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: words.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Center(
              child: Text(
                '相关',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
              ),
            );
          }
          final word = words[index - 1];
          return ActionChip(
            avatar: word.hot ? const Icon(Icons.trending_up_rounded, size: 15) : null,
            label: Text(word.word, maxLines: 1, overflow: TextOverflow.ellipsis),
            visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelStyle: Theme.of(context).textTheme.labelMedium,
            onPressed: () => openHotTopic(context, query: word.word),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _HostLine extends StatelessWidget {
  const _HostLine({required this.info});

  final TopicInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    final hostId = info.hostId;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: hostId == null ? null : () => openUser(context, hostId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.record_voice_over_outlined, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            if (info.host != null) ...[
              Text('主持人 ', style: style?.copyWith(color: scheme.onSurfaceVariant)),
              Flexible(
                child: Text(
                  info.host!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            if (info.note != null)
              Flexible(
                child: Text(
                  '${info.host != null ? '  ·  ' : ''}${info.note}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoardLine extends StatelessWidget {
  const _BoardLine({required this.stint});

  final TopicBoardStint stint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hours = stint.minutes ~/ 60;
    final minutes = stint.minutes % 60;
    final duration = hours > 0 ? '$hours小时${minutes > 0 ? '$minutes分钟' : ''}' : '$minutes分钟';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.leaderboard_rounded, size: 16, color: rankColor(context, stint.bestRank)),
          const SizedBox(width: 8),
          Text(stint.board, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          if (stint.bestRank != null)
            Text('最高第${stint.bestRank}位', style: text.bodySmall?.copyWith(color: rankColor(context, stint.bestRank))),
          const Spacer(),
          Text('在榜 $duration', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _UserStrip extends StatelessWidget {
  const _UserStrip({required this.users});

  final List<User> users;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: users.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final user = users[index];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => openUser(context, user.id),
            child: SizedBox(
              width: 58,
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  Avatar(url: user.avatarUrl, size: 40, verified: user.verified),
                  const SizedBox(height: 4),
                  Text(
                    user.screenName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Hourly reads as bars, the last hour in full colour; the axis carries the first, middle and
/// last hour.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<TopicTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      decoration: BoxDecoration(
        color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 76,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendPainter(points: points, color: scheme.primary),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(points.first.label, style: label),
              const Spacer(),
              Text(points[points.length ~/ 2].label, style: label),
              const Spacer(),
              Text(points.last.label, style: label),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.color});

  final List<TopicTrendPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final peak = points.fold<int>(0, (max, point) => point.value > max ? point.value : max);
    if (peak <= 0) return;
    final slot = size.width / points.length;
    final bar = (slot * 0.62).clamp(2.0, 14.0);
    for (var i = 0; i < points.length; i++) {
      final value = points[i].value;
      final height = value <= 0 ? 2.0 : (value / peak * size.height).clamp(3.0, size.height);
      final left = i * slot + (slot - bar) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - height, bar, height),
        Radius.circular(bar / 2.5),
      );
      final last = i == points.length - 1;
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: value <= 0 ? 0.15 : (last ? 1 : 0.45)));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => oldDelegate.points != points || oldDelegate.color != color;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) Container(width: 0.6, height: 26, color: scheme.outlineVariant),
            Expanded(
              child: Column(
                children: [
                  Text(stats[i].$1, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(stats[i].$2, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 导语 in two lines behind a quote bar; a tap opens the rest in place.
class _LeadText extends StatefulWidget {
  const _LeadText({required this.text});

  final String text;

  @override
  State<_LeadText> createState() => _LeadTextState();
}

class _LeadTextState extends State<_LeadText> {
  static const _lines = 2;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5, color: scheme.onSurfaceVariant);
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = (TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth - 12)).didExceedMaxLines;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: overflows ? () => setState(() => _expanded = !_expanded) : null,
          child: Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 2)),
            ),
            child: AnimatedSize(
              duration: InfMotion.feedback,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Text(
                widget.text,
                maxLines: _expanded ? null : _lines,
                overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        );
      },
    );
  }
}
