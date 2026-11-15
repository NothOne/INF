import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'native.dart';
import 'parse.dart';

/// TEMPORARY — probes the weibo.com group-chat backend at api.weibo.com.
///
/// The web chat's bundles name these endpoints; this finds out what they answer for a signed-in
/// account, with the weibo.com cookies the login already planted. Writes to a file under the app's
/// external directory, which adb can read without touching anything private.
class GroupProbe {
  GroupProbe._();

  static final _lines = <String>[];

  static void _log(String line) {
    _lines.add(line);
    debugPrint('INF-PROBE $line');
  }

  static Future<void> run(String gid) async {
    try {
      await _run(gid);
    } catch (error) {
      _log('fatal $error');
    }
    await _flush();
  }

  static Future<void> _flush() async {
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationSupportDirectory();
      final file = File('${dir.path}/inf-webim-probe.txt');
      await file.writeAsString(_lines.join('\n'));
    } catch (error) {
      debugPrint('INF-PROBE flush failed $error');
    }
  }

  static Future<void> _run(String gid) async {
    final cookie = await Native.getCookies('https://weibo.com/') ?? '';
    _log('cookie len=${cookie.length}');
    final names = cookie.split(';').map((part) => part.split('=').first.trim()).where((n) => n.isNotEmpty).toList();
    _log('cookie names=$names');
    final xsrf = RegExp(r'(?:^|;\s*)XSRF-TOKEN=([^;]+)').firstMatch(cookie)?.group(1);
    _log('xsrf=${xsrf == null ? 'none' : 'present'}');

    final probes = <String, Map<String, String>>{
      'webim/groupchat/query.json': {'gid': gid},
      'webim/query_group.json': {
        'gid': gid,
        'is_pc': '1',
        'query_member': '1',
        'sort_by_jp': '1',
        'query_member_count': '50',
      },
      'webim/groupchat/query_nick.json': {'gid': gid},
      'webim/groupchat/query_join_groups.json': {},
      'webim/groupchat/is_members.json': {'gid': gid},
      'webim/groupchat/query_fangroup_ability.json': {'gid': gid},
      'webim/2/notice_center/discussion_group/push_settings.json': {'call_from': 'mobile', 'gid': gid},
      'webim/groupchat/query_sys_messages.json': {'gid': gid},
    };
    for (final entry in probes.entries) {
      final body = await _get('https://api.weibo.com/${entry.key}', entry.value, cookie, xsrf);
      _log('${entry.key} → ${_clip(body, limit: 900)}');
      final json = _json(body);
      final data = asMap(asMap(json)?['data']);
      if (data != null) _log('${entry.key} data.keys=${data.keys.toList()}');
    }
  }

  static Future<dynamic> _get(String url, Map<String, String> query, String cookie, String? xsrf) async {
    try {
      final response = await Dio().get(
        url,
        queryParameters: query.isEmpty ? null : query,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          followRedirects: false,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36',
            'Referer': 'https://api.weibo.com/chat',
            'Accept': 'application/json, text/plain, */*',
            'Cookie': cookie,
            if (xsrf != null) 'X-XSRF-TOKEN': xsrf,
          },
        ),
      );
      return 'HTTP ${response.statusCode} ${response.data}';
    } on DioException catch (error) {
      return 'ERR ${error.type} ${error.message}';
    }
  }

  static dynamic _json(dynamic body) {
    if (body is! String) return null;
    final start = body.indexOf('{');
    if (start < 0) return null;
    try {
      return jsonDecode(body.substring(start));
    } catch (_) {
      return null;
    }
  }

  static String _clip(dynamic value, {int limit = 400}) {
    final text = value is String ? value : value.toString();
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    return flat.length <= limit ? flat : '${flat.substring(0, limit)}…';
  }
}
