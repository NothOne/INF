import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'emoji.dart';
import 'cached_page.dart';
import 'models.dart';
import 'native.dart';
import 'parse.dart';
import 'prefs.dart';
import 'session.dart';
import 'weibo_com_session.dart';

part 'api_feeds.dart';
part 'api_statuses.dart';
part 'api_weibo_com.dart';
part 'api_search_topic.dart';
part 'api_notify_message.dart';
part 'api_relations.dart';
part 'api_comments.dart';
part 'api_writes.dart';

class LoginRequiredException implements Exception {
  final String? loginUrl;

  /// The answer was not JSON. A signed-out client gets the passport page here, but so does one
  /// caught by risk control or a captive portal, so this alone does not prove the session ended.
  final bool unparsable;
  LoginRequiredException([this.loginUrl, this.unparsable = false]);
  @override
  String toString() => '需要登录微博';
}

class ApiException implements Exception {
  final String message;
  final int? code;

  /// Set where the transport already knows what went wrong, so [Failure.from] does not have to
  /// re-derive it from the message. Null for everything thrown by a caller, which leaves the
  /// classification to the envelope's code and wording.
  final FailureKind? kind;

  ApiException(this.message, {this.code, this.kind});

  @override
  String toString() => message;
}

/// What the transport can tell about a failure without guessing: it never reached the service, or
/// the service answered something that is not the shape this app reads.
enum FailureKind { network, parse }

/// A write Weibo will take only after its captcha; [captchaId] is what the puzzle is issued for.
class CaptchaRequiredException extends ApiException {
  final String captchaId;
  CaptchaRequiredException(super.message, {required this.captchaId});
}

/// Shared Dio transport error mapping used across m.weibo.cn, weibo.com, and api.weibo.com.
Exception dioError(DioException error) {
  final type = error.type;
  if (type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout) {
    return ApiException('网络连接超时', kind: FailureKind.network);
  }
  if (type == DioExceptionType.connectionError || type == DioExceptionType.badCertificate) {
    return ApiException('网络连接失败', kind: FailureKind.network);
  }
  return ApiException(error.message ?? '网络请求失败', kind: FailureKind.network);
}

/// Calls the JSON endpoints used by m.weibo.cn, with the same paths, parameters and headers the
/// Compose app verified on-device. Only the HTTP engine changed (OkHttp -> Dio).
class WeiboApi {
  WeiboApi._(this.session)
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://m.weibo.cn',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 30),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        )),
        _publicDio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 30),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final headers = options.headers;
        headers['User-Agent'] = session.userAgent;
        headers['Accept'] = 'application/json, text/plain, */*';
        headers['X-Requested-With'] = 'XMLHttpRequest';
        headers['MWeibo-Pwa'] = '1';
        headers.putIfAbsent('Referer', () => '$_web/');
        if (session.cookieHeader.isNotEmpty && options.uri.host == 'm.weibo.cn') {
          headers['Cookie'] = session.cookieHeader;
        }
        if (options.method != 'GET' && session.xsrf != null) {
          headers.putIfAbsent('X-XSRF-TOKEN', () => session.xsrf!);
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final setCookies = response.headers.map['set-cookie'];
        if (setCookies != null && response.requestOptions.uri.host == 'm.weibo.cn') {
          session.absorbSetCookies(setCookies);
        }
        handler.next(response);
      },
    ));
    // Non-m.weibo.cn hosts (weibo.com, passport, m.s.weibo.com) use a separate Dio with no
    // m.weibo.cn cookie/XSRF/PWA interceptor so credentials and site headers never leak across hosts.
    _publicDio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final headers = options.headers;
        headers.putIfAbsent('User-Agent', () => session.userAgent);
        headers.putIfAbsent('Accept', () => 'application/json, text/plain, */*');
        handler.next(options);
      },
    ));
  }

  static final WeiboApi instance = WeiboApi._(Session.instance);
  static const _web = 'https://m.weibo.cn';

  final Session session;
  final Dio _dio;
  final Dio _publicDio;

  Future<WeiboConfig> config() async {
    final data = await _get('api/config');
    final json = asMap(data);
    final config = WeiboConfig(
      login: json?['login'] == true,
      uid: idOf(json?['uid']),
      st: textOf(json?['st']),
    );
    if (config.st != null) session.st = config.st;
    return config;
  }

  // ---- feeds --------------------------------------------------------------------------------

  PageResult<Status> _parseFeed(FeedKind kind, dynamic data, int page) => switch (kind) {
        FeedKind.all ||
        FeedKind.followingAll ||
        FeedKind.special ||
        FeedKind.group ||
        FeedKind.circle ||
        FeedKind.private =>
          parseFriendsFeed(data),
        _ => parseContainerStatuses(data, page),
      };

  Future<dynamic> _listFeed(String path, String? cursor, [Map<String, dynamic>? params]) =>
      _get(path, query: {...?params, 'max_id': cursor}, emptyIsOk: true);

  Future<dynamic> _cardFeed(String containerId, int page) => _get(
        'api/container/getIndex',
        query: {
          'containerid': containerId,
          if (page > 1) 'page': page.toString(),
        },
        emptyIsOk: true,
      );

  // ---- statuses -----------------------------------------------------------------------------

  /// weibo.com's `profile/feature` hands a visitor m.weibo.cn's profile containers, paged by number.
  Future<PageResult<Status>> _profileContainer(String uid, String containerId, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await _asVisitor((cookie) => _getPublic(
          'https://weibo.com/ajax/profile/feature',
          query: {'containerid': containerId, if (page > 1) 'page': '$page'},
          referer: 'https://weibo.com/u/$uid',
          cookie: cookie,
        ));
    return parseContainerStatuses(data, page);
  }

  /// A weibo.com request behind the visitor wall; a refused or [accept]-failing answer gets one
  /// more try with a new visitor cookie.
  Future<T> _asVisitor<T>(Future<T> Function(String cookie) request, {bool Function(T result)? accept}) async {
    for (var attempt = 0;; attempt++) {
      try {
        final result = await request(await _visitorCookie());
        if (attempt > 0 || (accept?.call(result) ?? true)) return result;
      } catch (_) {
        if (attempt > 0) rethrow;
      }
      _visitor = null;
    }
  }

  Future<String>? _visitor;

  Future<String> _visitorCookie() => _visitor ??= _newVisitor()..catchError((_) {
        _visitor = null;
        return '';
      });

  /// passport.weibo.com hands any client an anonymous SUB/SUBP pair, wrapped in a JSONP callback.
  Future<String> _newVisitor() async {
    final response = await _publicDio.post<String>(
      'https://passport.weibo.com/visitor/genvisitor2',
      data: {'cb': 'visitor_gray_callback', 'tid': '', 'from': 'weibo'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        headers: {'Referer': 'https://passport.weibo.com/visitor/visitor'},
      ),
    );
    final body = response.data ?? '';
    final start = body.indexOf('(');
    final end = body.lastIndexOf(')');
    if (start < 0 || end <= start) throw ApiException('游客身份获取失败');
    final data = asMap(asMap(jsonDecode(body.substring(start + 1, end)))?['data']);
    final sub = textOf(data?['sub']);
    if (sub == null || sub.isEmpty) throw ApiException('游客身份获取失败');
    return 'SUB=$sub; SUBP=${textOf(data?['subp']) ?? ''}';
  }

  Future<dynamic> _searchPage(String query, int type, int page) => _get(
        'api/container/getIndex',
        query: {
          'containerid': '100103type=$type&q=$query',
          'page_type': 'searchall',
          if (page > 1) 'page': page.toString(),
        },
        emptyIsOk: true,
      );

  /// m.s.weibo.com only answers its own topic page.
  String _vtopic(String topic) => 'https://m.s.weibo.com/vtopic/detail_new?q=${Uri.encodeQueryComponent(topic)}';

  Future<PageResult<Status>> _containerStatuses(String containerId, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await _get(
      'api/container/getIndex',
      query: {
        'containerid': containerId,
        'page_type': 'searchall',
        if (page > 1) 'page': page.toString(),
      },
    );
    return parseContainerStatuses(data, page);
  }

  // ---- notifications and messages -----------------------------------------------------------

  Future<dynamic> _get(
    String path, {
    Map<String, dynamic>? query,
    bool emptyIsOk = false,
    String? referer,
    bool returnRoot = false,
  }) async {
    try {
      final params = <String, String>{};
      query?.forEach((key, value) {
        if (value != null) params[key] = value.toString();
      });
      final response = await _dio.get(
        '/$path',
        queryParameters: params.isEmpty ? null : params,
        options: Options(headers: referer == null ? null : {'Referer': referer}),
      );
      return _decodeEnvelope(response, emptyIsOk, returnRoot: returnRoot);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  /// An anonymous weibo.com endpoint: no m.weibo.cn cookie, and a refusal is just an error, never
  /// a sign the session ended.
  /// [whole] is for the endpoints that answer without a `data` wrapper.
  Future<dynamic> _getPublic(
    String url, {
    Map<String, String>? query,
    String? referer,
    String? cookie,
    String? xsrf,
    bool whole = false,
  }) async {
    try {
      final response = await _publicDio.get(
        url,
        queryParameters: query,
        options: Options(headers: {
          'Referer': referer ?? 'https://weibo.com/',
          'Cookie': ?cookie,
          'X-XSRF-TOKEN': ?xsrf,
        }),
      );
      return _publicEnvelope(response, whole);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  dynamic _publicEnvelope(Response response, bool whole) {
    final status = response.statusCode ?? 0;
    if (status >= 400) throw ApiException('HTTP $status');
    final body = response.data;
    final Map<String, dynamic>? map;
    try {
      map = asMap(body is String ? jsonDecode(body) : body);
    } on FormatException {
      throw ApiException('接口返回格式错误', kind: FailureKind.parse);
    }
    // weibo.com answers {ok: 1}, m.s.weibo.com {code: "100000"}; passport's {retcode} is read
    // by its parser, since a QR code still waiting for its scan is an answer too.
    if (map != null && intOf(map['ok']) == -100) {
      throw LoginRequiredException(textOf(map['url']));
    }
    final passport = map != null && map.containsKey('retcode');
    if (map == null || (!passport && intOf(map['ok']) != 1 && textOf(map['code']) != '100000')) {
      throw ApiException(
        textOf(map?['msg']) ?? textOf(map?['message']) ?? textOf(map?['error']) ?? '接口返回格式错误',
      );
    }
    return whole ? map : map['data'];
  }

  /// weibo.com as the signed-in account: the WebView's weibo.com cookies, which the passport
  /// login set alongside m.weibo.cn's.
  Future<dynamic> _getWeiboCom(
    String path,
    Map<String, String> query, {
    required String referer,
    bool whole = false,
  }) async {
    final (cookie, xsrf) = await WeiboComSession.instance.cookie();
    return _getPublic(
      'https://weibo.com/ajax/$path',
      query: query,
      referer: referer,
      cookie: cookie,
      xsrf: xsrf,
      whole: whole,
    );
  }

  /// Uses the signed-in weibo.com cookie when present, otherwise falls back to a visitor cookie.
  Future<T> _getWeiboComOrVisitor<T>(
    Future<T> Function(String cookie, String? xsrf) request, {
    bool Function(T value)? accept,
  }) async {
    final (cookie, xsrf) = await WeiboComSession.instance.cookie();
    if (WeiboComSession.hasAuth(cookie)) {
      try {
        final value = await request(cookie, xsrf);
        if (accept == null || accept(value)) return value;
      } catch (_) {}
    }
    return _asVisitor((visitorCookie) => request(visitorCookie, null), accept: accept);
  }

  /// weibo.com's JSON writes check `X-XSRF-TOKEN` against the `XSRF-TOKEN` cookie.
  Future<dynamic> _postWeiboCom(String path, Map<String, Object> body, {required String referer}) async {
    final (cookie, xsrf) = await WeiboComSession.instance.cookie();
    try {
      final response = await _publicDio.post(
        'https://weibo.com/ajax/$path',
        data: jsonEncode(body),
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {
            'Referer': referer,
            'Origin': 'https://weibo.com',
            'X-Requested-With': 'XMLHttpRequest',
            'Cookie': cookie,
            'X-XSRF-TOKEN': xsrf,
          },
        ),
      );
      return _publicEnvelope(response, true);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  /// weibo.com's form-encoded writes (`statuses/update`, `statuses/normal_repost`, etc.).
  Future<dynamic> _postWeiboComForm(
    String path,
    Map<String, String> fields, {
    required String referer,
  }) async {
    final (cookie, xsrf) = await WeiboComSession.instance.cookie();
    try {
      final response = await _publicDio.post(
        'https://weibo.com/ajax/$path',
        data: fields,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Referer': referer,
            'Origin': 'https://weibo.com',
            'X-Requested-With': 'XMLHttpRequest',
            'Cookie': cookie,
            'X-XSRF-TOKEN': xsrf,
          },
        ),
      );
      return _publicEnvelope(response, true);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  /// Form POST to an anonymous public endpoint (such as `ai.s.weibo.com`) returning raw JSON.
  Future<dynamic> _postPublicForm(
    String url,
    Map<String, String> fields, {
    String? referer,
  }) async {
    try {
      final response = await _publicDio.post(
        url,
        data: fields,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Referer': ?referer},
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 400) throw ApiException('HTTP $status');
      final body = response.data;
      try {
        return body is String ? jsonDecode(body) : body;
      } on FormatException {
        throw ApiException('接口返回格式错误', kind: FailureKind.parse);
      }
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  /// The cookie header and its XSRF token. weibo.com sets the token on its first page load, which
  /// the WebView may never have made; it only has to match, so one is made up then.
  /// m.weibo.cn adds the screen size in CSS pixels to every post.
  String get _screen {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return 'screen:412x915';
    final size = view.physicalSize / view.devicePixelRatio;
    return 'screen:${size.width.round()}x${size.height.round()}';
  }

  /// Shows Weibo's captcha and completes with the fields to resend the refused write with, or
  /// null when the reader gave up. Set by the app, which owns the UI.
  static Future<Map<String, String>?> Function(String captchaId)? captchaSolver;

  Future<dynamic> _post(
    String path,
    Map<String, String?> fields, {
    String? referer,
  }) async {
    try {
      return await _postOnce(path, fields, referer: referer);
    } on CaptchaRequiredException catch (error) {
      final solve = captchaSolver;
      if (solve == null) rethrow;
      final passed = await solve(error.captchaId);
      if (passed == null) throw ApiException('没有完成安全验证，操作未执行');
      return _postOnce(path, {...fields, ...passed}, referer: referer);
    }
  }

  Future<dynamic> _postOnce(
    String path,
    Map<String, String?> fields, {
    String? referer,
  }) async {
    try {
      final st = await _token(refresh: true);
      final response = await _dio.post(
        '/$path',
        data: <String, String>{
          for (final entry in fields.entries)
            if (entry.value != null) entry.key: entry.value!,
          'st': st,
          '_spr': _screen,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-XSRF-TOKEN': st,
            'Origin': _web,
            'Referer': ?referer,
          },
        ),
      );
      return _decodeEnvelope(response, false);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  Future<dynamic> _postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    String? referer,
  }) async {
    try {
      final st = await _token(refresh: true);
      final response = await _dio.post(
        '/$path',
        data: FormData.fromMap({
          'st': st,
          ...fields,
          fileField: await MultipartFile.fromFile(
            file.path,
            filename: file.path.split(Platform.pathSeparator).last,
            contentType: DioMediaType.parse(_imageType(file.path)),
          ),
        }),
        options: Options(headers: {
          'X-XSRF-TOKEN': st,
          'Origin': _web,
          'Referer': ?referer,
        }),
      );
      return _decodeEnvelope(response, false);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  dynamic _decodeEnvelope(Response response, bool emptyIsOk, {bool returnRoot = false}) {
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      throw ApiException('HTTP $status');
    }
    final body = response.data;
    dynamic root;
    if (body is String) {
      try {
        root = jsonDecode(body);
      } catch (_) {
        throw LoginRequiredException(null, true);
      }
    } else {
      root = body;
    }
    final map = asMap(root);
    if (map == null) throw ApiException('接口返回格式错误', kind: FailureKind.parse);
    EmojiStore.instance.learn(collectEmoji(map));
    final envelope = parseWeiboResult(map);
    if (envelope.isOk) return returnRoot ? map : envelope.data;
    if (envelope.needsLogin) {
      session.onLoginRequired();
      throw LoginRequiredException(envelope.loginUrl);
    }
    final captchaId = textOf(map['extra']);
    if (envelope.ok == 0 && textOf(map['error_type']) == 'captcha' && captchaId != null) {
      throw CaptchaRequiredException(envelope.message ?? '需要完成安全验证', captchaId: captchaId);
    }
    final code = envelope.errno ?? envelope.ok;
    if (emptyIsOk && (code == 0 || code == 100011)) return null;
    throw ApiException(envelope.message ?? '微博接口错误（$code）', code: code);
  }

  Future<String>? _tokenInFlight;

  Future<String> _token({bool refresh = false}) async {
    if (!refresh && session.st != null && session.st!.isNotEmpty) return session.st!;
    return _tokenInFlight ??= _fetchToken().whenComplete(() => _tokenInFlight = null);
  }

  Future<String> _fetchToken() async {
    final config = await this.config();
    final token = config.st;
    if (token == null || token.isEmpty) throw LoginRequiredException(null);
    session.st = token;
    return token;
  }

  /// Downloads a public media file (such as a CDN video) without leaking m.weibo.cn auth cookies
  /// to third-party hosts, supporting cancellation when the caller leaves the screen.
  Future<void> downloadMedia(
    String url,
    String savePath, {
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final uri = Uri.tryParse(url);
    final isUploadWeibo = uri?.host == 'upload.api.weibo.com';
    final weiboCookie = isUploadWeibo ? (await WeiboComSession.instance.cookie()).$1 : '';
    final headers = <String, String>{
      'Referer': isUploadWeibo ? 'https://api.weibo.com/chat' : '$_web/',
      'User-Agent': session.userAgent,
      if (isUploadWeibo && weiboCookie.isNotEmpty)
        'Cookie': weiboCookie
      else if (uri?.host == 'm.weibo.cn' && session.cookieHeader.isNotEmpty)
        'Cookie': session.cookieHeader,
    };
    try {
      await _publicDio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        options: Options(
          headers: headers,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw _dioError(error);
    }
  }

  Exception _dioError(DioException error) => dioError(error);

  String _imageType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<PageResult<T>> _numberedPage<T>(
    String? cursor,
    Future<List<T>> Function(String page) fetch,
  ) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final items = await fetch(page.toString());
    return PageResult(items, items.isEmpty ? null : (page + 1).toString());
  }
}

/// The containerid for a topic search. A blank keyword asks for the hashtag stream; a keyword
/// switches to the space-separated AND search, the only way m.weibo.cn narrows a topic.
String topicQuery(String name, String? keyword) {
  final topic = name.trim().replaceAll('#', '');
  final needle = (keyword ?? '').trim().replaceAll('#', '');
  if (needle.isEmpty) return '231522type=1&t=10&q=#$topic#';
  return '231522type=1&t=10&q=$topic $needle';
}
