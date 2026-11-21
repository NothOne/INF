import 'dart:math';

import 'native.dart';
import 'session.dart';

/// What a weibo.com request needs and an m.weibo.cn one does not: the cookie the WebView got when it
/// was signed in there, and an XSRF token that matches it.
///
/// This is deliberately small. It used to be a class that also carried a `Dio`, a JSON envelope and
/// a `post` helper — a second, unused copy of what `api.dart` already does for this domain, written
/// while splitting the file and then never called. What the app actually needs in one place is the
/// cookie pair; the requests themselves stay in `api.dart`, where `_getPublic` / `_postWeiboCom` and
/// their shared envelope already are.
class WeiboComSession {
  WeiboComSession._();
  static final WeiboComSession instance = WeiboComSession._();

  static final _random = Random();

  String _cachedCookie = '';
  bool _resetRegistered = false;

  /// The last `weibo.com` Cookie header read from the native cookie jar, for synchronous image and
  /// video headers (such as `upload.api.weibo.com/2/mss/msget`). Cleared on sign-out/account switch.
  String get cachedCookie => _cachedCookie;

  void _ensureResetHook() {
    if (_resetRegistered) return;
    _resetRegistered = true;
    Session.instance.registerAccountReset(() => _cachedCookie = '');
  }

  /// Whether [cookie] carries a signed-in weibo.com session (non-empty `SUB=`).
  static bool hasAuth(String cookie) => RegExp(r'(?:^|;\s*)SUB=[^;\s]+').hasMatch(cookie);

  /// The cookie header and its XSRF token.
  ///
  /// weibo.com sets the token on its first page load, which the WebView may never have made; the
  /// service only checks that the header and the cookie agree, so one is made up when it is missing.
  Future<(String, String)> cookie() async {
    _ensureResetHook();
    final header = await Native.getCookies('https://weibo.com/') ?? '';
    _cachedCookie = header;
    final xsrf = RegExp(r'(?:^|;\s*)XSRF-TOKEN=([^;]+)').firstMatch(header)?.group(1);
    if (xsrf != null) return (header, xsrf);
    final made = List.generate(24, (_) => _random.nextInt(36).toRadixString(36)).join();
    return ('$header; XSRF-TOKEN=$made', made);
  }
}
