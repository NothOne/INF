import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/image_url.dart';
import '../../core/links.dart';
import '../../core/native.dart';
import '../../core/navigation.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/web_view.dart';

class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.url});

  final String url;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(
      onProgress: (value) {
        if (mounted) setState(() => _progress = value / 100);
      },
      onPageStarted: (url) {
        if (_bouncesBack(url)) return;
        if (mounted && _failed) setState(() => _failed = false);
      },
      onPageFinished: (url) async {
        _loadedOnce = true;
        final host = Uri.tryParse(url)?.host;
        if (mounted) {
          setState(() {
            _progress = 1;
            if (host != null && host.isNotEmpty) _host = host;
          });
        }
        _web.runJavaScript(upgradeSinaimgScript).catchError((_) {});
        final title = (await _web.getTitle())?.trim();
        if (mounted && title != _title) setState(() => _title = title);
      },
      onWebResourceError: (error) {
        if (error.isForMainFrame == true && mounted) setState(() => _failed = true);
      },
      // A bad certificate is reported here, not as a resource error. Only Android says which
      // URL it was for; a failing subresource must not cover a page that loaded.
      onSslAuthError: (error) {
        error.cancel();
        final platform = error.platform;
        if (platform is! AndroidSslAuthError) return;
        final host = Uri.tryParse(platform.url)?.host;
        if (host != null && host == Uri.tryParse(_target)?.host && mounted) setState(() => _failed = true);
      },
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        final scheme = uri?.scheme.toLowerCase() ?? '';
        if (request.isMainFrame && _bouncesBack(request.url)) return NavigationDecision.prevent;
        if (request.isMainFrame && _loadedOnce && linkTargetOf(request.url) is ClientPageTarget) {
          openLink(context, request.url);
          return NavigationDecision.prevent;
        }
        if (request.isMainFrame && (scheme == 'http' || scheme == 'https')) _target = request.url;
        if (scheme == 'http') {
          if (request.isMainFrame) _web.loadRequest(Uri.parse(secureUrl(request.url)));
          return NavigationDecision.prevent;
        }
        const loadable = {'https', 'about', 'data', 'blob', 'javascript'};
        if (loadable.contains(scheme)) return NavigationDecision.navigate;
        // Before the first load an app link is the page pushing its app on everyone: ignored.
        if (!_loadedOnce || !mounted) return NavigationDecision.prevent;
        // A tap on 在微博中查看 and the like: a post, a person or a topic opens on INF's own page.
        if (scheme == 'sinaweibo') {
          final target = linkTargetOf(request.url);
          if (target is StatusTarget || target is UserTarget || target is TopicTarget || target is SuperTopicTarget) {
            openLink(context, request.url);
            return NavigationDecision.prevent;
          }
        }
        _offerApp(request.url);
        return NavigationDecision.prevent;
      },
    ))
    ..loadRequest(Uri.parse(secureUrl(widget.url)));

  double _progress = 0;
  bool _failed = false;
  bool _loadedOnce = false;
  String? _title;
  late String _host = Uri.tryParse(widget.url)?.host ?? '';

  /// When each app was last offered: a page retrying its jump on a timer is asked about once,
  /// a tap a few seconds later again.
  final Map<String, DateTime> _offered = {};
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _offer;

  /// The page wants another app (哔哩哔哩's 打开App, a news site's 打开): say which, and open it
  /// only if the reader asks.
  void _offerApp(String url) {
    final name = appNameOf(url);
    final key = name ?? Uri.tryParse(url)?.scheme ?? url;
    final now = DateTime.now();
    final last = _offered[key];
    if (last != null && now.difference(last) < const Duration(seconds: 3)) return;
    _offered[key] = now;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    _offer = messenger.showSnackBar(SnackBar(
        content: Text(name == null ? '网页想打开其他应用' : '网页想打开「$name」'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '打开',
          onPressed: () async {
            final weibo = url.toLowerCase().startsWith('sinaweibo:');
            final opened = await Native.openUrl(url, package: weibo ? 'com.sina.weibo' : null);
            if (!opened && mounted) showMessage(context, name == null ? '没有可以打开它的应用' : '没有安装$name');
          },
        ),
      ));
    final offer = _offer!;
    offer.closed.then((_) {
      if (identical(_offer, offer)) _offer = null;
    });
  }

  /// The prompt belongs to this page; the messenger would keep it over the post underneath.
  @override
  void dispose() {
    _offer?.close();
    super.dispose();
  }

  /// The address as the post or page gave it, before the HTTPS upgrade: a site that only speaks
  /// HTTP fails here but still opens in a browser.
  late String _target = widget.url;

  /// The page a back step left, and until when returning to it counts as being bounced: a
  /// redirecting page that is gone back to forwards to where the user just was.
  String? _leftUrl;
  DateTime? _bounceUntil;
  bool _closing = false;

  Future<void> _back() async {
    if (!await _web.canGoBack()) {
      _close();
      return;
    }
    _leftUrl = await _web.currentUrl();
    _bounceUntil = DateTime.now().add(const Duration(seconds: 2));
    await _web.goBack();
  }

  bool _bouncesBack(String url) {
    final left = _leftUrl;
    final until = _bounceUntil;
    if (left == null || until == null || DateTime.now().isAfter(until)) return false;
    if (_sameAddress(url, left)) {
      _close();
      return true;
    }
    return false;
  }

  static bool _sameAddress(String a, String b) {
    String strip(String url) => secureUrl(url).split('#').first.replaceFirst(RegExp(r'/$'), '');
    return strip(a) == strip(b);
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  Future<void> _openInBrowser() async {
    final current = _failed ? null : await _web.currentUrl();
    final url = current == null || current.isEmpty || current.startsWith('about:') ? _target : current;
    final opened = await Native.openUrl(url);
    if (!opened && mounted) showMessage(context, '没有可以打开链接的浏览器');
  }

  void _retry() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _web.loadRequest(Uri.parse(secureUrl(_target)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: _WebTitle(title: _title, host: _host),
          titleSpacing: 0,
          leadingWidth: 96,
          leading: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded), tooltip: '返回'),
              IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded), tooltip: '关闭'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser_rounded),
              tooltip: '用浏览器打开',
            ),
          ],
          bottom: _progress < 1 && !_failed
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
            Positioned.fill(child: InfWebView(controller: _web)),
            if (_failed)
              Positioned.fill(
                child: ColoredBox(
                  color: scheme.surface,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('网页加载失败', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Text(
                            _target,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _openInBrowser,
                          icon: const Icon(Icons.open_in_browser_rounded),
                          label: const Text('用浏览器打开'),
                        ),
                        TextButton(onPressed: _retry, child: const Text('重试')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The page's own title once it has one, over its host; until then just the host.
class _WebTitle extends StatelessWidget {
  const _WebTitle({required this.title, required this.host});

  final String? title;
  final String host;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = host.isEmpty ? '网页' : host;
    final heading = title == null || title!.isEmpty || title!.startsWith('http') || title == host ? null : title;
    if (heading == null) return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
