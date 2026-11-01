import 'models.dart';
import 'parse.dart';

enum TopicEventKind { started, post, boardOn, boardOff, peak, now }

/// One moment in a topic's story, from Weibo's own records or one of its posts.
class TopicEvent {
  final DateTime at;
  final TopicEventKind kind;
  final String title;
  final String? detail;
  final Status? status;

  const TopicEvent({required this.at, required this.kind, required this.title, this.detail, this.status});
}

/// Weibo has no public event timeline any more, so this one is put together from what it does
/// say: when the topic started and with which post, each run on a board, the busiest hour of
/// reading, and the posts that carried it — those by verified accounts, the earliest and the
/// most discussed. Oldest first, ending at [now].
List<TopicEvent> buildTopicTimeline({
  TopicInfo? info,
  HotSearch? entry,
  List<TopicTrendPoint>? trend,
  Status? first,
  List<Status> posts = const [],
  int maxPosts = 10,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final events = <TopicEvent>[];

  final started = first?.createdAt ?? info?.createdAt;
  if (started != null) {
    events.add(TopicEvent(
      at: started,
      kind: TopicEventKind.started,
      title: first != null ? '${first.author.screenName} 发起话题' : '话题创建',
      detail: first == null && info?.host != null ? '主持人 ${info!.host}' : null,
      status: first,
    ));
  }

  final boards = info?.boards ?? const <TopicBoardStint>[];
  for (final stint in boards) {
    final on = stint.onAt;
    if (on != null) {
      events.add(TopicEvent(
        at: on,
        kind: TopicEventKind.boardOn,
        title: '登上${stint.board}',
        detail: stint.bestRank == null ? null : '最高第${stint.bestRank}名',
      ));
    }
    final off = stint.offAt;
    if (off != null) {
      events.add(TopicEvent(
        at: off,
        kind: TopicEventKind.boardOff,
        title: '离开${stint.board}',
        detail: stint.minutes > 0 ? '在榜${durationText(stint.minutes)}' : null,
      ));
    }
  }
  final onboard = entry?.onboardAt;
  if (onboard != null && !boards.any((stint) => stint.onAt != null && stint.board == '热搜榜')) {
    events.add(TopicEvent(at: onboard, kind: TopicEventKind.boardOn, title: '登上${entry!.board.label}'));
  }

  final peak = _peakOf(trend, clock);
  if (peak != null) {
    events.add(TopicEvent(
      at: peak.$1,
      kind: TopicEventKind.peak,
      title: '阅读高峰',
      detail: '这一小时阅读 ${compactCount(peak.$2)}',
    ));
  }

  final seen = <String>{if (first != null) first.id};
  final pool = [
    for (final post in posts)
      if (seen.add(post.id)) post,
  ];
  if (pool.isNotEmpty) {
    int weight(Status post) => post.repostsCount + post.commentsCount + post.likesCount;
    final earliest = pool.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);
    final loudest = pool.reduce((a, b) => weight(a) >= weight(b) ? a : b);
    final picked = <String, String?>{
      if (first == null) earliest.id: '能找到的最早一条',
      loudest.id: '讨论最多 · 转评赞 ${compactCount(weight(loudest))}',
    };
    for (final post in pool) {
      if (picked.length >= maxPosts) break;
      if (post.author.verified) picked.putIfAbsent(post.id, () => null);
    }
    for (final post in pool) {
      final note = picked[post.id];
      if (!picked.containsKey(post.id)) continue;
      events.add(TopicEvent(
        at: post.createdAt,
        kind: TopicEventKind.post,
        title: '${post.author.screenName} 发布',
        detail: note,
        status: post,
      ));
    }
  }

  events.sort((a, b) => a.at.compareTo(b.at));
  if (events.isNotEmpty) {
    final figures = [
      if (entry != null) entry.rankText,
      if (info?.reads != null) '阅读 ${compactCount(info!.reads!)}',
      if (info?.discussions != null) '讨论 ${compactCount(info!.discussions!)}',
    ];
    events.add(TopicEvent(
      at: clock,
      kind: TopicEventKind.now,
      title: entry != null ? '仍在榜上' : '现在',
      detail: figures.isEmpty ? null : figures.join(' · '),
    ));
  }
  return events;
}

/// The busiest hour of [trend], whose points are the last 24 hours ending with the current one.
(DateTime, int)? _peakOf(List<TopicTrendPoint>? trend, DateTime now) {
  if (trend == null || trend.isEmpty) return null;
  var best = 0;
  for (var i = 1; i < trend.length; i++) {
    if (trend[i].value > trend[best].value) best = i;
  }
  if (trend[best].value <= 0) return null;
  final hour = DateTime(now.year, now.month, now.day, now.hour);
  return (hour.subtract(Duration(hours: trend.length - 1 - best)), trend[best].value);
}

String durationText(int minutes) {
  if (minutes < 60) return '$minutes分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours >= 24) return '${hours ~/ 24}天${hours % 24 > 0 ? '${hours % 24}小时' : ''}';
  return rest == 0 ? '$hours小时' : '$hours小时$rest分钟';
}
