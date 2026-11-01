import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/topic_timeline.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/hot_search_row.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/smart_image.dart';

/// How a topic unfolded, oldest first: Weibo's records about it first, then the posts that
/// carried it as they arrive.
class TopicTimelinePage extends StatefulWidget {
  const TopicTimelinePage({
    super.key,
    required this.query,
    required this.title,
    this.info,
    this.trend,
    this.entry,
  });

  final String query;
  final String title;
  final TopicInfo? info;
  final List<TopicTrendPoint>? trend;
  final HotSearch? entry;

  @override
  State<TopicTimelinePage> createState() => _TopicTimelinePageState();
}

class _TopicTimelinePageState extends State<TopicTimelinePage> {
  late TopicInfo? _info = widget.info;
  late List<TopicTrendPoint>? _trend = widget.trend;
  Status? _first;
  List<Status> _posts = const [];
  bool _loading = true;

  bool get _isTopic => widget.query.startsWith('#') && widget.query.endsWith('#') && widget.query.length > 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = WeiboApi.instance;
    // A hot-search keyword usually has a hashtag of the same words, which carries the records.
    final topic = _isTopic ? widget.query : '#${widget.query.trim()}#';
    await Future.wait<void>([
      api.topicDetail(topic).then((info) {
        if (info != null && mounted) setState(() => _info = info.merge(_info));
      }).catchError((_) {}),
      api.topicTrend(topic).then((trend) {
        if (trend.isNotEmpty && mounted) setState(() => _trend = trend);
      }).catchError((_) {}),
    ]);
    final firstId = _info?.firstStatusId;
    final pages = <Future<List<Status>>>[
      for (final (tab, cursor) in [(HotTopicTab.hot, null), (HotTopicTab.hot, '2'), (HotTopicTab.realtime, null)])
        api
            .hotTopicPage(widget.query, tab, cursor)
            .then((result) => result.$1.items)
            .catchError((_) => const <Status>[]),
    ];
    final first = firstId == null ? Future<Status?>.value() : api.status(firstId).catchError((_) => null);
    final found = await Future.wait(pages);
    final firstStatus = await first;
    if (!mounted) return;
    setState(() {
      _first = firstStatus;
      _posts = [for (final page in found) ...page];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final events = buildTopicTimeline(
      info: _info,
      entry: widget.entry,
      trend: _trend,
      first: _first,
      posts: _posts,
    );
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('事件时间线'),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: InfRefreshIndicator(
        onRefresh: _load,
        child: events.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 160),
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : const EmptyHint(text: '这个话题还整理不出时间线', icon: Icons.timeline_rounded),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  12 + contentGutter(context),
                  8,
                  16 + contentGutter(context),
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: events.length + 1,
                itemBuilder: (context, index) {
                  if (index == events.length) return _Footnote(loading: _loading);
                  final event = events[index];
                  final previous = index == 0 ? null : events[index - 1];
                  final newDay = previous == null || !_sameDay(previous.at, event.at);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (newDay) _DayHeader(day: event.at, first: index == 0),
                      _EventRow(event: event, last: index == events.length - 1),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String _two(int n) => n.toString().padLeft(2, '0');

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.first});

  final DateTime day;
  final bool first;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final local = day.toLocal();
    final now = DateTime.now();
    final label = _sameDay(local, now)
        ? '今天'
        : _sameDay(local, now.subtract(const Duration(days: 1)))
            ? '昨天'
            : local.year == now.year
                ? '${local.month}月${local.day}日'
                : '${local.year}年${local.month}月${local.day}日';
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 4 : 10, 0, 10),
      child: Text(
        '$label  周${_weekdays[local.weekday - 1]}',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.last});

  final TopicEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final local = event.at.toLocal();
    final (icon, color) = switch (event.kind) {
      TopicEventKind.started => (Icons.flag_rounded, scheme.primary),
      TopicEventKind.post => (Icons.chat_bubble_outline_rounded, scheme.onSurfaceVariant),
      TopicEventKind.boardOn => (Icons.trending_up_rounded, rankColor(context, 1)),
      TopicEventKind.boardOff => (Icons.trending_down_rounded, scheme.outline),
      TopicEventKind.peak => (Icons.insights_rounded, rankColor(context, 2)),
      TopicEventKind.now => (Icons.radio_button_checked_rounded, scheme.primary),
    };
    final status = event.status;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                event.kind == TopicEventKind.now ? '现在' : '${_two(local.hour)}:${_two(local.minute)}',
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: InfChrome.of(context).fill(scheme, color, 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 13, color: color),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: last ? 4 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (event.detail != null) ...[
                    const SizedBox(height: 2),
                    Text(event.detail!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                  if (status != null) ...[const SizedBox(height: 8), _PostPreview(status: status)],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A post on the timeline: enough to recognise it, the rest a tap away.
class _PostPreview extends StatelessWidget {
  const _PostPreview({required this.status});

  final Status status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final picture = status.media.isEmpty ? null : status.media.first.previewUrl;
    final body = status.text.trim().isEmpty && status.repostOf != null ? status.repostOf!.text : status.text;
    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openStatus(context, statusId: status.id, seed: status),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Avatar(url: status.author.avatarUrl, size: 20, verified: status.author.verified),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            status.author.screenName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(body.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                  ],
                ),
              ),
              if (picture != null && picture.isNotEmpty) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SmartImage(url: picture, width: 56, height: 56, fit: BoxFit.cover),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
      child: loading
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('正在整理相关微博', style: style),
              ],
            )
          : Text('根据话题记录、榜单数据和相关微博整理', textAlign: TextAlign.center, style: style),
    );
  }
}
