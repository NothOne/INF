import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/motion.dart';
import '../../core/haptics.dart';
import '../../core/navigation.dart';
import '../../core/widgets/common.dart';

/// Open a chat link inside INF when it points at a Weibo status/user; fall
/// back to a local link sheet for arbitrary URLs.
Future<void> openChatLink(BuildContext context, String url) async {
  var target = url;
  if (target.contains('t.cn')) {
    target = await _resolveShortLink(target) ?? target;
  }
  final uri = Uri.tryParse(target);
  if (uri == null) {
    await showChatLinkSheet(context, target);
    return;
  }
  final status = RegExp(r'/(?:detail|status)/([0-9A-Za-z]+)').firstMatch(uri.path);
  if (status != null) {
    await openStatus(context, statusId: status.group(1)!);
    return;
  }
  final user = RegExp(r'/(?:u|profile)/([0-9]+)').firstMatch(uri.path);
  if (user != null) {
    await openUser(context, user.group(1)!);
    return;
  }
  if (uri.host == 'weibo.com' || uri.host == 'www.weibo.com') {
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2 && RegExp(r'^[0-9]+' + r'$').hasMatch(parts[0])) {
      await openStatus(context, statusId: parts[1]);
      return;
    }
    if (parts.length == 1 && RegExp(r'^[0-9]+' + r'$').hasMatch(parts[0])) {
      await openUser(context, parts[0]);
      return;
    }
  }
  await showChatLinkSheet(context, target);
}

Future<String?> _resolveShortLink(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    await response.drain<void>();
    if (response.redirects.isEmpty) return null;
    final last = response.redirects.last.location;
    return Uri.parse(url).resolveUri(last).toString();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
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
                        await SharePlus.instance.share(ShareParams(text: url));
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
