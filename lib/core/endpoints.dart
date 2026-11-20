/// Every place the app asks Weibo for something, and the three facts that used to live in comments
/// beside each method: which host it is, what gets it an answer, and whether a captcha can come
/// back instead.
///
/// This is data, not a layer. Nothing routes through it — the transport still takes a path string —
/// so a parser or a page reads exactly as before. What it buys is that the pairing of host and
/// credential is written once, in a table the tests check against the transports, instead of being
/// re-stated (and occasionally re-stated wrong) beside fifty methods in nine files.
///
/// The one thing read at runtime is [Endpoint.captchaRisk]: a write can be answered with
/// `error_type: captcha`, and knowing that before the request is sent is what lets a page warn the
/// reader instead of surprising them at the end of a post they just finished writing.
library;

/// Which of Weibo's services a request goes to.
///
/// These are not interchangeable: each has its own cookie, its own error shape, and its own idea of
/// what a successful answer looks like. Mixing two of them in one class is how a request ends up
/// carrying the wrong cookie, which has happened — see `DEVLOG.md`.
enum EndpointHost {
  /// `m.weibo.cn`, the phone site. Most of the app speaks this one.
  mWeibo,

  /// `weibo.com`'s `ajax/*`. Signed-out callers get a visitor identity or nothing at all.
  weiboCom,

  /// `api.weibo.com/webim/*`, the group chat backend: another host, another cookie, and
  /// `result: false` rather than `ok: 0`.
  apiWeibo,

  /// `passport.weibo.com`, which hands out the visitor identity and the login QR code.
  passport,

  /// `m.s.weibo.com`, the topic page's data. Answers only with that topic's own page as Referer.
  msWeibo,
}

/// What a request needs before the host will answer it.
enum EndpointAuth {
  /// The signed-in account's own cookie for that host.
  user,

  /// An anonymous identity obtained from passport, replaced when the service refuses the old one.
  visitor,

  /// Nothing. The answer is the same for anyone.
  none,
}

/// One thing the app asks for, named after the method that asks.
///
/// [path] is the address below the host, exactly as the transport receives it. Where one path
/// answers several different questions — every container read is `api/container/getIndex` — each
/// question gets its own row: these are capabilities, not routes.
enum Endpoint {
  // ---- m.weibo.cn: reading ----------------------------------------------------------------

  config(EndpointHost.mWeibo, 'api/config', EndpointAuth.user),
  feedGroups(EndpointHost.mWeibo, 'api/config/list', EndpointAuth.user),
  feedFriends(EndpointHost.mWeibo, 'feed/friends', EndpointAuth.user, cached: true),
  feedGroup(EndpointHost.mWeibo, 'feed/group', EndpointAuth.user, cached: true),
  feedCircle(EndpointHost.mWeibo, 'feed/circle', EndpointAuth.user, cached: true),
  feedPrivate(EndpointHost.mWeibo, 'feed/private', EndpointAuth.user, cached: true),

  /// 赞过、收藏 and a 推荐 channel: card containers rather than feed lists.
  feedContainer(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user, cached: true),
  statusShow(EndpointHost.mWeibo, 'statuses/show', EndpointAuth.user),
  statusLongText(EndpointHost.mWeibo, 'statuses/extend', EndpointAuth.user),
  comments(EndpointHost.mWeibo, 'comments/hotflow', EndpointAuth.user, cached: true),

  /// The replies under one comment. Answers with the thread's root comment as well.
  commentReplies(EndpointHost.mWeibo, 'comments/hotFlowChild', EndpointAuth.user),
  reposts(EndpointHost.mWeibo, 'api/statuses/repostTimeline', EndpointAuth.user),
  userTimeline(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user),
  userProfile(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user, cached: true),
  searchStatuses(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user),
  searchUsers(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user),
  relations(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user),
  superTopics(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user),

  /// The 热搜 board as m.weibo.cn draws it: the fallback when weibo.com's own is unavailable.
  hotSearchFallback(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user),

  /// A topic's or a search's posts, with the head of the first page as a bonus.
  topicPage(EndpointHost.mWeibo, 'api/container/getIndex', EndpointAuth.user),
  unread(EndpointHost.mWeibo, 'api/remind/unread', EndpointAuth.user),
  notifyMentionsInStatuses(EndpointHost.mWeibo, 'message/mentionsAt', EndpointAuth.user, cached: true),
  notifyMentionsInComments(EndpointHost.mWeibo, 'message/mentionsCmt', EndpointAuth.user, cached: true),
  notifyComments(EndpointHost.mWeibo, 'message/cmt', EndpointAuth.user, cached: true),
  notifyLikes(EndpointHost.mWeibo, 'message/attitude', EndpointAuth.user, cached: true),
  conversations(EndpointHost.mWeibo, 'message/msglist', EndpointAuth.user, cached: true),
  strangers(EndpointHost.mWeibo, 'message/notelist', EndpointAuth.user, cached: true),
  chat(EndpointHost.mWeibo, 'api/chat/list', EndpointAuth.user),
  groupChat(EndpointHost.mWeibo, 'api/groupchat/list', EndpointAuth.user),

  // ---- m.weibo.cn: writing ----------------------------------------------------------------
  //
  // Every one of these goes through `_post`, which is where the captcha retry lives, so every one
  // can come back as a captcha.

  like(EndpointHost.mWeibo, 'api/attitudes/create', EndpointAuth.user, captchaRisk: true),
  unlike(EndpointHost.mWeibo, 'api/attitudes/destroy', EndpointAuth.user, captchaRisk: true),
  likeComment(EndpointHost.mWeibo, 'api/likes/update', EndpointAuth.user, captchaRisk: true),
  unlikeComment(EndpointHost.mWeibo, 'api/likes/destroy', EndpointAuth.user, captchaRisk: true),
  favorite(EndpointHost.mWeibo, 'api/statuses/createfav', EndpointAuth.user, captchaRisk: true),
  unfavorite(EndpointHost.mWeibo, 'api/statuses/destroyfav', EndpointAuth.user, captchaRisk: true),
  uploadPicture(EndpointHost.mWeibo, 'api/statuses/uploadPic', EndpointAuth.user, captchaRisk: true),
  postStatus(EndpointHost.mWeibo, 'api/statuses/update', EndpointAuth.user, captchaRisk: true),
  repost(EndpointHost.mWeibo, 'api/statuses/repost', EndpointAuth.user, captchaRisk: true),
  comment(EndpointHost.mWeibo, 'api/comments/create', EndpointAuth.user, captchaRisk: true),
  reply(EndpointHost.mWeibo, 'api/comments/reply', EndpointAuth.user, captchaRisk: true),
  follow(EndpointHost.mWeibo, 'api/friendships/create', EndpointAuth.user, captchaRisk: true),

  /// Weibo's own spelling is `destory`; the path is not misspelled on this side.
  unfollow(EndpointHost.mWeibo, 'api/friendships/destory', EndpointAuth.user, captchaRisk: true),
  sendMessage(EndpointHost.mWeibo, 'api/chat/send', EndpointAuth.user, captchaRisk: true),
  sendGroupMessage(EndpointHost.mWeibo, 'api/groupchat/send', EndpointAuth.user, captchaRisk: true),
  uploadChatPicture(EndpointHost.mWeibo, 'api/chat/upload', EndpointAuth.user, captchaRisk: true),

  /// Also `quite`: Weibo's spelling again.
  leaveGroup(EndpointHost.mWeibo, 'api/groupchat/quite', EndpointAuth.user, captchaRisk: true),

  // ---- weibo.com --------------------------------------------------------------------------

  /// The 热搜 board, which carries rank, badge, category and the time each entry made the list.
  hotBand(EndpointHost.weiboCom, 'statuses/hot_band', EndpointAuth.none),
  hotBoardEntertainment(EndpointHost.weiboCom, 'statuses/entertainment', EndpointAuth.visitor),
  hotBoardSocial(EndpointHost.weiboCom, 'statuses/social', EndpointAuth.visitor),
  hotBoardTechnology(EndpointHost.weiboCom, 'statuses/technology', EndpointAuth.visitor),
  hotBoardLife(EndpointHost.weiboCom, 'statuses/life', EndpointAuth.visitor),
  hotBoardSport(EndpointHost.weiboCom, 'statuses/sport', EndpointAuth.visitor),
  hotBoardAcg(EndpointHost.weiboCom, 'statuses/acg', EndpointAuth.visitor),

  /// 推荐 channels. The same for every visitor, and answered without one too.
  recommendChannels(EndpointHost.weiboCom, 'feed/allGroups', EndpointAuth.none),
  recommendFeed(EndpointHost.weiboCom, 'feed/hottimeline', EndpointAuth.visitor),
  profileInfo(EndpointHost.weiboCom, 'profile/info', EndpointAuth.visitor),
  profileDetail(EndpointHost.weiboCom, 'profile/detail', EndpointAuth.visitor),

  /// 精选, and the posts, pictures and videos tabs: m.weibo.cn containers drawn for a visitor.
  profileFeature(EndpointHost.weiboCom, 'profile/feature', EndpointAuth.visitor),
  profileWaterfall(EndpointHost.weiboCom, 'profile/getWaterFallContent', EndpointAuth.visitor),
  profileAudioList(EndpointHost.weiboCom, 'profile/getAudioList', EndpointAuth.visitor),
  profileImageWall(EndpointHost.weiboCom, 'profile/getImageWall', EndpointAuth.visitor),

  /// 搜他的微博: answered only to the signed-in weibo.com cookie, never to a visitor.
  searchBlog(EndpointHost.weiboCom, 'profile/searchblog', EndpointAuth.user),

  /// weibo.com's copy of a post: the signed address for its sound, and the card address a feed
  /// left out.
  statusShowCom(EndpointHost.weiboCom, 'statuses/show', EndpointAuth.visitor),
  searchSuggestions(EndpointHost.weiboCom, 'side/search', EndpointAuth.none),

  /// 加入黑名单. m.weibo.cn has no blacklist, so this is weibo.com's — and it answers `{ok: 1}`
  /// without the envelope `_post` reads, which is why it cannot raise a captcha.
  hideUser(EndpointHost.weiboCom, 'statuses/filterUser', EndpointAuth.user),

  // ---- api.weibo.com: group chat -----------------------------------------------------------
  //
  // None of this exists on m.weibo.cn. The envelope is `result: false`, not `ok: 0`, so none of
  // these can raise a captcha either.

  groupInfo(EndpointHost.apiWeibo, 'groupchat/query.json', EndpointAuth.user),
  groupMembers(EndpointHost.apiWeibo, 'query_group.json', EndpointAuth.user),
  groupMuted(EndpointHost.apiWeibo, '2/notice_center/discussion_group/push_settings.json', EndpointAuth.user),
  updateGroupMuted(EndpointHost.apiWeibo, '2/notice_center/discussion_group/set_push_settings.json', EndpointAuth.user),
  updateGroupNotice(EndpointHost.apiWeibo, 'groupchat/send_bulletin.json', EndpointAuth.user),

  // ---- passport ---------------------------------------------------------------------------

  /// The anonymous SUB/SUBP pair every visitor-wall request is made with.
  visitorIdentity(EndpointHost.passport, 'visitor/genvisitor2', EndpointAuth.none),

  /// A login QR code. Answered with `retcode`, not `ok`.
  qrImage(EndpointHost.passport, 'sso/v2/qrcode/image', EndpointAuth.none),
  qrCheck(EndpointHost.passport, 'sso/v2/qrcode/check', EndpointAuth.none),

  // ---- m.s.weibo.com ----------------------------------------------------------------------

  topicDetail(EndpointHost.msWeibo, 'ajax_topic/detail', EndpointAuth.none),
  topicTrend(EndpointHost.msWeibo, 'ajax_topic/trend', EndpointAuth.none);

  const Endpoint(this.host, this.path, this.auth, {this.captchaRisk = false, this.cached = false});

  final EndpointHost host;

  /// The address below the host, as the transport is given it.
  final String path;

  final EndpointAuth auth;

  /// Whether Weibo may answer this with `error_type: captcha` instead of doing it.
  ///
  /// True for every m.weibo.cn write, because all of them go through `_post` and the refusal
  /// arrives inside the same envelope. False for the other hosts, which answer in shapes that
  /// never carry a captcha id — a page that warned about one there would be warning about
  /// something that cannot happen.
  final bool captchaRisk;

  /// Whether the first page of this answer is kept in `PageCache` for the next launch.
  final bool cached;

  /// The endpoints that can be refused with a captcha, should a page want to warn first.
  static List<Endpoint> get captchaRisks => values.where((e) => e.captchaRisk).toList(growable: false);

  /// Every endpoint path asked of [host], for the tests that compare this table to the transports.
  static Set<String> pathsOn(EndpointHost host) =>
      {for (final endpoint in values) if (endpoint.host == host) endpoint.path};
}
