import 'dart:convert';

import 'package:dio/dio.dart';

import 'api.dart' show ApiException, dioError;
import 'models.dart';
import 'parse.dart';
import 'weibo_com_session.dart';

/// The group chat backend: `api.weibo.com/webim/*`.
///
/// None of this exists on m.weibo.cn — every candidate there answered 404 or an empty page (see
/// `DEVLOG.md`). It speaks a different host, a different cookie (the weibo.com one, from the WebView
/// the passport login signed in) and a different error shape (`result: false` rather than `ok: 0`),
/// which is why it is its own class rather than a section of [WeiboApi]: mixing the two is how a
/// request ends up carrying the wrong cookie, and that has happened.
///
/// Two things are easy to get wrong and both were found on-device:
///  * The group's id goes in `id`, not `gid`. `gid` is answered with "invalid parameter".
///  * `query_group` wants `source`; without it the service says `appkey` is missing and answers
///    with an empty member list.
class GroupChatApi {
  GroupChatApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 30),
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ));

  static final GroupChatApi instance = GroupChatApi();

  /// This backend's own client: no m.weibo.cn interceptor, so a chat request cannot pick up that
  /// cookie. The cookie it does carry comes from [WeiboComSession].
  final Dio _dio;

  final WeiboComSession _session = WeiboComSession.instance;
  static const _source = '209678993';

  /// What the phone site calls a group: `api/groupchat/list`'s `gid` is this one's `id`.
  Future<Map<String, dynamic>> _call(String path, Map<String, String> query, {Map<String, String>? body}) async {
    final (header, xsrf) = await _session.cookie();
    try {
      final response = body == null
          ? await _dio.get(
              'https://api.weibo.com/webim/$path',
              queryParameters: query,
              options: Options(
                responseType: ResponseType.plain,
                headers: {'Referer': 'https://api.weibo.com/chat', 'Cookie': header, 'X-XSRF-TOKEN': xsrf},
              ),
            )
          : await _dio.post(
              'https://api.weibo.com/webim/$path',
              data: body,
              options: Options(
                contentType: Headers.formUrlEncodedContentType,
                responseType: ResponseType.plain,
                headers: {
                  'Referer': 'https://api.weibo.com/chat',
                  'Origin': 'https://api.weibo.com',
                  'Cookie': header,
                  'X-XSRF-TOKEN': xsrf,
                },
              ),
            );
      final map = asMap(response.data is String ? _jsonOrNull(response.data) : response.data);
      if (map == null) throw ApiException('接口返回格式错误');
      // This service says `result: false`; it never says `ok: 0`.
      if (map['result'] == false || map['error'] != null) {
        throw ApiException(textOf(map['error']) ?? '群聊接口拒绝了这个请求');
      }
      return map;
    } on DioException catch (error) {
      throw dioError(error);
    }
  }

  static dynamic _jsonOrNull(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// A group's own page: its name, size, owner, admins and announcement.
  ///
  /// The announcement is inside this answer (`bulletin.content`), so it needs no request of its own —
  /// which is just as well, because there is no announcement endpoint.
  Future<GroupInfo> groupInfo(String gid) async {
    final map = await _call('groupchat/query.json', {'id': gid});
    final bulletin = asMap(map['bulletin']);
    final admins = [for (final id in asList(map['admins'])) idOf(id) ?? ''].where((id) => id.isNotEmpty).toSet();
    return GroupInfo(
      gid: gid,
      name: textOf(map['name']) ?? textOf(map['system_name']) ?? '',
      memberCount: intOf(map['member_count']) ?? 0,
      maxMembers: intOf(map['max_member']) ?? 0,
      ownerId: idOf(map['owner']) ?? '',
      adminIds: admins,
      notice: parseGroupNotice(bulletin?['content']),
      createdAt: intOf(map['create_time']),
      place: textOf(asMap(map['position'])?['name']),
    );
  }

  /// The group's members.
  ///
  /// The service hands these out in pages of its own size (`query_member_count`). The answer carries
  /// a `members` array beside `member_infos`; both are read, because which one is populated has
  /// varied between answers. There is no cursor in the answer, so a page that comes back shorter
  /// than asked for is the last one.
  Future<List<GroupMember>> groupMembers(String gid, {int offset = 0, int count = 50}) async {
    final map = await _call('query_group.json', {
      'id': gid,
      'source': _source,
      'is_pc': '1',
      'query_member': '1',
      'query_member_count': '$count',
      if (offset > 0) 'member_offset': '$offset',
      'sort_by_jp': '1',
    });
    return parseGroupMembers(map);
  }

  /// Whether this group's messages are muted for the account.
  ///
  /// `switch` is 1 for muted and 2 for not — not the 0/1 that the name suggests, which is why it is
  /// read explicitly rather than tested for truthiness.
  Future<bool> groupMuted(String gid) async {
    final map = await _call('2/notice_center/discussion_group/push_settings.json', {
      'call_from': 'mobile',
      'dgid': gid,
    });
    return intOf(map['switch']) == 1;
  }

  Future<void> setGroupMuted(String gid, bool muted) async {
    await _call('2/notice_center/discussion_group/set_push_settings.json', const {}, body: {
      'dgid': gid,
      'switch': muted ? '1' : '2',
      'call_from': 'mobile',
    });
  }

  /// Posts the group's announcement. Only the owner and admins may, and the service refuses quietly
  /// otherwise, so the caller shows the error rather than assuming it worked.
  Future<void> setGroupNotice(String gid, String notice) async {
    await _call('groupchat/send_bulletin.json', const {}, body: {
      'id': gid,
      'content': notice,
      'keep_time': '8640000',
    });
  }
}
