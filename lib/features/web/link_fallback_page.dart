import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics.dart';
import '../../core/native.dart';
import '../../core/widgets/common.dart';

/// Where a link ends up when INF has no page for it and there is no web version to load: say so,
/// and offer the Weibo app, the system's handler and the address itself.
class LinkFallbackPage extends StatelessWidget {
  const LinkFallbackPage({super.key, required this.url, this.title});

  final String url;
  final String? title;

  Future<void> _openOutside(BuildContext context) async {
    final opened = await Native.openUrl(url);
    if (!opened && context.mounted) showMessage(context, '没有可以打开这个链接的应用');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final weiboApp = url.toLowerCase().startsWith('sinaweibo:');
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
                  Icon(Icons.link_off_rounded, size: 44, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 14),
                  Text(
                    title == null || title!.isEmpty ? '暂不支持在 INF 中查看' : title!,
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    weiboApp ? '这是微博客户端专用的页面，网页版没有对应内容。' : '这个链接没有可以在 INF 中打开的页面。',
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
                    child: SelectableText(url, maxLines: 4, style: text.bodySmall),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openOutside(context),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(weiboApp ? '在微博客户端打开' : '用其他应用打开'),
                    ),
                  ),
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
