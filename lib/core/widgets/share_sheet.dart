import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../haptics.dart';
import '../models.dart';
import '../motion.dart';
import '../session.dart';
import '../share.dart';
import 'avatar.dart';
import 'common.dart';

/// Sharing a post: to a recent private-message contact (the post's link, which Weibo shows as a
/// card in the chat), or out through the system share panel.
Future<void> showStatusShare(BuildContext context, Status status, {VoidCallback? onLongImage}) {
  return showActionSheet<void>(
    context: context,
    frosted: false,
    builder: (sheetContext) => _ShareSheet(
      status: status,
      onLongImage: onLongImage,
      messenger: context,
    ),
  );
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.status, required this.messenger, this.onLongImage});

  final Status status;
  final VoidCallback? onLongImage;

  /// Where messages go once the sheet is closed.
  final BuildContext messenger;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    void run(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Session.instance.uid != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Text('发送给好友', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            _Contacts(status: status),
            const Divider(height: 20),
          ],
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _ShareTarget(
                  icon: Icons.ios_share_rounded,
                  label: '系统分享',
                  onTap: () => run(() => shareText(statusShareText(status))),
                ),
                _ShareTarget(
                  icon: Icons.link_rounded,
                  label: '复制链接',
                  onTap: () => run(() {
                    Clipboard.setData(ClipboardData(text: statusLink(status.id)));
                    Haptic.success.play();
                    showMessage(messenger, '已复制');
                  }),
                ),
                if (onLongImage != null)
                  _ShareTarget(icon: Icons.article_outlined, label: '生成长图', onTap: () => run(onLongImage!)),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// The first page of private conversations, newest first; a tap sends the post to that chat.
class _Contacts extends StatefulWidget {
  const _Contacts({required this.status});

  final Status status;

  @override
  State<_Contacts> createState() => _ContactsState();
}

class _ContactsState extends State<_Contacts> {
  List<Conversation>? _items = WeiboApi.instance.cachedConversations(false)?.items;
  String? _error;
  final Set<String> _sending = {};
  final Set<String> _sent = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await WeiboApi.instance.conversations(false, null);
      if (mounted) setState(() => _items = page.items);
    } catch (error) {
      if (mounted && _items == null) setState(() => _error = error is ApiException ? error.message : '加载失败');
    }
  }

  String _key(Conversation c) => c.groupId ?? c.user.id;

  Future<void> _send(Conversation conversation) async {
    final key = _key(conversation);
    if (_sending.contains(key) || _sent.contains(key)) return;
    setState(() => _sending.add(key));
    try {
      final content = statusLink(widget.status.id);
      if (conversation.isGroup) {
        await WeiboApi.instance.sendGroupMessage(conversation.groupId!, content);
      } else {
        await WeiboApi.instance.sendMessage(conversation.user.id, content);
      }
      Haptic.success.play();
      if (mounted) setState(() => _sent.add(key));
    } catch (error) {
      Haptic.error.play();
      if (mounted) showMessage(context, error is ApiException ? error.message : '发送失败');
    } finally {
      if (mounted) setState(() => _sending.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _items;
    if (items == null) {
      return SizedBox(
        height: 84,
        child: Center(
          child: _error == null
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_error!, style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    if (items.isEmpty) {
      return SizedBox(
        height: 60,
        child: Center(child: Text('还没有私信联系人', style: TextStyle(color: scheme.onSurfaceVariant))),
      );
    }
    return SizedBox(
      height: 84,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final conversation = items[index];
          final key = _key(conversation);
          final sending = _sending.contains(key);
          final sent = _sent.contains(key);
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _send(conversation),
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Avatar(url: conversation.user.avatarUrl, size: 48),
                      if (sending || sent)
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.check_rounded, color: Colors.white),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      sent ? '已发送' : conversation.user.screenName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: sent ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShareTarget extends StatelessWidget {
  const _ShareTarget({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, shape: BoxShape.circle),
              child: Icon(icon, color: scheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
