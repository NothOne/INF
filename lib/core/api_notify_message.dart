part of 'api.dart';

/// Notifications and both kinds of message. The messages are m.weibo.cn; group settings are in `group_chat_api.dart`.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiNotifyMessage on WeiboApi {

  Future<UnreadCounts> unread() async {
    final data = await _get('api/remind/unread', query: {
      't': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    return parseUnread(data);
  }

  CachedPage<NotificationItem> _notificationsPage(NotificationKind kind, [int page = 1]) =>
      CachedPage<NotificationItem>(
        key: 'notify-${kind.name}',
        parse: (data) {
          final items = parseNotifications(data, kind);
          return PageResult(items, items.isEmpty ? null : '${page + 1}');
        },
      );

  Future<PageResult<NotificationItem>> notifications(NotificationKind kind, String? cursor) async {
    final path = switch (kind) {
      NotificationKind.mentionInStatus => 'message/mentionsAt',
      NotificationKind.mentionInComment => 'message/mentionsCmt',
      NotificationKind.comment => 'message/cmt',
      NotificationKind.like => 'message/attitude',
    };
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await _get(path, query: {'page': page.toString()}, emptyIsOk: true);
    return _notificationsPage(kind, page).accept(data, isFirstPage: page == 1);
  }

  PageResult<NotificationItem>? cachedNotifications(NotificationKind kind) => _notificationsPage(kind).read();

  CachedPage<Conversation> _conversationsPage(bool strangers, [int page = 1]) => CachedPage<Conversation>(
        key: 'conversations-$strangers',
        parse: (data) {
          final items = parseConversations(data);
          return PageResult(items, items.isEmpty ? null : '${page + 1}');
        },
      );

  Future<PageResult<Conversation>> conversations(bool strangers, String? cursor) async {
    final path = strangers ? 'message/notelist' : 'message/msglist';
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await _get(path, query: {'page': page.toString()}, emptyIsOk: true);
    return _conversationsPage(strangers, page).accept(data, isFirstPage: page == 1);
  }

  PageResult<Conversation>? cachedConversations(bool strangers) => _conversationsPage(strangers).read();

  Future<PageResult<DirectMessage>> chat(String uid, String? cursor) async {
    final data = await _get('api/chat/list', query: {
      'uid': uid,
      'count': '20',
      'unfollowing': '0',
      'max_id': cursor,
    });
    final parsed = parseChat(data);
    final messages = parsed.$1;
    return PageResult(messages, messages.length > 1 ? messages.last.id : null);
  }

  Future<PageResult<DirectMessage>> groupChat(String gid, String? cursor) async =>
      (await groupChatPage(gid, cursor)).messages;

  /// A page of group messages, and the group's title as that page carried it.
  ///
  /// The title is `群名(828)` — the only thing m.weibo.cn says about a group itself, and enough to
  /// paint the chat's top bar. The group's full description, members and announcement come from
  /// weibo.com instead (see [groupInfo]).
  Future<({PageResult<DirectMessage> messages, String? title})> groupChatPage(String gid, String? cursor) async {
    final data = await _get('api/groupchat/list', query: {
      'gid': gid,
      'count': '20',
      'max_mid': cursor,
    });
    final messages = parseGroupChat(data);
    return (messages: PageResult(messages, messages.length > 1 ? messages.last.id : null), title: groupTitle(data));
  }

  /// The group's name and member count out of the title its message pages carry.
  ///
  /// Only used to paint the chat's top bar before weibo.com's own answer arrives; [groupInfo] is the
  /// real source.
  GroupInfo groupInfoFromTitle(String gid, String? title) {
    final split = splitGroupTitle(title ?? '');
    return GroupInfo(gid: gid, name: split.name, memberCount: split.count);
  }

  Future<void> sendMessage(String uid, String content) async {
    await _post('api/chat/send', {
      'uid': uid,
      'content': content,
    }, referer: '${WeiboApi._web}/message/chat?uid=$uid');
  }

  Future<void> sendGroupMessage(String gid, String content) async {
    await _post('api/groupchat/send', {
      'gid': gid,
      'content': content,
    }, referer: '${WeiboApi._web}/message/chat?gid=$gid');
  }

  Future<String> uploadChatImage(File file, ChatTarget target) async {
    final data = await _postMultipart(
      'api/chat/upload',
      fields: {
        if (target.isGroup) 'tochatid': target.id else 'tuid': target.id,
      },
      fileField: 'file',
      file: file,
      referer: '${WeiboApi._web}/message/chat?${target.isGroup ? 'gid' : 'uid'}=${target.id}',
    );
    final fids = textOf(asMap(data)?['fids']);
    if (fids == null || fids.isEmpty) throw ApiException('图片上传失败');
    return fids;
  }

  Future<void> sendChatImage(ChatTarget target, String fids) async {
    final path = target.isGroup ? 'api/groupchat/send' : 'api/chat/send';
    final key = target.isGroup ? 'gid' : 'uid';
    await _post(path, {
      key: target.id,
      'media_type': '1',
      'fids': fids,
    }, referer: '${WeiboApi._web}/message/chat?$key=${target.id}');
  }

  /// The path really is "quite" (a typo in Weibo's own API); do not correct it.
  Future<void> leaveGroup(String gid) async {
    await _post('api/groupchat/quite', {'gid': gid},
        referer: '${WeiboApi._web}/message/chat?gid=$gid');
  }

  // ---- relationships and people -------------------------------------------------------------
}
