import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
