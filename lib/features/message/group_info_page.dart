import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/native.dart';
import '../../core/navigation.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

/// A group chat's own page, opened from the ⋯ in the chat's top bar.
///
/// What m.weibo.cn will say about a group is a short list. Its name and member count ride in the title
/// of every message page (`群名(828)`); every other candidate — member list, announcement, settings —
/// was tried against a real account and answered 404 or an empty page (see `WeiboApi.groupSpeakers`).
///
/// So the member strip here is **the people whose messages have been loaded**, not the roster, and it
/// says so. The group's real size is the count in the title, which is exact even though its members are
/// not enumerable. Nothing on this page pretends to be the announcement or a mute switch, because
/// there is nowhere to read or write either.
///
/// Pops with true once the group was left.
class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({
    super.key,
    required this.gid,
    required this.title,
    this.speakers = const [],
    this.hasMoreHistory = false,
    this.onLoadOlder,
  });

  final String gid;

  /// The group's title as its message pages spell it, `群名(828)`.
  final String title;

  /// Everyone whose messages the chat page has loaded, alphabetically.
  final List<User> speakers;

  /// Whether there is more history to page in, which is the only way to see more of the speakers.
  final bool hasMoreHistory;

  /// Pages more history in and answers with the speakers it turned up.
  final Future<List<User>> Function()? onLoadOlder;

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late List<User> _speakers = widget.speakers;
  bool _loadingMore = false;
  bool _busy = false;

  String get _link => 'https://m.weibo.cn/message/chat?gid=${widget.gid}';

  GroupInfo get _info => WeiboApi.instance.groupInfoFromTitle(widget.gid, widget.title);

  Future<void> _moreSpeakers() async {
    final load = widget.onLoadOlder;
    if (load == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final all = await load();
      if (!mounted) return;
      // The chat page holds the accumulated set and hands back the whole of it.
      if (all.isNotEmpty) setState(() => _speakers = all);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    Haptic.success.play();
    if (mounted) showMessage(context, '已复制');
  }

  Future<void> _openInBrowser() async {
    if (await Native.openUrl(_link)) return;
    if (mounted) showMessage(context, '没有可以打开链接的浏览器');
  }

  Future<void> _share() async {
    final name = _info.name;
    try {
      await SharePlus.instance.share(ShareParams(text: '微博群聊：$name\n$_link', subject: name));
    } catch (_) {
      await _copy(_link);
    }
  }

  Future<void> _leave() async {
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
    setState(() => _busy = true);
    try {
      await WeiboApi.instance.leaveGroup(widget.gid);
      Haptic.success.play();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      Haptic.error.play();
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, error is ApiException ? error.message : '退出失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chrome = InfChrome.of(context);
    final gutter = contentGutter(context);
    final info = _info;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: chrome.extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: const Text('群聊信息'),
        actions: [
          IconButton(onPressed: _share, tooltip: '分享群', icon: const Icon(Icons.ios_share_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: ContentColumn(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            (chrome.extendsBehindBars ? MediaQuery.paddingOf(context).top + kToolbarHeight : 0) + 16,
            gutter,
            28 + MediaQuery.paddingOf(context).bottom,
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
            Text(info.name, textAlign: TextAlign.center, style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              info.memberCount > 0
                  ? '群号 ${widget.gid} · ${info.memberCount} 人'
                  : '群号 ${widget.gid}',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _MembersStrip(
              speakers: _speakers,
              count: info.memberCount,
              onTap: () => openGroupMembers(
                context,
                gid: widget.gid,
                name: info.name,
                speakers: _speakers,
                memberCount: info.memberCount,
                hasMoreHistory: widget.hasMoreHistory,
                onLoadOlder: widget.onLoadOlder,
              ),
            ),
            if (_speakers.isNotEmpty && widget.hasMoreHistory)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: TextButton.icon(
                  onPressed: _loadingMore ? null : _moreSpeakers,
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                  label: Text(_loadingMore ? '正在往前翻…' : '往前翻聊天记录，看到更多成员'),
                ),
              ),
            const SizedBox(height: 8),
            const Divider(height: 24),
            _SectionCard(
              children: [
                _Row(icon: Icons.ios_share_rounded, label: '分享群', onTap: _share),
                _Row(icon: Icons.tag_rounded, label: '复制群号', onTap: () => _copy(widget.gid)),
                _Row(icon: Icons.open_in_browser_rounded, label: '在浏览器中打开', onTap: _openInBrowser),
              ],
            ),
            const SizedBox(height: 10),
            _SectionCard(
              children: [
                _Row(icon: Icons.logout_rounded, label: '退出群聊', danger: true, onTap: _busy ? null : _leave),
              ],
            ),
            const SizedBox(height: 18),
            // Said plainly rather than left as missing rows the reader would wonder about: these are
            // things the phone site does not expose for a group, not things this app forgot.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '群公告、消息免打扰、完整成员名单，网页版微博没有提供，这里也拿不到。'
                '看到的消息条数越多，下面能列出的成员越多。',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The strip of faces at the top, and the way into the full list.
class _MembersStrip extends StatelessWidget {
  const _MembersStrip({required this.speakers, required this.count, required this.onTap});

  final List<User> speakers;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: speakers.isEmpty
                  ? Text(
                      '还没有可列出的成员',
                      style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final speaker in speakers.take(8)) Avatar(url: speaker.avatarUrl, size: 38),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              speakers.isEmpty ? '成员' : '${speakers.length} 位',
              style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// A rounded block of rows, the shape a settings screen uses.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? scheme.error : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(color: danger ? scheme.error : scheme.onSurface),
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
