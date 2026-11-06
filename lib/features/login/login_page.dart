import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/native.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/web_view.dart';
import 'qr_login_panel.dart';

/// Which form passport's page should show. It opens on whatever its config names first, so the
/// other one is reached by tapping its tab once the page has drawn.
enum _WebLogin {
  page(null, '网页登录'),
  sms(['短信验证登录', '验证码登录'], '短信验证码登录'),
  password(['账号密码登录', '账号登录'], '账号密码登录');

  const _WebLogin(this.tabs, this.title);
  final List<String>? tabs;
  final String title;
}

/// Clicks the first leaf element reading one of [labels], polling while the page's app mounts.
String _selectTabScript(List<String> labels) => '''
(function (labels) {
  var tries = 0;
  var timer = setInterval(function () {
    tries++;
    var nodes = document.querySelectorAll('div,span,a,button,li,p');
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (node.children.length === 0 && labels.indexOf((node.textContent || '').trim()) >= 0) {
        node.click();
        clearInterval(timer);
        return;
      }
    }
    if (tries > 25) clearInterval(timer);
  }, 200);
})(${jsonEncode(labels)});
''';

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
        if (mounted) {
          setState(() {
            _progress = 0.15;
            _loadError = null;
          });
        }
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
        // A good crossdomain hop 302s away, so a page that settles on one has failed.
        if (Native.isOhos) _skipFailedCrossdomain(url);
        _selectTab(url);
        _onUrl(url);
      },
      // HarmonyOS's WebView has no HTTP error callback; there onPageFinished stands in.
      onHttpError: Native.isOhos ? null : (error) => _skipFailedCrossdomain(error.request?.uri.toString()),
      onWebResourceError: (error) {
        if (!(error.isForMainFrame ?? true) || _skipFailedCrossdomain(error.url)) return;
        debugPrint('INF login: ${error.errorCode} ${error.description} ${error.url}');
        if (mounted) setState(() => _loadError = '${error.description}（${error.errorCode}）');
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

  /// Null while the methods are listed; otherwise the WebView is in front, showing this form.
  _WebLogin? _shown;
  bool _webReady = false;
  bool _tabSelected = false;

  double _progress = 0;
  bool _checking = false;
  bool _finished = false;
  bool _bridging = false;
  String? _loadError;
  final Set<String> _skipped = {};

  @override
  void initState() {
    super.initState();
    if (Session.instance.state == SessionState.loggedOut) {
      Native.clearAuthCookies().then((_) => Session.instance.reloadCookies());
    }
  }

  Future<void> _openWeb(_WebLogin form, {String? url}) async {
    Haptic.selection.play();
    setState(() {
      _shown = form;
      _tabSelected = false;
      _progress = 0;
      _loadError = null;
      _bridging = url != null;
    });
    // The platform controller is created with WebViewWidget, lazily on Android: it has to be on
    // screen before its cookie policy can be set.
    await WidgetsBinding.instance.endOfFrame;
    if (!_webReady) {
      _webReady = true;
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
    }
    await _web.loadRequest(Uri.parse(url ?? Session.loginUrl));
  }

  void _closeWeb() {
    setState(() {
      _shown = null;
      _bridging = false;
      _loadError = null;
    });
  }

  void _selectTab(String url) {
    final tabs = _shown?.tabs;
    if (tabs == null || _tabSelected) return;
    final uri = Uri.tryParse(url);
    if (uri?.host != 'passport.weibo.com' || uri?.path != '/sso/signin') return;
    _tabSelected = true;
    _web.runJavaScript(_selectTabScript(tabs)).catchError((_) {});
  }

  /// After SMS login, passport jumps to login.sina.com.cn/sso/v2/crossdomain,
  /// which can answer 403 with an empty body. Every hop carries its own ticket
  /// for the next one in `cdurl`, and a successful hop just 302s there with
  /// `&url=`; do that redirect ourselves so the `.weibo.cn` hop still runs.
  bool _skipFailedCrossdomain(String? failedUrl) {
    final uri = Uri.tryParse(failedUrl ?? '');
    if (uri == null || !uri.path.endsWith('/crossdomain')) return false;
    final next = uri.queryParameters['cdurl'];
    if (next == null || next.isEmpty || !_skipped.add(failedUrl!)) return false;
    final target = uri.queryParameters['url'];
    final sep = next.contains('?') ? '&' : '?';
    final resolved = target == null ? next : '$next${sep}url=${Uri.encodeQueryComponent(target)}';
    if (Uri.tryParse(resolved)?.scheme != 'https') return false;
    if (mounted) setState(() => _bridging = true);
    _web.loadRequest(Uri.parse(resolved));
    return true;
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
      final bar = infSnackBar(context, const Text('登录成功'));
      Navigator.of(context).pop();
      messenger.showSnackBar(bar);
    } else if (manual) {
      Haptic.error.play();
      messenger.showSnackBar(infSnackBar(context, const Text('还没有检测到登录，请先在网页中完成登录和验证')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    return PopScope(
      canPop: shown == null,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (mounted) {
          _closeWeb();
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: Text(shown?.title ?? '登录微博'),
          actions: [
            if (shown != null)
              TextButton(
                onPressed: _checking ? null : () => _check(manual: true),
                child: _checking
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('完成'),
              ),
          ],
          leading: shown == null
              ? IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭',
                )
              : IconButton(
                  onPressed: _closeWeb,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: '换一种方式',
                ),
          bottom: shown != null && _progress < 1
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
        body: IndexedStack(
          index: shown == null ? 0 : 1,
          children: [
            _methods(context),
            // Built on first use and then kept, so going back to the list and in again keeps the
            // page and its cookies where they were.
            if (_webReady || shown != null) _webBody(context) else const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _methods(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final gutter = contentGutter(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(16 + gutter, 12, 16 + gutter, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        QrLoginPanel(
          active: _shown == null && !_finished,
          onConfirmed: (url) => _openWeb(_WebLogin.page, url: url),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text('其他方式', style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        _MethodTile(
          icon: Icons.sms_outlined,
          title: '短信验证码登录',
          subtitle: '输入手机号收验证码，发送前通常要完成拼图验证',
          onTap: () => _openWeb(_WebLogin.sms),
        ),
        _MethodTile(
          icon: Icons.password_rounded,
          title: '账号密码登录',
          subtitle: '可能要完成拼图验证，新设备还会要求短信二次验证',
          onTap: () => _openWeb(_WebLogin.password),
        ),
        _MethodTile(
          icon: Icons.language_rounded,
          title: '网页登录',
          subtitle: '打开微博官方登录页，可用页面上的全部方式',
          onTap: () => _openWeb(_WebLogin.page),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '短信和密码登录都在微博官方页面里完成，验证码和安全验证也由微博提供。INF 只读取登录后的 Cookie，不保存手机号和密码。',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _webBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        InfWebView(controller: _web),
        if (_loadError != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: Material(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '登录页加载失败：$_loadError',
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    TextButton(onPressed: _web.reload, child: const Text('重试')),
                  ],
                ),
              ),
            ),
          ),
        if (_bridging)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surface,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
