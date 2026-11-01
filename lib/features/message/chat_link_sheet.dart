import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics.dart';
import '../../core/links.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/share.dart';
import '../../core/widgets/common.dart';

/// Open a chat link inside INF when it points at a Weibo status/user; fall
/// back to a local link sheet for arbitrary URLs.
Future<void> openChatLink(BuildContext context, String url) async {
  var target = url;
  if (linkTargetOf(target) is ShortLinkTarget) {
    target = await expandShortLink(target) ?? target;
    if (!context.mounted) return;
  }
  switch (linkTargetOf(target)) {
    case StatusTarget() || UserTarget() || TopicTarget() || SuperTopicTarget():
      await openLink(context, target);
    case WebTarget() || AppOnlyTarget() || ClientPageTarget() || ShortLinkTarget():
      await showChatLinkSheet(context, target);
  }
}

/// Chat links are shown in a local sheet instead of pushing a WebView.
Future<void> showChatLinkSheet(BuildContext context, String url) {
  return showActionSheet<void>(
    context: context,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text('链接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  url,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        Haptic.success.play();
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                          showMessage(context, '链接已复制');
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('复制链接'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await shareText(url);
                      },
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('分享'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
