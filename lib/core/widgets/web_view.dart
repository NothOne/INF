import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Weibo's own pages (the birthday gifts, old activity pages) still link pictures as
/// http://ww*.sinaimg.cn, which Android will not fetch; the same pictures are served over HTTPS.
/// Run once a page has loaded; it also catches pictures the page adds later.
const upgradeSinaimgScript = r'''
(function () {
  if (window.__infUpgrade) return;
  window.__infUpgrade = true;
  var plain = /^http:\/\/([^\/]*\.)?sinaimg\.cn\//;
  function fix(node) {
    if (node.tagName === 'IMG' && plain.test(node.getAttribute('src') || '')) {
      node.src = 'https' + node.getAttribute('src').slice(4);
    }
  }
  function scan(node) {
    if (!node.querySelectorAll) return;
    fix(node);
    node.querySelectorAll('img').forEach(fix);
  }
  scan(document.documentElement);
  new MutationObserver(function (changes) {
    changes.forEach(function (change) {
      if (change.type === 'attributes') fix(change.target);
      change.addedNodes.forEach(scan);
    });
  }).observe(document.documentElement, {subtree: true, childList: true, attributes: true, attributeFilter: ['src']});
})();
''';

/// A WebView that Android composites itself. The default texture-backed mode never shows a page
/// under Impeller on some devices.
class InfWebView extends StatelessWidget {
  const InfWebView({super.key, required this.controller});

  final WebViewController controller;

  @override
  Widget build(BuildContext context) {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) return WebViewWidget(controller: controller);
    return WebViewWidget.fromPlatformCreationParams(
      params: AndroidWebViewWidgetCreationParams(
        controller: platform,
        displayWithHybridComposition: true,
      ),
    );
  }
}
