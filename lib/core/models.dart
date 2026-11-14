import 'dart:math' as math;

/// Every model the UI needs. The shapes mirror the Compose app's core/model package, so the
/// parsing rules in parse.dart can stay a direct port of the proven Kotlin mappers.
class User {
  final String id;
  final String screenName;
  final String? avatarUrl;
  final String description;
  final bool verified;
  final int followersCount;
  final int followingCount;
  final int statusesCount;
  final bool following;

  const User({
    required this.id,
    required this.screenName,
    this.avatarUrl,
    this.description = '',
    this.verified = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.statusesCount = 0,
    this.following = false,
  });

  User copyWith({
    String? screenName,
    String? avatarUrl,
    bool? verified,
    int? followersCount,
    int? followingCount,
    int? statusesCount,
    bool? following,
  }) =>
      User(
        id: id,
        screenName: screenName ?? this.screenName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        description: description,
        verified: verified ?? this.verified,
        followersCount: followersCount ?? this.followersCount,
        followingCount: followingCount ?? this.followingCount,
        statusesCount: statusesCount ?? this.statusesCount,
        following: following ?? this.following,
      );

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: (json['id'] ?? '').toString(),
        screenName: json['screen_name'] as String? ?? '',
        avatarUrl: (json['avatar_url'] ?? json['avatar_hd'] ?? json['profile_image_url']) as String?,
        description: json['description'] as String? ?? '',
        verified: json['verified'] == true,
        followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
        followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
        statusesCount: (json['statuses_count'] as num?)?.toInt() ?? 0,
        following: json['following'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'screen_name': screenName,
        'avatar_url': avatarUrl,
        'description': description,
        'verified': verified,
        'followers_count': followersCount,
        'following_count': followingCount,
        'statuses_count': statusesCount,
        'following': following,
      };
}

enum MediaKind { image, video }

class Media {
  final MediaKind kind;
  final String url;
  final String previewUrl;
  final int width;
  final int height;
  final int durationMs;

  /// Weibo live-photo motion clip (pic_video / live photo MOV), when the API
  /// exposes one. Null for ordinary still images.
  final String? liveUrl;

  const Media.image(
    this.url, {
    String? previewUrl,
    this.width = 0,
    this.height = 0,
    this.liveUrl,
  })  : kind = MediaKind.image,
        previewUrl = previewUrl ?? url,
        durationMs = 0;

  const Media.video(
    this.url, {
    this.previewUrl = '',
    this.durationMs = 0,
  })  : kind = MediaKind.video,
        width = 0,
        height = 0,
        liveUrl = null;

  bool get isLong => kind == MediaKind.image && width > 0 && height > width * 3;

  bool get isLive => liveUrl != null && liveUrl!.isNotEmpty;
}

class Article {
  final String url;
  final String title;
  final String? summary;
  const Article({required this.url, this.title = '', this.summary});
}

class Topic {
  final String name;
  const Topic(this.name);
}

class Place {
  final String name;

  /// Weibo's page for the place.
  final String? url;
  final String? address;

  /// What Weibo says about it, e.g. 198人来过 1084条微博.
  final String? summary;
  final String? picUrl;
  const Place(this.name, {this.url, this.address, this.summary, this.picUrl});
}

/// Sound a post carries: a voice post's recording (`blog_audio`) or a podcast card.
class AudioClip {
  /// m.weibo.cn's copy of a voice post has the address without its signature, which the CDN
  /// refuses; see [signed] and [WeiboApi.audioUrl].
  final String url;
  final String title;
  final String? author;
  final String? coverUrl;
  final int durationMs;

  /// What Weibo heard in a voice post.
  final String? transcript;
  final bool voice;

  const AudioClip({
    required this.url,
    this.title = '',
    this.author,
    this.coverUrl,
    this.durationMs = 0,
    this.transcript,
    this.voice = false,
  });

  /// False also when m.weibo.cn gave no address at all, only the `[语音…]` line.
  bool get signed => url.isNotEmpty && (!url.contains('weibocdn.com') || url.contains('ssig='));
}

/// What a link in a post points at, as far as its address and Weibo's little icon tell.
enum LinkKind { web, video, audio, article, place, superTopic, vote, lottery, group }

/// A link as the post shows it: the address, and the words and kind Weibo draws in its place.
class WeiboLink {
  final String url;
  final String label;
  final LinkKind kind;
  const WeiboLink({required this.url, this.label = '', this.kind = LinkKind.web});
}

/// The card under a post for anything that is not a picture, a video or an article: a vote, a web
/// page, a group, a Q&A and whatever Weibo adds next.
class LinkCard {
  /// Empty when the feed left it out, as m.weibo.cn does for some banners; see [WeiboApi.cardUrl].
  final String url;
  final String title;
  final String? summary;
  final String? imageUrl;
  final String typeLabel;
  final LinkKind kind;

  /// A 16:9 banner (a birthday, a medal) drawn as [imageUrl] over this picture, instead of a row.
  final String? backgroundUrl;
  final bool banner;

  const LinkCard({
    required this.url,
    required this.title,
    this.summary,
    this.imageUrl,
    this.typeLabel = '',
    this.kind = LinkKind.web,
    this.backgroundUrl,
    this.banner = false,
  });
}

class Status {
  final String id;
  final User author;
  final String text;
  final DateTime createdAt;
  final String? source;
  final List<Media> media;
  final Status? repostOf;
  final int repostsCount;
  final int commentsCount;
  final int likesCount;
  final bool liked;
  final bool favorited;
  final List<Topic> topics;
  final Place? place;
  final Article? article;
  final LinkCard? card;
  final AudioClip? audio;

  /// The links in [text], by address.
  final Map<String, WeiboLink> links;
  final bool isLongText;
  final String? region;
  final bool pinned;

  const Status({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.source,
    this.media = const [],
    this.repostOf,
    this.repostsCount = 0,
    this.commentsCount = 0,
    this.likesCount = 0,
    this.liked = false,
    this.favorited = false,
    this.topics = const [],
    this.place,
    this.article,
    this.card,
    this.audio,
    this.links = const {},
    this.isLongText = false,
    this.region,
    this.pinned = false,
  });

  /// The pictures of the post, or of the post it reposts when it has none of its own.
  List<Media> get images {
    final own = media.where((item) => item.kind == MediaKind.image).toList();
    if (own.isNotEmpty || repostOf == null) return own;
    return repostOf!.media.where((item) => item.kind == MediaKind.image).toList();
  }

  Status copyWith({
    String? text,
    bool? liked,
    bool? favorited,
    int? likesCount,
    int? repostsCount,
    int? commentsCount,
    bool? isLongText,
    String? source,
    Map<String, WeiboLink>? links,
  }) =>
      Status(
        id: id,
        author: author,
        text: text ?? this.text,
        createdAt: createdAt,
        source: source ?? this.source,
        media: media,
        repostOf: repostOf,
        repostsCount: repostsCount ?? this.repostsCount,
        commentsCount: commentsCount ?? this.commentsCount,
        likesCount: likesCount ?? this.likesCount,
        liked: liked ?? this.liked,
        favorited: favorited ?? this.favorited,
        topics: topics,
        place: place,
        article: article,
        card: card,
        audio: audio,
        links: links ?? this.links,
        isLongText: isLongText ?? this.isLongText,
        region: region,
        pinned: pinned,
      );
}

class Comment {
  final String id;
  final String statusId;
  final User author;
  final String text;
  final DateTime createdAt;
  final int likesCount;
  final bool liked;
  final String? region;
  final User? replyTo;
  final List<Comment> replies;
  final int repliesCount;
  final List<Media> images;

  const Comment({
    required this.id,
    required this.statusId,
    required this.author,
    required this.text,
    required this.createdAt,
    this.likesCount = 0,
    this.liked = false,
    this.region,
    this.replyTo,
    this.replies = const [],
    this.repliesCount = 0,
    this.images = const [],
  });

  Comment copyWith({bool? liked, int? likesCount, int? repliesCount}) => Comment(
        id: id,
        statusId: statusId,
        author: author,
        text: text,
        createdAt: createdAt,
        likesCount: likesCount ?? this.likesCount,
        liked: liked ?? this.liked,
        region: region,
        replyTo: replyTo,
        replies: replies,
        repliesCount: repliesCount ?? this.repliesCount,
        images: images,
      );
}

enum NotificationKind {
  mentionInStatus('@微博', '还没有微博提到你'),
  mentionInComment('@评论', '还没有评论提到你'),
  comment('评论', '还没有收到评论'),
  like('赞', '还没有收到赞');

  final String label;
  final String emptyText;
  const NotificationKind(this.label, this.emptyText);
}

class NotificationItem {
  final String id;
  final NotificationKind kind;
  final User user;
  final String text;
  final DateTime createdAt;
  final String? statusId;
  final String? commentId;
  final String? targetText;
  final String? targetImage;

  const NotificationItem({
    required this.id,
    required this.kind,
    required this.user,
    required this.text,
    required this.createdAt,
    this.statusId,
    this.commentId,
    this.targetText,
    this.targetImage,
  });
}

class Conversation {
  final User user;
  final String lastText;
  final DateTime updatedAt;
  final int unread;
  final String? groupId;

  const Conversation({
    required this.user,
    required this.lastText,
    required this.updatedAt,
    this.unread = 0,
    this.groupId,
  });

  bool get isGroup => groupId != null;
}

class DirectMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final String? senderName;
  final String? senderAvatar;
  final int mediaType;

  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.senderName,
    this.senderAvatar,
    this.mediaType = 0,
  });

  String get displayText => mediaType == 1 ? (text.isEmpty ? '[图片]' : text) : text;
}

class ChatTarget {
  final String id;
  final bool isGroup;
  const ChatTarget(this.id, this.isGroup);
}

class UnreadCounts {
  final int mentionsInStatuses;
  final int mentionsInComments;
  final int comments;
  final int likes;
  final int messages;

  const UnreadCounts({
    this.mentionsInStatuses = 0,
    this.mentionsInComments = 0,
    this.comments = 0,
    this.likes = 0,
    this.messages = 0,
  });

  int get notifications => mentionsInStatuses + mentionsInComments + comments + likes;

  int of(NotificationKind kind) => switch (kind) {
        NotificationKind.mentionInStatus => mentionsInStatuses,
        NotificationKind.mentionInComment => mentionsInComments,
        NotificationKind.comment => comments,
        NotificationKind.like => likes,
      };
}

class HotSearch {
  final String word;
  final String query;
  final String? heat;
  final String? iconUrl;
  final bool pinned;

  /// Position on the board, 1-based. Null for pinned entries.
  final int? rank;

  /// The badge Weibo puts after the word: 新 热 沸 爆 荐 …
  final String? label;
  final int? labelColor;
  final String? category;
  final int? heatValue;
  final DateTime? onboardAt;
  final HotBoard board;

  const HotSearch({
    required this.word,
    required this.query,
    this.heat,
    this.iconUrl,
    this.pinned = false,
    this.rank,
    this.label,
    this.labelColor,
    this.category,
    this.heatValue,
    this.onboardAt,
    this.board = HotBoard.realtime,
  });

  /// 热搜第3, 文娱榜第3 …
  String get rankText {
    final name = board == HotBoard.realtime ? '热搜' : '${board.label}榜';
    if (pinned) return '$name置顶';
    return rank == null ? name : '$name第$rank';
  }

  /// `#话题#` entries open as a topic; the rest are plain keywords.
  bool get isTopic => query.length > 2 && query.startsWith('#') && query.endsWith('#');
}

class SearchSuggestion {
  final String word;
  final int? count;
  final bool hot;
  const SearchSuggestion({required this.word, this.count, this.hot = false});
}

class SearchSuggestions {
  final List<SearchSuggestion> words;
  final List<User> users;
  const SearchSuggestions({this.words = const [], this.users = const []});

  bool get isEmpty => words.isEmpty && users.isEmpty;
}

/// weibo.com's boards; [path] follows `ajax/statuses/`. All but the hot-search board refuse a
/// request without at least a visitor cookie. weibo.com's 我的, 流量 and 飙升 boards need a
/// weibo.com account or a 大V badge, so they are not here.
enum HotBoard {
  realtime('热搜', 'hot_band'),
  entertainment('文娱', 'entertainment'),
  social('社会', 'social'),
  tech('科技', 'technology'),
  life('生活', 'life'),
  sport('体育', 'sport'),
  acg('ACG', 'acg');

  final String label;
  final String path;
  const HotBoard(this.label, this.path);

  static HotBoard? named(String name) => values.where((board) => board.name == name).firstOrNull;
}

/// One of the 推荐 page's channels. [personal] is 热门 as m.weibo.cn draws it for the signed-in
/// account; every other channel (推荐, 同城, 搞笑, 科技 …) is weibo.com's `feed/hottimeline`, the
/// same for everyone.
class RecommendChannel {
  final String gid;
  final String containerId;
  final String title;

  /// In weibo.com's 我的频道 rather than 频道推荐.
  final bool featured;
  final bool personal;

  const RecommendChannel({
    required this.gid,
    required this.containerId,
    required this.title,
    this.featured = true,
    this.personal = false,
  });

  static const hot = RecommendChannel(gid: '102803', containerId: '102803', title: '热门', personal: true);
  static const everyone = RecommendChannel(gid: '102803', containerId: '102803', title: '推荐');

  /// 热门 and 推荐 share weibo's group id.
  String get key => personal ? 'personal' : gid;

  Map<String, dynamic> toJson() => {'gid': gid, 'containerid': containerId, 'title': title, 'personal': personal};

  static RecommendChannel? fromJson(Map<String, dynamic>? json) {
    final gid = json?['gid'];
    final container = json?['containerid'];
    final title = json?['title'];
    if (gid is! String || container is! String || title is! String) return null;
    // Saved before 推荐 split from 热门: that 热门 is now the personal one.
    if (json?['personal'] == true || (json?['personal'] == null && gid == hot.gid && title == hot.title)) return hot;
    return RecommendChannel(gid: gid, containerId: container, title: title);
  }
}

/// The streams m.weibo.cn's search container offers for one query; [type] goes into its id.
enum HotTopicTab {
  all('综合', 1),
  realtime('实时', 61),
  hot('热门', 60),
  video('视频', 64);

  final String label;
  final int type;
  const HotTopicTab(this.label, this.type);
}

/// How a search channel's results are drawn.
enum SearchResultKind { statuses, users, entries }

/// One tab of the search results: m.weibo.cn's `100103type=<type>&q=…` container. The list comes
/// with the first page of 综合 ([parseSearchChannels]); [defaults] is shown until then.
class SearchChannel {
  final String name;
  final int type;
  const SearchChannel(this.name, this.type);

  static const users = 3;
  static const topics = 38;
  static const superTopics = 98;

  /// The streams whose cards are posts. Anything else (地点, 商品 …) is read as plain entries.
  static const _postTypes = {1, 60, 61, 62, 63, 64, 21, 97, 110};

  SearchResultKind get kind => type == users
      ? SearchResultKind.users
      : (_postTypes.contains(type) ? SearchResultKind.statuses : SearchResultKind.entries);

  static const defaults = [
    SearchChannel('综合', 1),
    SearchChannel('实时', 61),
    SearchChannel('热门', 60),
    SearchChannel('用户', users),
    SearchChannel('视频', 64),
    SearchChannel('图片', 63),
    SearchChannel('关注', 62),
    SearchChannel('文章', 21),
    SearchChannel('话题', topics),
    SearchChannel('超话', superTopics),
  ];

  @override
  bool operator ==(Object other) => other is SearchChannel && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(name, type);
}

/// A search result that is neither a post nor a person: a topic, a super topic, a place …
class SearchEntry {
  final String title;
  final String? subtitle;
  final String? detail;
  final String? imageUrl;

  /// Where a tap goes; may be a `sinaweibo://` address, which [openLink] understands.
  final String? url;
  const SearchEntry({required this.title, this.subtitle, this.detail, this.imageUrl, this.url});

  /// `#话题#` titles open as a topic.
  bool get isTopic => title.length > 2 && title.startsWith('#') && title.endsWith('#');
}

/// The sections of someone's page. weibo.com's `profile/info` names those an account has in
/// `tabList`; [featured] and [posts] are always there.
enum ProfileTab {
  posts('微博', 'feed'),
  featured('精选', 'hot'),
  videos('视频', 'newVideo'),
  photos('相册', 'album'),
  audio('音频', 'audio'),
  articles('文章', 'article');

  final String label;

  /// weibo.com's name for it in `tabList`.
  final String key;
  const ProfileTab(this.label, this.key);

  static const fallback = [posts, featured, videos, photos];
}

/// The 微博 tab's filters: m.weibo.cn's second-level profile streams.
enum ProfilePostFilter {
  all('全部', ''),
  original('原创', 'ORI'),
  pictures('图片', 'PIC'),
  videos('视频', 'VIDEO');

  final String label;
  final String suffix;
  const ProfilePostFilter(this.label, this.suffix);
}

/// One picture on someone's 相册 wall, and the post it came from.
class ProfilePhoto {
  final Media media;
  final String? statusId;
  const ProfilePhoto(this.media, {this.statusId});
}

/// What weibo.com adds to a profile: its tabs, the 转评赞 its posts have had, and short facts
/// (IP 属地, 生日, 注册时间, 阳光信用, 视频累计播放量 …).
class ProfileExtras {
  final List<ProfileTab> tabs;

  /// Null when weibo.com did not say.
  final int? interactions;
  final int? likes;
  final int? comments;
  final int? reposts;
  final List<String> facts;

  /// weibo.com's cover, which has the account's own picture where m.weibo.cn often has the stock one.
  final String? coverUrl;
  final VerifiedBadge? verified;

  final VipIcon? vip;

  /// `m` or `f`; null when not said.
  final String? gender;
  const ProfileExtras({
    this.tabs = ProfileTab.fallback,
    this.interactions,
    this.likes,
    this.comments,
    this.reposts,
    this.facts = const [],
    this.coverUrl,
    this.verified,
    this.vip,
    this.gender,
  });
}

/// The 会员 icon: VIP, SVIP or VVIP with its level; [aspect] is width over height.
class VipIcon {
  final String url;
  final double aspect;
  const VipIcon(this.url, this.aspect);
}

/// weibo.com's V by colour: gold, orange and yellow for people (gold and orange the higher grades),
/// blue for organisations, red for government media, grey for a lapsed one.
enum VerifiedBadge { gold, orange, yellow, blue, red, grey }

/// One run of a topic on a Weibo board: 热搜榜, 文娱榜, 社会榜 …
class TopicBoardStint {
  final String board;
  final int? bestRank;
  final int minutes;
  final DateTime? onAt;

  /// Null while it is still on the board.
  final DateTime? offAt;
  const TopicBoardStint({required this.board, this.bestRank, this.minutes = 0, this.onAt, this.offAt});
}

/// What Weibo says about a topic or a hot-search keyword: its head on m.weibo.cn and its card on
/// m.s.weibo.com. Every field is optional; a keyword that is not a hashtag has few of them.
class TopicInfo {
  final String? title;

  /// 导语: the short editorial summary some topics carry.
  final String? lead;
  final String? coverUrl;

  /// The stats line as m.weibo.cn writes it, kept for when no figure could be read from it.
  final String? stats;
  final int? reads;
  final int? discussions;
  final int? originals;
  final int? interactions;
  final String? host;
  final String? hostId;

  /// What else the head says after the host, e.g. 「14家媒体发布」.
  final String? note;
  final String? category;

  /// Weibo's one-line verdict on the topic, e.g. 「剧集领域热度第1名」.
  final String? highlight;
  final List<TopicBoardStint> boards;
  final List<User> contributors;
  final List<User> media;
  final DateTime? createdAt;

  /// The post the topic was started with.
  final String? firstStatusId;

  const TopicInfo({
    this.title,
    this.lead,
    this.coverUrl,
    this.stats,
    this.reads,
    this.discussions,
    this.originals,
    this.interactions,
    this.host,
    this.hostId,
    this.note,
    this.category,
    this.highlight,
    this.boards = const [],
    this.contributors = const [],
    this.media = const [],
    this.createdAt,
    this.firstStatusId,
  });

  bool get isEmpty =>
      lead == null &&
      coverUrl == null &&
      stats == null &&
      reads == null &&
      discussions == null &&
      host == null &&
      boards.isEmpty &&
      contributors.isEmpty;

  /// This, with the gaps filled from [other].
  TopicInfo merge(TopicInfo? other) => other == null
      ? this
      : TopicInfo(
          title: title ?? other.title,
          lead: lead ?? other.lead,
          coverUrl: coverUrl ?? other.coverUrl,
          stats: stats ?? other.stats,
          reads: reads ?? other.reads,
          discussions: discussions ?? other.discussions,
          originals: originals ?? other.originals,
          interactions: interactions ?? other.interactions,
          host: host ?? other.host,
          hostId: hostId ?? other.hostId,
          note: note ?? other.note,
          category: category ?? other.category,
          highlight: highlight ?? other.highlight,
          boards: boards.isNotEmpty ? boards : other.boards,
          contributors: contributors.isNotEmpty ? contributors : other.contributors,
          media: media.isNotEmpty ? media : other.media,
          createdAt: createdAt ?? other.createdAt,
          firstStatusId: firstStatusId ?? other.firstStatusId,
        );
}

/// Reads per hour over the last day, oldest first.
class TopicTrendPoint {
  final String label;
  final int value;
  const TopicTrendPoint(this.label, this.value);
}

class SuperTopic {
  final String name;
  final String? iconUrl;
  final String? containerId;
  final String? followersLabel;
  final bool followed;
  const SuperTopic({
    required this.name,
    this.iconUrl,
    this.containerId,
    this.followersLabel,
    this.followed = false,
  });
}

class UserProfile {
  final User user;
  final String? coverUrl;
  final String? verifiedReason;
  final bool following;
  final bool followsYou;

  const UserProfile({
    required this.user,
    this.coverUrl,
    this.verifiedReason,
    this.following = false,
    this.followsYou = false,
  });

  UserProfile withFollowing(bool follow) {
    if (follow == following) return this;
    final delta = follow ? 1 : -1;
    return UserProfile(
      user: user.copyWith(
        following: follow,
        followersCount: math.max(0, user.followersCount + delta),
      ),
      coverUrl: coverUrl,
      verifiedReason: verifiedReason,
      following: follow,
      followsYou: followsYou,
    );
  }
}

enum FeedKind { all, group, circle, private, liked, favorites, card }

class FeedSource {
  final FeedKind kind;
  final String name;
  final String id;
  const FeedSource(this.kind, this.name, [this.id = '']);

  static const all = FeedSource(FeedKind.all, '全部关注');
  static const circle = FeedSource(FeedKind.circle, '好友圈');
  static const private = FeedSource(FeedKind.private, '悄悄关注');
  static const liked = FeedSource(FeedKind.liked, '我赞过的');
  static const favorites = FeedSource(FeedKind.favorites, '我的收藏');

  String get key => '${kind.name}\u001F${id.isEmpty ? kind.name : id}';

  static FeedSource? fromKey(String? key, List<FeedSource> sources) {
    if (key == null) return null;
    final parts = key.split('\u001F');
    if (parts.length != 2) return null;
    final kind = FeedKind.values.where((k) => k.name == parts[0]).firstOrNull;
    if (kind == null) return null;
    return sources.where((s) => s.kind == kind && (s.id.isEmpty ? s.kind.name : s.id) == parts[1]).firstOrNull;
  }
}

enum FriendsTab {
  following('关注的人', '231093_-_selffollowed'),
  recent('经常访问', '231093_-_recently'),
  recommended('推荐', '231093_-_selfrecomm');

  final String label;
  final String container;
  const FriendsTab(this.label, this.container);

  static FriendsTab of(String? name) =>
      values.where((t) => t.name.toLowerCase() == (name ?? '').toLowerCase()).firstOrNull ?? following;
}

enum RelationKind { following, followers }

String relationContainer(RelationKind kind, String uid, {bool self = false}) => switch (kind) {
      RelationKind.following => self ? '231093_-_selffollowed' : '231051_-_followers_-_$uid',
      RelationKind.followers => self ? '231016_-_selffans' : '231051_-_fans_-_$uid',
    };

String likedContainer(String uid) => '230869${uid}_-_mix';

enum DraftType { original, repost, comment, reply }
enum DraftState { editing, queued, sending, failed }

class Draft {
  final int id;
  final DraftType type;
  final String text;
  final String? statusId;
  final String? commentId;
  final String? replyToName;
  final List<String> images;
  final bool crossPost;
  final DraftState state;
  final String? error;
  final DateTime updatedAt;

  const Draft({
    this.id = 0,
    required this.type,
    this.text = '',
    this.statusId,
    this.commentId,
    this.replyToName,
    this.images = const [],
    this.crossPost = false,
    this.state = DraftState.editing,
    this.error,
    required this.updatedAt,
  });

  Draft copyWith({
    int? id,
    String? text,
    List<String>? images,
    bool? crossPost,
    DraftState? state,
    String? error,
    DateTime? updatedAt,
  }) =>
      Draft(
        id: id ?? this.id,
        type: type,
        text: text ?? this.text,
        statusId: statusId,
        commentId: commentId,
        replyToName: replyToName,
        images: images ?? this.images,
        crossPost: crossPost ?? this.crossPost,
        state: state ?? this.state,
        error: error ?? this.error,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  bool get isEmpty => text.trim().isEmpty && images.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'text': text,
        'statusId': statusId,
        'commentId': commentId,
        'replyToName': replyToName,
        'images': images,
        'crossPost': crossPost,
        'state': state.name,
        'error': error,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Draft.fromJson(Map<String, dynamic> json) => Draft(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: DraftType.values.where((t) => t.name == json['type']).firstOrNull ?? DraftType.original,
        text: json['text'] as String? ?? '',
        statusId: json['statusId'] as String?,
        commentId: json['commentId'] as String?,
        replyToName: json['replyToName'] as String?,
        images: (json['images'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        crossPost: json['crossPost'] == true,
        state: DraftState.values.where((s) => s.name == json['state']).firstOrNull ?? DraftState.editing,
        error: json['error'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class ViewedStatus {
  final String statusId;
  final String authorName;
  final String? avatarUrl;
  final String text;
  final DateTime viewedAt;
  const ViewedStatus({
    required this.statusId,
    required this.authorName,
    this.avatarUrl,
    required this.text,
    required this.viewedAt,
  });

  Map<String, dynamic> toJson() => {
        'statusId': statusId,
        'authorName': authorName,
        'avatarUrl': avatarUrl,
        'text': text,
        'viewedAt': viewedAt.toIso8601String(),
      };

  factory ViewedStatus.fromJson(Map<String, dynamic> json) => ViewedStatus(
        statusId: json['statusId'] as String? ?? '',
        authorName: json['authorName'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        text: json['text'] as String? ?? '',
        viewedAt: DateTime.tryParse(json['viewedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class PageResult<T> {
  final List<T> items;
  final String? nextCursor;
  const PageResult(this.items, this.nextCursor);
}

/// A passport QR login: [imageUrl] draws the code, [scanUrl] is what it encodes, which the Weibo
/// app on the same phone can open directly instead of scanning.
class QrLogin {
  final String qrid;
  final String imageUrl;
  final String scanUrl;
  const QrLogin({required this.qrid, required this.imageUrl, required this.scanUrl});
}

enum QrLoginState { waiting, scanned, failed, confirmed }

class QrLoginStatus {
  final QrLoginState state;
  final String? message;

  /// On [QrLoginState.confirmed], the first hop of the SSO chain; the WebView has to follow it so
  /// the signed-in cookies land where m.weibo.cn reads them.
  final String? url;
  const QrLoginStatus(this.state, {this.message, this.url});
}