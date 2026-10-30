import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/haptics.dart';
import '../../core/native.dart';
import '../../core/session.dart';
import '../../core/widgets/web_view.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // The SSO chain (passport.weibo.com -> passport.weibo.cn second verify ->
  // login.sina.com.cn -> passport.*/sso/crossdomain -> m.weibo.cn) only writes
  // the signed-in `.weibo.cn` SUB on its last hop. Never redirect the WebView
  // mid-chain: interrupting any step leaves only a visitor SUB behind.
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white)
    ..setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) {
        if (mounted) setState(() => _progress = 0.15);
      },
      onProgress: (value) {
        if (mounted) setState(() => _progress = value / 100);
      },
      onPageFinished: (url) {
        if (mounted) {
          setState(() {
            _progress = 1;
            if (url.startsWith('https://') && !_skipped.contains(url)) _bridging = false;
          });
        }
        _onUrl(url);
      },
      onHttpError: (error) => _skipFailedCrossdomain(error.request?.uri.toString()),
      onWebResourceError: (error) {
        if (error.isForMainFrame ?? true) _skipFailedCrossdomain(error.url);
      },
      onUrlChange: (change) {
        final url = change.url;
        if (url != null) _onUrl(url);
      },
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        if (uri == null) return NavigationDecision.prevent;
        if (uri.scheme == 'http' || uri.scheme == 'https') return NavigationDecision.navigate;
        return NavigationDecision.prevent;
      },
    ));

  double _progress = 0;
  bool _checking = false;
  bool _finished = false;
  bool _bridging = false;
  final Set<String> _skipped = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Wait until WebViewWidget has created the native WebView before toggling
    // its cookie policy; the platform controller is lazy on Android.
    await WidgetsBinding.instance.endOfFrame;
    if (Session.instance.state == SessionState.loggedOut) {
      await Native.clearAuthCookies();
      await Session.instance.reloadCookies();
    }
    // WebView's default UA contains "; wv"; Sina's older SSO endpoint can
    // return a non-2xx page for it. Use a normal mobile Chrome UA.
    await _web.setUserAgent(
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
    );
    // The crossdomain hops set cookies for several registrable domains;
    // Android WebView defaults third-party cookies to off.
    try {
      final platform = _web.platform;
      if (platform is AndroidWebViewController) {
        await AndroidWebViewCookieManager(
          const PlatformWebViewCookieManagerCreationParams(),
        ).setAcceptThirdPartyCookies(platform, true);
      }
    } catch (_) {}
    await _web.loadRequest(Uri.parse(Session.loginUrl));
  }

  /// After SMS login, passport jumps to login.sina.com.cn/sso/v2/crossdomain,
  /// which can answer 403 with an empty body. Every hop carries its own ticket
  /// for the next one in `cdurl`, and a successful hop just 302s there with
  /// `&url=`; do that redirect ourselves so the `.weibo.cn` hop still runs.
  void _skipFailedCrossdomain(String? failedUrl) {
    final uri = Uri.tryParse(failedUrl ?? '');
    if (uri == null || !uri.path.endsWith('/crossdomain')) return;
    final next = uri.queryParameters['cdurl'];
    if (next == null || next.isEmpty || !_skipped.add(failedUrl!)) return;
    final target = uri.queryParameters['url'];
    final sep = next.contains('?') ? '&' : '?';
    final resolved = target == null ? next : '$next${sep}url=${Uri.encodeQueryComponent(target)}';
    if (Uri.tryParse(resolved)?.scheme != 'https') return;
    if (mounted) setState(() => _bridging = true);
    _web.loadRequest(Uri.parse(resolved));
  }

  void _onUrl(String url) {
    if (Uri.tryParse(url)?.host == 'm.weibo.cn') _check(manual: false);
  }

  Future<void> _check({required bool manual}) async {
    if (_checking || _finished) return;
    setState(() => _checking = true);
    var loggedIn = false;
    try {
      // CookieManager can lag the final redirect slightly; only spend a
      // network request once a signed-in SUB is actually visible.
      for (var attempt = 0; attempt < 4 && !loggedIn; attempt++) {
        if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 500));
        await Session.instance.reloadCookies();
        if (!Session.instance.hasSignedInCookie) continue;
        loggedIn = await Session.instance.refresh() == SessionState.loggedIn;
        if (!loggedIn) break;
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (loggedIn) {
      _finished = true;
      Haptic.success.play();
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('登录成功')));
    } else if (manual) {
      Haptic.error.play();
      messenger.showSnackBar(const SnackBar(content: Text('还没有检测到登录，请先在网页中完成登录和验证')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: const Text('登录微博'),
          actions: [
            TextButton(
              onPressed: _checking ? null : () => _check(manual: true),
              child: _checking
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('完成'),
            ),
          ],
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    minHeight: 2,
                    backgroundColor: scheme.surfaceContainerHigh,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            InfWebView(controller: _web),
            if (_bridging)
              Positioned.fill(
                child: ColoredBox(
                  color: scheme.surface,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
