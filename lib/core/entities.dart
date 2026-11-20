import 'models.dart';
import 'session.dart';

/// The one copy of each thing the app has seen, so a list and a page opened from it are showing
/// the same object rather than two answers that happen to agree.
///
/// This exists because the delta layer was not enough. [StatusStore] remembers *what this device
/// changed* — a like, a comment it posted — and overlays that on whatever copy a row holds. That
/// keeps the numbers equal, but it cannot make a copy *better*: the feed's copy of a long post
/// stays truncated after the detail page has fetched the whole text, and a list keeps the counts
/// it was parsed with even though the same post was just fetched fresh. Two answers, one screen.
///
/// So the reading direction flips. A parser's answer goes in here through [put], which merges
/// rather than replaces; a row reads the merged copy back out. The delta layer stays on top of it,
/// unchanged, because "this device liked it" is still not something an answer can say.
///
/// **Scope: statuses only.** Users and comments get their own stores when they have the same
/// problem; adding them before there is a case to check against would be guessing at the merge
/// rules. `NEXT.md` keeps the staging.
class Entities {
  Entities._() {
    Session.instance.registerAccountReset(clear);
  }
  static final Entities instance = Entities._();

  /// Recent posts, oldest out first. A few kilobytes each: a session's worth of scrolling, not the
  /// whole timeline. Large enough that going back a screen never re-fetches, small enough that the
  /// map cannot grow without limit the way a plain one would.
  static const int _kept = 200;

  final Map<String, Status> _statuses = {};

  /// The post as the app best knows it, or null if it has never been seen.
  Status? status(String id) => _statuses[id];

  /// Files [incoming] and answers with the copy that is now current.
  ///
  /// Merging, not replacing: an answer that carries less than what is already stored must not take
  /// anything away. Every answer here comes from a full response, so in practice the incoming one
  /// wins — except where it is visibly poorer, which is what the checks below are for.
  Status put(Status incoming) {
    final existing = _statuses.remove(incoming.id);
    final merged = existing == null ? incoming : _merge(existing, incoming);
    _statuses[incoming.id] = merged;
    if (_statuses.length > _kept) _statuses.remove(_statuses.keys.first);
    return merged;
  }

  /// Files [incoming] only when this id has never been seen, so a list row mounting an older copy
  /// cannot overwrite fresher counts that another screen already stored.
  Status putIfAbsent(Status incoming) => _statuses[incoming.id] ?? put(incoming);

  /// Files a post without answering with it, for callers that only have something to hand over.
  void putAll(Iterable<Status> statuses) {
    for (final status in statuses) {
      put(status);
    }
  }

  void clear() => _statuses.clear();

  /// How many posts are being held, for tests that check the bound is real.
  int get length => _statuses.length;

  /// The cap, for tests that check it is the number they think it is.
  int get kept => _kept;

  /// [existing] is what was stored, [incoming] what just arrived. Content that the new answer
  /// leaves out is kept; content it carries replaces what was there, except a shorter text, which
  /// is an answer that still has the truncation the longer one had already lifted.
  Status _merge(Status existing, Status incoming) {
    final text = incoming.text.trim().isEmpty
        ? existing.text
        : (incoming.text.length < existing.text.length ? existing.text : incoming.text);
    final author = incoming.author.screenName.isEmpty ? existing.author : incoming.author;
    final media = _mergeMedia(existing.media, incoming.media);
    final links = _mergeLinks(existing.links, incoming.links);
    final source = incoming.source ?? existing.source;
    final region = incoming.region ?? existing.region;
    final place = incoming.place ?? existing.place;
    final article = incoming.article ?? existing.article;
    final card = incoming.card ?? existing.card;
    final audio = incoming.audio ?? existing.audio;
    final repostOf = (existing.repostOf != null &&
            incoming.repostOf != null &&
            existing.repostOf!.id == incoming.repostOf!.id)
        ? _merge(existing.repostOf!, incoming.repostOf!)
        : (incoming.repostOf ?? existing.repostOf);
    final topics = incoming.topics.isEmpty ? existing.topics : incoming.topics;

    final unchanged = text == existing.text &&
        _sameAuthor(author, existing.author) &&
        _sameMedia(media, existing.media) &&
        _sameLinks(links, existing.links) &&
        source == existing.source &&
        region == existing.region &&
        place?.name == existing.place?.name &&
        article?.url == existing.article?.url &&
        card?.url == existing.card?.url &&
        audio?.url == existing.audio?.url &&
        identical(repostOf, existing.repostOf) &&
        _sameTopics(topics, existing.topics) &&
        incoming.repostsCount == existing.repostsCount &&
        incoming.commentsCount == existing.commentsCount &&
        incoming.likesCount == existing.likesCount &&
        incoming.liked == existing.liked &&
        incoming.favorited == existing.favorited &&
        (incoming.isLongText || existing.isLongText) == existing.isLongText &&
        (incoming.pinned || existing.pinned) == existing.pinned;
    // Same answer as before: hand back the stored object, so a caller can tell "nothing new" from
    // "new copy" by identity and skip a rebuild.
    if (unchanged) return existing;

    return Status(
      id: incoming.id,
      author: author,
      text: text,
      createdAt: incoming.createdAt,
      source: source,
      media: media,
      repostOf: repostOf,
      repostsCount: incoming.repostsCount,
      commentsCount: incoming.commentsCount,
      likesCount: incoming.likesCount,
      liked: incoming.liked,
      favorited: incoming.favorited,
      topics: topics,
      place: place,
      article: article,
      card: card,
      audio: audio,
      links: links,
      // While either copy is still truncated, the post is still a long one: the flag is what makes
      // the card offer 全文, and losing it would hide the way to the text that is stored.
      isLongText: incoming.isLongText || existing.isLongText,
      region: region,
      pinned: incoming.pinned || existing.pinned,
    );
  }

  static List<Media> _mergeMedia(List<Media> existing, List<Media> incoming) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) return incoming;
    // A feed refresh from m.weibo.cn drops mixed-media videos and caps pics; never regress a
    // richer media list that the detail page already resolved from weibo.com.
    if (incoming.length < existing.length) return existing;
    if (incoming.length == existing.length) {
      final existingVideos = existing.where((m) => m.kind == MediaKind.video).length;
      final incomingVideos = incoming.where((m) => m.kind == MediaKind.video).length;
      if (incomingVideos < existingVideos) return existing;
    }
    return incoming;
  }

  static Map<String, WeiboLink> _mergeLinks(Map<String, WeiboLink> existing, Map<String, WeiboLink> incoming) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) return incoming;
    final merged = Map<String, WeiboLink>.from(existing);
    for (final entry in incoming.entries) {
      final prev = merged[entry.key];
      if (prev == null) {
        merged[entry.key] = entry.value;
      } else {
        final images = entry.value.images.length >= prev.images.length ? entry.value.images : prev.images;
        final label = (images.length > 1 && (entry.value.label.isEmpty || entry.value.label == '查看图片'))
            ? (prev.label.isNotEmpty ? prev.label : '查看${images.length}张图片')
            : (entry.value.label.isNotEmpty ? entry.value.label : prev.label);
        merged[entry.key] = WeiboLink(url: entry.key, label: label, kind: entry.value.kind, images: images);
      }
    }
    return merged;
  }

  static bool _sameAuthor(User a, User b) =>
      identical(a, b) || (a.id == b.id && a.screenName == b.screenName && a.avatarUrl == b.avatarUrl);

  static bool _sameMedia(List<Media> a, List<Media> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].kind != b[i].kind || a[i].url != b[i].url) return false;
    }
    return true;
  }

  static bool _sameLinks(Map<String, WeiboLink> a, Map<String, WeiboLink> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null ||
          other.label != entry.value.label ||
          other.kind != entry.value.kind ||
          !_sameMedia(other.images, entry.value.images)) {
        return false;
      }
    }
    return true;
  }

  static bool _sameTopics(List<Topic> a, List<Topic> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name) return false;
    }
    return true;
  }
}
