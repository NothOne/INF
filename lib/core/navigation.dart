import 'package:flutter/material.dart';

import '../core/container_route.dart';
import '../core/models.dart';
import '../features/compose/compose_page.dart';
import '../features/detail/status_detail_page.dart';
import '../features/friends/friends_page.dart';
import '../features/history/drafts_page.dart';
import '../features/history/viewed_page.dart';
import '../features/login/login_page.dart';
import '../features/longimage/long_image_page.dart';
import '../features/media/image_viewer_page.dart';
import '../features/media/video_page.dart';
import '../features/message/chat_page.dart';
import '../features/relations/relations_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/topic/hot_topic_page.dart';
import '../features/topic/super_topics_page.dart';
import '../features/topic/topic_page.dart';
import '../features/user/user_page.dart';
import '../features/web/web_page.dart';

/// Normal destinations use MaterialPageRoute so the app-wide PageTransitionsTheme
/// (fade-forwards with predictive back on Android, Cupertino on iOS) owns the transition. A tap
/// that captured a [ContainerOrigin] just before gets a page that grows out of what was tapped.
Future<T?> pushInf<T>(BuildContext context, Widget page, {bool overlay = false}) {
  if (overlay) {
    return Navigator.of(context).push<T>(
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
  if (origin != null) {
    return Navigator.of(context).push<T>(ContainerTransformRoute<T>(origin: origin, builder: (context) => page));
  }
  return Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (context) => page));
}

Future<void> openStatus(
  BuildContext context, {
  required String statusId,
  Status? seed,
}) {
  // Lists pass the post they show, also when the tap was on the original it reposts.
  final matching = seed?.id == statusId ? seed : (seed?.repostOf?.id == statusId ? seed?.repostOf : null);
  return pushInf(context, StatusDetailPage(statusId: statusId, seed: matching));
}

Future<void> openUser(BuildContext context, String uid) =>
    pushInf(context, UserPage(uid: uid));

/// A hashtag opens on its topic page; with [query] it is the topic narrowed by that keyword.
Future<void> openTopic(BuildContext context, String name, {String? query}) {
  if (query != null && query.trim().isNotEmpty) return pushInf(context, TopicPage(name: name, query: query));
  final topic = name.replaceAll('#', '').trim();
  return pushInf(context, HotTopicPage(query: '#$topic#'));
}

/// A hot-search entry or any keyword: its board stats, head, related searches and posts.
Future<void> openHotTopic(BuildContext context, {required String query, HotSearch? entry}) =>
    pushInf(context, HotTopicPage(query: query, entry: entry));

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
  bool group = false,
}) =>
    pushInf(context, ChatPage(uid: uid, name: name, group: group));

Future<void> openWeb(BuildContext context, String url) => pushInf(context, WebPage(url: url));

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
  return Navigator.of(context).push<void>(
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
    pushInf(context, TopicPage(name: name, containerId: containerId, title: name));