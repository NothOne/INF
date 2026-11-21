import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'api.dart' show ApiException, dioError;
import 'models.dart';
import 'parse.dart';
import 'session.dart';
import 'weibo_com_session.dart';

/// The group chat backend: `api.weibo.com/webim/*` (plus its MSS attachment hosts).
///
/// None of this exists on m.weibo.cn — every candidate there answered 404 or an empty page (see
/// `DEVLOG.md`). It speaks a different host, a different cookie (the weibo.com one, from the WebView
/// the passport login signed in) and a different error shape (`result: false` rather than `ok: 0`),
/// which is why it is its own class rather than a section of [WeiboApi]: mixing the two is how a
/// request ends up carrying the wrong cookie, and that has happened.
///
/// Facts verified against `api.weibo.com/chat/`'s web client bundle:
///  * The group's id goes in `id`, not `gid`. `gid` is answered with "invalid parameter".
///  * Every `webim/*` request carries `source=209678993` (in query on GET, form body on POST).
///  * `query_group.json` returns all members in one shot when passed `query_all_member=1` and
///    `query_member_count=5000` (it does not support `member_offset` pagination).
class GroupChatApi {
  GroupChatApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              sendTimeout: const Duration(seconds: 60),
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ));

  static final GroupChatApi instance = GroupChatApi();

  /// This backend's own client: no m.weibo.cn interceptor, so a chat request cannot pick up that
  /// cookie. The cookie it does carry comes from [WeiboComSession].
  final Dio _dio;

  final WeiboComSession _session = WeiboComSession.instance;
  static const _source = '209678993';
  static const _maxVideoBytes = 104857600; // 100 MB, matching webchat's limit.
  static const _maxVideoSeconds = 300; // 5 minutes, matching webchat's limit.
  static const _metaCacheLimit = 200;

  static final String _clientId =
      List.generate(16, (_) => Random().nextInt(36).toRadixString(36)).join();

  final Map<String, Future<ChatMediaMeta?>> _metaCache = {};
  bool _resetRegistered = false;

  void _ensureResetHook() {
    if (_resetRegistered) return;
    _resetRegistered = true;
    Session.instance.registerAccountReset(_metaCache.clear);
  }

  /// What the phone site calls a group: `api/groupchat/list`'s `gid` is this one's `id`.
  Future<Map<String, dynamic>> _call(String path, Map<String, String> query, {Map<String, String>? body}) async {
    final (header, xsrf) = await _session.cookie();
    final fullQuery = <String, String>{
      ...query,
      if (body == null) ...{
        'source': _source,
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    };
    final fullBody = body == null
        ? null
        : <String, String>{
            ...body,
            'source': _source,
          };
    try {
      final response = fullBody == null
          ? await _dio.get(
              'https://api.weibo.com/webim/$path',
              queryParameters: fullQuery,
              options: Options(
                responseType: ResponseType.plain,
                headers: {'Referer': 'https://api.weibo.com/chat', 'Cookie': header, 'X-XSRF-TOKEN': xsrf},
              ),
            )
          : await _dio.post(
              'https://api.weibo.com/webim/$path',
              queryParameters: fullQuery.isEmpty ? null : fullQuery,
              data: fullBody,
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

  /// A group's own page: its name, size, owner, admins and announcement (`bulletin`).
  Future<GroupInfo> groupInfo(String gid) async {
    final map = await _call('groupchat/query.json', {'id': gid});
    return parseGroupInfo(gid, map);
  }

  /// Full group query from `api.weibo.com/webim/query_group.json`: returns both [GroupInfo]
  /// (including `bulletin` and `summary`) and members up to [memberCount].
  ///
  /// Matches pcweibochat's two call shapes: without `query_all_member`/`group_ts` for full group
  /// metadata and bulletin, and with both flags to pull the complete member roster.
  Future<({GroupInfo info, List<GroupMember> members})> queryGroup(
    String gid, {
    bool allMembers = true,
    int memberCount = 5000,
  }) async {
    final map = await _call('query_group.json', {
      'id': gid,
      'is_pc': '1',
      'query_member': '1',
      'query_member_count': '$memberCount',
      'sort_by_jp': '1',
      if (allMembers) ...{
        'query_all_member': '1',
        'group_ts': '${DateTime.now().millisecondsSinceEpoch}',
      },
    });
    return (info: parseGroupInfo(gid, map), members: parseGroupMembers(map));
  }

  /// All members of a group via `query_group.json` with `query_all_member=1`.
  Future<List<GroupMember>> groupMembers(String gid, {int count = 5000}) async {
    final result = await queryGroup(gid, allMembers: true, memberCount: count);
    return result.members;
  }

  /// A page of group messages from `api.weibo.com/webim/groupchat/query_messages.json`.
  ///
  /// Unlike m.weibo.cn's `api/groupchat/list`, this carries attachment `fids`, `live_photo_video_fid`,
  /// `ext_text.video_pic_fid`, `pic_infos`, and inline `url_objects`.
  Future<PageResult<DirectMessage>> groupMessages(String gid, {String? maxMid, int count = 20}) async {
    final map = await _call('groupchat/query_messages.json', {
      'id': gid,
      'count': '$count',
      'convert_emoji': '1',
      'query_sender': '1',
      if (maxMid != null && maxMid.isNotEmpty) 'max_mid': maxMid,
    });
    return parseWebimGroupMessages(map, requestedCount: count);
  }

  /// Metadata for a chat attachment `fid` (dimensions, thumbnail, video duration, transcoded fid).
  ///
  /// Cached per session so scrolling does not re-query the same attachment.
  Future<ChatMediaMeta?> mediaMeta(String fid) {
    _ensureResetHook();
    final existing = _metaCache.remove(fid);
    if (existing != null) {
      _metaCache[fid] = existing;
      return existing;
    }
    final future = _fetchMediaMeta(fid);
    _metaCache[fid] = future;
    if (_metaCache.length > _metaCacheLimit) _metaCache.remove(_metaCache.keys.first);
    return future;
  }

  Future<ChatMediaMeta?> _fetchMediaMeta(String fid) async {
    final (header, _) = await _session.cookie();
    if (!WeiboComSession.hasAuth(header)) {
      _metaCache.remove(fid);
      return null;
    }
    Future<Map<String, dynamic>?> query({bool replace = false}) async {
      final resp = await _dio.get(
        'https://upload.api.weibo.com/2/mss/meta_query.json',
        queryParameters: {
          'source': _source,
          'fid': fid,
          if (replace) 'replace': 'true',
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Referer': 'https://api.weibo.com/chat', 'Cookie': header},
        ),
      );
      return asMap(resp.data is String ? _jsonOrNull(resp.data) : resp.data);
    }

    try {
      var map = await query();
      if (map == null) {
        _metaCache.remove(fid);
        return null;
      }
      if (textOf(map['extension'])?.toLowerCase() == 'mp4') {
        map = await query(replace: true) ?? map;
      }
      return parseChatMediaMeta(map, fallbackFid: fid);
    } catch (_) {
      _metaCache.remove(fid);
      return null;
    }
  }

  /// Uploads an image via `webim/uploadx.json` and sends it to a group chat.
  Future<void> uploadAndSendImage(
    String gid,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final (header, xsrf) = await _session.cookie();
    if (!WeiboComSession.hasAuth(header)) {
      throw ApiException('发送群聊图片需要 weibo.com 登录态，请重新登录');
    }
    final name = file.path.split(Platform.pathSeparator).last;
    onProgress?.call(0.1);
    final Map<String, dynamic>? uploadMap;
    try {
      final form = FormData.fromMap({
        'blob': await MultipartFile.fromFile(file.path, filename: name),
      });
      final uploadPath = 'uploadx.json';
      final response = await _dio.post(
        'https://api.weibo.com/webim/$uploadPath',
        queryParameters: {'source': _source, 'gid': gid},
        data: form,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(0.1 + 0.75 * (sent / total).clamp(0.0, 1.0));
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://api.weibo.com/chat',
            'Origin': 'https://api.weibo.com',
            'Cookie': header,
            'X-XSRF-TOKEN': xsrf,
          },
        ),
      );
      uploadMap = asMap(response.data is String ? _jsonOrNull(response.data) : response.data);
    } on DioException catch (error) {
      throw dioError(error);
    }
    final fid = idOf(uploadMap?['fid']);
    if (fid == null || fid.isEmpty) {
      throw ApiException(textOf(uploadMap?['error']) ?? '图片上传失败');
    }
    onProgress?.call(0.9);
    await _call('groupchat/send_message.json', const {}, body: {
      'id': gid,
      'fids': fid,
      'content': '分享图片',
      'media_type': '1',
      'return_detail': '1',
      'annotations': jsonEncode({'webchat': 1, 'clientid': _clientId}),
    });
    onProgress?.call(1.0);
  }

  /// Uploads a local video through `api.weibo.com/chat/`'s chunked multimedia pipeline
  /// (`2/multimedia/init.json` → `up.video.weibocdn.com/2/multimedia/upload.json` →
  /// `2/mss/query_video_trans.json` for first-frame cover → `groupchat/send_message.json`).
  Future<void> uploadAndSendVideo(
    String gid,
    File file, {
    int width = 0,
    int height = 0,
    int durationSec = 0,
    void Function(double progress)? onProgress,
  }) async {
    final (header, _) = await _session.cookie();
    if (!WeiboComSession.hasAuth(header)) {
      throw ApiException('发送视频需要 weibo.com 登录态，请重新登录');
    }
    final size = await file.length();
    if (size <= 0) throw ApiException('视频文件为空');
    if (size >= _maxVideoBytes) throw ApiException('视频不能大于 100 MB');
    if (durationSec >= _maxVideoSeconds) throw ApiException('视频不能大于 5 分钟');

    onProgress?.call(0.05);
    final fileMd5 = (await md5.bind(file.openRead()).first).toString();
    final name = file.path.split(Platform.pathSeparator).last;

    // 1. Init upload session.
    final initMap = await _call('2/multimedia/init.json', const {}, body: {
      'extprops': jsonEncode({'uploadType': 3, 'recipientId': gid}),
      'length': '$size',
      'name': name,
      'type': 'dm_attachment_video',
      'md5': fileMd5,
      'check': fileMd5,
      'mediaprops': jsonEncode({
        'raw_md5': fileMd5,
        'video_type': 'dm_video',
        'screenshot': 1,
        'width': width,
        'height': height,
        'duration': durationSec,
        'dm_video_props': {'togid': gid, 'touid': 0, 'gid': 0},
      }),
    });
    final fileToken = textOf(initMap['fileToken']);
    final auth = textOf(initMap['auth']);
    final chunkKb = intOf(initMap['length']) ?? 256;
    if (fileToken == null || fileToken.isEmpty || auth == null || auth.isEmpty) {
      throw ApiException(textOf(initMap['error']) ?? '初始化视频上传失败');
    }
    final chunkSize = (chunkKb > 0 ? chunkKb : 256) * 1024;
    final totalChunks = (size + chunkSize - 1) ~/ chunkSize;
    onProgress?.call(0.10);

    // 2. Upload chunks sequentially with per-chunk MD5 verification.
    String? videoFid;
    final raf = await file.open();
    try {
      for (var index = 0; index < totalChunks; index++) {
        final offset = index * chunkSize;
        final length = (size - offset) < chunkSize ? (size - offset) : chunkSize;
        await raf.setPosition(offset);
        final bytes = await raf.read(length);
        final chunkMd5 = md5.convert(bytes).toString();
        final Map<String, dynamic>? chunkResp;
        try {
          final resp = await _dio.post(
            'https://up.video.weibocdn.com/2/multimedia/upload.json',
            queryParameters: {
              'source': _source,
              'filetoken': fileToken,
              'startloc': '$offset',
              'selectId': gid,
              'check': fileMd5,
              'sectioncheck': chunkMd5,
              'name': name,
              'chunk': '$index',
              'chunks': '$totalChunks',
            },
            data: Stream.fromIterable([bytes]),
            options: Options(
              contentType: DioMediaType('application', 'octet-stream').toString(),
              responseType: ResponseType.plain,
              headers: {
                'X-Up-Auth': auth,
                'Origin': 'https://api.weibo.com',
                'Referer': 'https://api.weibo.com/chat',
                Headers.contentLengthHeader: bytes.length,
              },
            ),
          );
          chunkResp = asMap(resp.data is String ? _jsonOrNull(resp.data) : resp.data);
        } on DioException catch (error) {
          throw dioError(error);
        }
        if (chunkResp?['error'] != null) {
          throw ApiException(textOf(chunkResp?['error']) ?? '视频分片上传失败');
        }
        final fid = idOf(chunkResp?['fid']);
        if (fid != null && fid.isNotEmpty) videoFid = fid;
        onProgress?.call(0.10 + 0.75 * ((index + 1) / totalChunks));
      }
    } finally {
      await raf.close();
    }
    if (videoFid == null || videoFid.isEmpty) {
      throw ApiException('视频上传未返回文件标识');
    }

    // 3. Poll briefly for server-extracted first-frame cover fid (optional, matching webchat's 5s window).
    String coverFid = '';
    for (var attempt = 0; attempt < 8; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final trans = await _call('2/mss/query_video_trans.json', {'fid': videoFid});
        final found = idOf(asMap(trans['msg'])?['firstFrameFId']);
        if (found != null && found.isNotEmpty) {
          coverFid = found;
          break;
        }
      } catch (_) {
        break;
      }
    }
    onProgress?.call(0.92);

    // 4. Send the group message.
    await _call('groupchat/send_message.json', const {}, body: {
      'id': gid,
      'fids': videoFid,
      'content': '分享视频',
      'media_type': '10',
      'return_detail': '1',
      'annotations': jsonEncode({
        'video_pic_fid': coverFid,
        'webchat': 1,
        'clientid': _clientId,
      }),
    });
    onProgress?.call(1.0);
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

  /// Posts or clears the group's announcement. Only the owner and admins may, and the service
  /// refuses otherwise, so the caller shows the error rather than assuming it worked.
  Future<void> setGroupNotice(String gid, String notice, {String? scheme}) async {
    final trimmed = notice.trim();
    if (trimmed.isEmpty) {
      await _call('groupchat/delete_bulletin.json', const {}, body: {'id': gid});
      return;
    }
    final cleanScheme = scheme?.trim();
    await _call('groupchat/send_bulletin.json', const {}, body: {
      'id': gid,
      'content': trimmed,
      if (cleanScheme != null && cleanScheme.isNotEmpty) 'scheme': cleanScheme,
      'keep_time': '8640000',
    });
  }
}
