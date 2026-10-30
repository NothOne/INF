import 'package:flutter/foundation.dart';

import 'api.dart';
import 'native.dart';
import 'page_cache.dart';
import 'prefs.dart';

enum SessionState { checking, loggedOut, loggedIn, unreachable }

class WeiboConfig {
  final bool login;
  final String? uid;
  final String? st;
  const WeiboConfig({required this.login, this.uid, this.st});
}

/// Owns the cookie jar shared with the login WebView, and the one bit of state every screen cares
/// about: whether the user is signed in.
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const loginUrl =
      'https://passport.weibo.com/sso/signin?entry=wapsso&source=wapssowb&url=https%3A%2F%2Fm.weibo.cn%2F';

  final Map<String, String> cookies = {};
  String? uid;
  String? st;
  String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  SessionState state = SessionState.checking;
  String? unreachableMessage;

  int _revision = 0;
  int get revision => _revision;

  String get userAgent => _userAgent;
  String? get xsrf => cookies['XSRF-TOKEN'];

  String get cookieHeader => cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Whose cached pages to show: the signed-in account, or while the check is still running, the
  /// account that was signed in last time.
  String? get cacheScope => uid ?? (state == SessionState.checking ? Prefs.instance.lastUid : null);

  /// m.weibo.cn only trusts a signed-in SUB on `.weibo.cn`; the visitor system
  /// also sets one there (prefix `_2AkM`), so presence alone is not enough.
  bool get hasSignedInCookie {
    final sub = cookies['SUB'];
    return sub != null && sub.isNotEmpty && !sub.startsWith('_2AkM');
  }

  Future<void> init() async {
    // Do not block startup on WebView's user-agent query (it can take seconds).
    Native.userAgent().then((agent) {
      if (agent != null && agent.isNotEmpty) _userAgent = agent;
    }).catchError((_) {});
    await reloadCookies();
  }

  /// Mirrors exactly what the WebView would send to m.weibo.cn. Cookies on
  /// weibo.com / sina.com.cn / passport hosts are not accepted by m.weibo.cn,
  /// so they must not be mixed in.
  Future<void> reloadCookies() async {
    final header = await Native.getCookies('https://m.weibo.cn/');
    cookies
      ..clear()
      ..addAll(_parseCookieHeader(header));
    _revision++;
    notifyListeners();
  }

  Map<String, String> _parseCookieHeader(String header) {
    final result = <String, String>{};
    for (final part in header.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final index = trimmed.indexOf('=');
      if (index <= 0) continue;
      result[trimmed.substring(0, index)] = trimmed.substring(index + 1);
    }
    return result;
  }

  Future<SessionState> refresh() async {
    state = SessionState.checking;
    notifyListeners();
    await reloadCookies();

    try {
      final config = await WeiboApi.instance.config();
      if (config.st != null) st = config.st;
      if (config.login && config.uid != null && config.uid!.isNotEmpty) {
        uid = config.uid;
        state = SessionState.loggedIn;
        Prefs.instance.setLastUid(uid);
      } else {
        uid = null;
        state = SessionState.loggedOut;
      }
      unreachableMessage = null;
    } on LoginRequiredException {
      uid = null;
      state = SessionState.loggedOut;
    } catch (error) {
      uid = null;
      unreachableMessage = error is ApiException ? error.message : error.toString();
      state = SessionState.unreachable;
    }
    notifyListeners();
    return state;
  }

  void onLoginRequired() {
    if (state == SessionState.loggedOut) return;
    state = SessionState.loggedOut;
    uid = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await Native.clearCookies();
    await Prefs.instance.setLastUid(null);
    await PageCache.instance.clear();
    cookies.clear();
    uid = null;
    st = null;
    state = SessionState.loggedOut;
    _revision++;
    notifyListeners();
  }

  Future<void> setCookieForDebug(String rawCookie) async {
    for (final part in rawCookie.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      await Native.setCookie(trimmed);
    }
    await reloadCookies();
  }
}
