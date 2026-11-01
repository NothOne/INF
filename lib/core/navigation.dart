import 'package:flutter/material.dart';

import '../core/container_route.dart';
import '../core/links.dart';
import '../core/models.dart';
import '../core/pane.dart';
import '../core/prefs.dart';
import '../features/compose/compose_page.dart';
import '../features/detail/status_detail_page.dart';
import '../features/friends/friends_page.dart';
import '../features/history/drafts_page.dart';
import '../features/history/viewed_page.dart';
import '../features/login/login_page.dart';
import '../features/longimage/long_image_page.dart';
import '../features/media/image_viewer_page.dart';
import '../features/media/video_page.dart';
import '../features/place/place_sheet.dart';
import '../features/message/chat_page.dart';
import '../features/relations/relations_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/topic/hot_topic_page.dart';
import '../features/topic/super_topics_page.dart';
import '../features/topic/topic_page.dart';
import '../features/topic/topic_timeline_page.dart';
import '../features/user/user_page.dart';
import '../features/web/link_fallback_page.dart';
import '../features/web/web_page.dart';

/// Every page moves the one way [Prefs.pageMotion] says. [PageMotion.expand] grows it out of the
/// [ContainerOrigin] the tap captured just before, or out of the touch itself; [PageMotion.slide]
/// is MaterialPageRoute, so the app-wide PageTransitionsTheme (fade-forwards with predictive back
/// on Android, Cupertino on iOS) owns the transition.
///
/// [pane] marks a page that may open in the [DetailPane] beside a list, and names what it shows
/// so the list can mark it; it does whenever [context] is in or beside one. Everything else opens
/// over the whole screen, also when asked for from inside the pane.
Future<T?> pushInf<T>(BuildContext context, Widget page, {bool overlay = false, String? pane}) {
  if (pane != null) {
    final detail = DetailPane.maybeOf(context);
    if (detail != null) {
      ContainerOrigin.take();
      return detail.open<T>(context, page, key: pane);
    }
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  if (overlay) {
    return navigator.push<T>(
      PageRouteBuilder<T>(
        opaque: false,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: child,
        ),
      ),
    );
  }
  final origin = ContainerOrigin.take();
  if (Prefs.instance.pageMotion == PageMotion.slide) {
    return navigator.push<T>(MaterialPageRoute<T>(builder: (context) => page));
  }
  return navigator.push<T>(ContainerTransformRoute<T>(
    origin: origin ?? ContainerOrigin.atTouch(MediaQuery.sizeOf(context)),
    builder: (context) => page,
  ));
}

Future<void> openStatus(
  BuildContext context, {
  required String statusId,
  Status? seed,
}) {
  // Lists pass the post they show, also when the tap was on the original it reposts.
  final matching = seed?.id == statusId ? seed : (seed?.repostOf?.id == statusId ? seed?.repostOf : null);
  return pushInf(context, StatusDetailPage(statusId: statusId, seed: matching), pane: 'status:$statusId');
}

/// The replies under one comment of a post.
Future<void> openCommentFloor(BuildContext context, {required String statusId, required Comment root}) => pushInf(
      context,
      CommentFloorPage(statusId: statusId, commentId: root.id, root: root),
      pane: 'floor:${root.id}',
    );

Future<void> openUser(BuildContext context, String uid) =>
    pushInf(context, UserPage(uid: uid), pane: 'user:$uid');

/// A hashtag opens on its topic page; with [query] it is the topic narrowed by that keyword.
Future<void> openTopic(BuildContext context, String name, {String? query}) {
  if (query != null && query.trim().isNotEmpty) {
    return pushInf(context, TopicPage(name: name, query: query), pane: 'topic:$name:$query');
  }
  final topic = name.replaceAll('#', '').trim();
  return pushInf(context, HotTopicPage(query: '#$topic#'), pane: 'topic:#$topic#');
}

/// A hot-search entry or any keyword: its board stats, head, related searches and posts.
Future<void> openHotTopic(BuildContext context, {required String query, HotSearch? entry}) =>
    pushInf(context, HotTopicPage(query: query, entry: entry), pane: 'topic:$query');

Future<void> openTopicTimeline(
  BuildContext context, {
  required String query,
  required String title,
  TopicInfo? info,
  List<TopicTrendPoint>? trend,
  HotSearch? entry,
}) =>
    pushInf(
      context,
      TopicTimelinePage(query: query, title: title, info: info, trend: trend, entry: entry),
      pane: 'timeline:$query',
    );

Future<void> openSearch(BuildContext context, {String? query}) =>
    pushInf(context, SearchPage(initialQuery: query));

Future<void> openCompose(
  BuildContext context, {
  DraftType type = DraftType.original,
  String? statusId,
  String? commentId,
  String? replyToName,
  int? draftId,
  String? initialText,
}) =>
    pushInf(
      context,
      ComposePage(
        type: type,
        statusId: statusId,
        commentId: commentId,
        replyToName: replyToName,
        draftId: draftId,
        initialText: initialText,
      ),
    );

Future<void> openLogin(BuildContext context) => pushInf(context, const LoginPage());

Future<void> openSettings(BuildContext context) => pushInf(context, const SettingsPage());

Future<void> openSuperTopics(BuildContext context) => pushInf(context, const SuperTopicsPage());

Future<void> openFriends(BuildContext context, {FriendsTab tab = FriendsTab.following}) =>
    pushInf(context, FriendsPage(initialTab: tab));

Future<void> openRelations(
  BuildContext context, {
  required String uid,
  RelationKind kind = RelationKind.following,
}) =>
    pushInf(context, RelationsPage(uid: uid, initialKind: kind));

Future<void> openLiked(BuildContext context, String uid) =>
    pushInf(context, TopicPage(name: '', likedUid: uid, title: '赞过', emptyText: '还没有赞过微博'));

Future<void> openViewed(BuildContext context) => pushInf(context, const ViewedPage());

Future<void> openDrafts(BuildContext context) => pushInf(context, const DraftsPage());

Future<void> openChat(
  BuildContext context, {
  required String uid,
  String? name,
  String? avatar,
  bool group = false,
}) =>
    pushInf(context, ChatPage(uid: uid, name: name, avatar: avatar, group: group), pane: 'chat:$uid');

Future<void> openWeb(BuildContext context, String url) => pushInf(context, WebPage(url: url));

/// Any link: a post, a person, a topic or a super topic opens on INF's own page, t.cn is asked
/// where it goes first, other addresses load in [WebPage], and what only the Weibo app can show
/// lands on [LinkFallbackPage].
Future<void> openLink(BuildContext context, String url, {String? title}) async {
  var target = linkTargetOf(url);
  if (target is ShortLinkTarget) {
    final expanded = await expandShortLink(target.url);
    if (!context.mounted) return;
    target = expanded == null ? WebTarget(target.url) : linkTargetOf(expanded);
    if (target is ShortLinkTarget) target = WebTarget(target.url);
  }
  if (!context.mounted) return;
  switch (target) {
    case StatusTarget(:final id):
      return openStatus(context, statusId: id);
    case UserTarget(:final user):
      return openUser(context, user);
    case TopicTarget(:final name):
      return openTopic(context, name);
    case SuperTopicTarget(:final containerId, :final name):
      return openTopicFeed(context, containerId: containerId, name: name.isEmpty ? '超话' : '$name超话');
    case WebTarget(:final url):
      return openWeb(context, url);
    case AppOnlyTarget(:final url):
      return openLinkFallback(context, url, title: title);
    case ClientPageTarget(:final url, :final appUrl):
      return openLinkFallback(context, url, appUrl: appUrl, title: title);
    case ShortLinkTarget(:final url):
      return openWeb(context, url);
  }
}

Future<void> openLinkFallback(BuildContext context, String url, {String? appUrl, String? title}) =>
    pushInf(context, LinkFallbackPage(url: url, appUrl: appUrl, title: title));

/// Where a post was sent from: its address, and the way there in a map app.
Future<void> openPlace(BuildContext context, Place place) => showPlaceSheet(context, place);

Future<void> openVideo(BuildContext context, String url, {String? coverUrl}) =>
    pushInf(context, VideoPage(url: url, coverUrl: coverUrl), overlay: true);

Future<void> openImage(
  BuildContext context, {
  required List<Media> media,
  int index = 0,
  String? heroTag,
}) {
  final images = media.where((m) => m.kind == MediaKind.image).toList();
  if (images.isEmpty) return Future.value();
  final target = media[index];
  final initial = images.indexOf(target);
  // The image viewer is a Hero-first route: fading the whole route while the
  // Hero shrinks makes the full-screen image flash for one frame on pop.
  // No barrier colour: the viewer paints its own backdrop so a drag can thin it.
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => ImageViewerPage(
        images: images,
        initialIndex: initial < 0 ? 0 : initial,
        heroTag: heroTag,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
    ),
  );
}

Future<void> openLongImage(BuildContext context, Status status) =>
    pushInf(context, LongImagePage(status: status));

Future<void> openTopicFeed(
  BuildContext context, {
  required String containerId,
  required String name,
}) =>
    pushInf(context, TopicPage(name: name, containerId: containerId, title: name), pane: 'topic-feed:$containerId');