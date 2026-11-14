import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/native.dart';
import '../../core/navigation.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

/// A group chat's own page: its name, the members who have spoken in what was loaded (m.weibo.cn
/// has no member list), and leaving it. Pops with true once left.
class GroupInfoPage extends StatelessWidget {
  const GroupInfoPage({super.key, required this.gid, required this.name, required this.members});

  final String gid;
  final String name;
  final List<User> members;

  String get _link => 'https://m.weibo.cn/message/chat?gid=$gid';

  Future<void> _leave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('退出后不再接收这个群的消息，确定退出？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await WeiboApi.instance.leaveGroup(gid);
      Haptic.success.play();
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (error) {
      Haptic.error.play();
      if (context.mounted) showMessage(context, error is ApiException ? error.message : '退出失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chrome = InfChrome.of(context);
    final gutter = contentGutter(context);
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: chrome.extendsBehindBars,
      appBar: AppBar(flexibleSpace: lookBarBackground(context), title: const Text('群聊信息')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          (chrome.extendsBehindBars ? MediaQuery.paddingOf(context).top + kToolbarHeight : 0) + 16,
          gutter,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: scheme.secondaryContainer,
              child: Icon(Icons.groups_rounded, size: 34, color: scheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(height: 12),
          Text(name, textAlign: TextAlign.center, style: textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('群号 $gid', textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              members.isEmpty ? '最近发言的成员' : '最近发言的成员 · ${members.length}',
              style: textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          if (members.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: EmptyHint(text: '还没有人发言'))
          else
            Wrap(
              spacing: 4,
              runSpacing: 12,
              children: [
                for (final member in members)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => openUser(context, member.id),
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          Avatar(url: member.avatarUrl, size: 46),
                          const SizedBox(height: 5),
                          Text(
                            member.screenName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall,
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.tag_rounded),
            title: const Text('复制群号'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: gid));
              Haptic.success.play();
              showMessage(context, '已复制');
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_browser_rounded),
            title: const Text('在浏览器中打开'),
            onTap: () async {
              if (!await Native.openUrl(_link) && context.mounted) showMessage(context, '没有可以打开链接的浏览器');
            },
          ),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: scheme.error),
            title: Text('退出群聊', style: TextStyle(color: scheme.error)),
            onTap: () => _leave(context),
          ),
        ],
      ),
    );
  }
}
