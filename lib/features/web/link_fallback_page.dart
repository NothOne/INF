import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics.dart';
import '../../core/native.dart';
import '../../core/widgets/common.dart';

/// Where a link ends up when INF has no page for it and its web page shows nothing useful: say
/// why, and offer the Weibo app, the browser and the address itself.
class LinkFallbackPage extends StatelessWidget {
  const LinkFallbackPage({super.key, required this.url, this.appUrl, this.title});

  /// The address to copy, and to load in a browser when it is a web one.
  final String url;

  /// The same page as the Weibo app opens it, for a web page that only works there.
  final String? appUrl;
  final String? title;

  bool get _web => url.toLowerCase().startsWith('http');

  Future<void> _open(BuildContext context, String target, String missing, {String? package}) async {
    final opened = await Native.openUrl(target, package: package);
    if (!opened && context.mounted) showMessage(context, missing);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final weiboUrl = appUrl ?? (url.toLowerCase().startsWith('sinaweibo:') ? url : null);
    final explanation = switch ((weiboUrl != null, _web)) {
      (true, true) => '这是微博客户端里的页面（小程序、专栏等），网页版只会提示下载客户端。',
      (true, false) => '这是微博客户端专用的页面，网页版没有对应内容。',
      (false, true) => '这个链接没有可以在 INF 中打开的页面，可以用浏览器试试。',
      (false, false) => '这个链接需要其他应用打开。',
    };
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('链接')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    weiboUrl != null ? Icons.phone_android_rounded : Icons.link_off_rounded,
                    size: 44,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title != null && title!.isNotEmpty
                        ? title!
                        : (weiboUrl != null ? '需要在微博客户端中查看' : '暂不支持在 INF 中查看'),
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    explanation,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(url, minLines: 1, maxLines: 4, style: text.bodySmall),
                  ),
                  const SizedBox(height: 18),
                  if (weiboUrl != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _open(context, weiboUrl, '没有安装微博客户端', package: 'com.sina.weibo'),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('在微博客户端打开'),
                      ),
                    ),
                  if (_web || weiboUrl == null) ...[
                    if (weiboUrl != null) const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: weiboUrl == null
                          ? FilledButton.icon(
                              onPressed: () => _open(context, url, '没有可以打开这个链接的应用'),
                              icon: Icon(_web ? Icons.open_in_browser_rounded : Icons.open_in_new_rounded),
                              label: Text(_web ? '用浏览器打开' : '用其他应用打开'),
                            )
                          : OutlinedButton.icon(
                              onPressed: () => _open(context, url, '没有可以打开链接的浏览器'),
                              icon: const Icon(Icons.open_in_browser_rounded),
                              label: const Text('用浏览器打开'),
                            ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        Haptic.success.play();
                        if (context.mounted) showMessage(context, '链接已复制');
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('复制链接'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
