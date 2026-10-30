import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
      onPageFinished: (_) {
        if (mounted) setState(() => _progress = 1);
      },
    ))
    ..loadRequest(Uri.parse(widget.url));

  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(widget.url)?.host ?? '';
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
          title: Text(host.isEmpty ? '网页' : host, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: IconButton(
            onPressed: () async {
              if (await _web.canGoBack()) {
                await _web.goBack();
              } else if (mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
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
        body: InfWebView(controller: _web),
      ),
    );
  }
}
