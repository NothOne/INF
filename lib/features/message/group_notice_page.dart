import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error_text.dart';
import '../../core/group_chat_api.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/rich_text.dart';
import 'chat_cards.dart';

/// Full group announcement screen, opened from the preview row on [GroupInfoPage].
///
/// Displays the complete text (with clickable links, mentions, topics and emojis), publish time,
/// optional attached link (`bulletin.scheme`), copy action, and in-place editing for group owners
/// and admins. Pops with the updated [GroupInfo] when edited.
class GroupNoticePage extends StatefulWidget {
  const GroupNoticePage({
    super.key,
    required this.info,
    this.canEdit = false,
  });

  final GroupInfo info;
  final bool canEdit;

  @override
  State<GroupNoticePage> createState() => _GroupNoticePageState();
}

class _GroupNoticePageState extends State<GroupNoticePage> {
  late GroupInfo _info = widget.info;
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _content = TextEditingController(text: _info.notice ?? '');
  late final TextEditingController _scheme = TextEditingController(text: _info.noticeScheme ?? '');

  @override
  void initState() {
    super.initState();
    // If the group has no announcement yet and the viewer can edit, open straight into editing.
    if ((_info.notice?.isEmpty ?? true) && widget.canEdit) {
      _editing = true;
    }
  }

  @override
  void dispose() {
    _content.dispose();
    _scheme.dispose();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    Haptic.success.play();
    if (mounted) showMessage(context, '已复制群公告');
  }

  Future<void> _refresh() async {
    GroupInfo? primary;
    GroupInfo? base;
    await Future.wait<void>([
      GroupChatApi.instance
          .queryGroup(_info.gid, allMembers: false)
          .then<void>((v) => primary = v.info)
          .catchError((Object _) {}),
      GroupChatApi.instance.groupInfo(_info.gid).then<void>((v) => base = v).catchError((Object _) {}),
    ]);
    if (!mounted) return;
    var next = _info;
    if (primary != null) next = primary!.mergeWith(next);
    if (base != null) next = next.mergeWith(base!);
    setState(() => _info = next);
  }

  Future<void> _save() async {
    if (_saving) return;
    final nextContent = _content.text.trim();
    final nextScheme = _scheme.text.trim();
    setState(() => _saving = true);
    try {
      await GroupChatApi.instance.setGroupNotice(
        _info.gid,
        nextContent,
        scheme: nextScheme.isEmpty ? null : nextScheme,
      );
      Haptic.success.play();
      if (!mounted) return;
      final updated = _info.copyWith(
        notice: nextContent.isEmpty ? null : nextContent,
        clearNotice: nextContent.isEmpty,
        noticeScheme: nextContent.isEmpty || nextScheme.isEmpty ? null : nextScheme,
        clearNoticeScheme: nextContent.isEmpty || nextScheme.isEmpty,
        noticeTime: nextContent.isEmpty ? null : DateTime.now().millisecondsSinceEpoch ~/ 1000,
        clearNoticeTime: nextContent.isEmpty,
      );
      setState(() {
        _info = updated;
        _saving = false;
        _editing = false;
      });
      showMessage(context, nextContent.isEmpty ? '已清空群公告' : '群公告已更新');
      Navigator.of(context).pop(updated);
    } catch (error) {
      Haptic.error.play();
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, friendlyError(error));
    }
  }

  String _formatTime(int epochSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final gutter = contentGutter(context);
    final notice = _info.notice;
    final noticeScheme = _info.noticeScheme;

    return PopScope<GroupInfo>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_info);
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        extendBodyBehindAppBar: chrome.extendsBehindBars,
        appBar: AppBar(
          flexibleSpace: lookBarBackground(context),
          title: const Text('群公告'),
          actions: [
            if (_editing) ...[
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('发布'),
              ),
            ] else ...[
              if (notice != null && notice.isNotEmpty)
                IconButton(
                  onPressed: () => _copy(notice),
                  tooltip: '复制公告',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                ),
              if (widget.canEdit)
                TextButton(
                  onPressed: () {
                    _content.text = _info.notice ?? '';
                    _scheme.text = _info.noticeScheme ?? '';
                    setState(() => _editing = true);
                  },
                  child: const Text('编辑'),
                ),
            ],
            const SizedBox(width: 4),
          ],
        ),
        body: ContentColumn(
          child: Builder(
            builder: (bodyContext) {
              final list = ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  gutter + 16,
                  MediaQuery.paddingOf(bodyContext).top + 16,
                  gutter + 16,
                  28 + MediaQuery.paddingOf(bodyContext).bottom,
                ),
                children: _editing
                    ? _buildEditor(context)
                    : _buildReader(context, notice, noticeScheme),
              );
              return _editing ? list : InfRefreshIndicator(onRefresh: _refresh, child: list);
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildReader(BuildContext context, String? notice, String? noticeScheme) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (notice == null || notice.isEmpty) {
      return [
        const SizedBox(height: 48),
        const EmptyHint(text: '暂无群公告', icon: Icons.campaign_outlined),
      ];
    }
    return [
      Row(
        children: [
          Icon(Icons.campaign_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _info.name.isNotEmpty ? _info.name : '群公告',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(color: scheme.onSurface),
            ),
          ),
          if (_info.noticeTime != null && _info.noticeTime! > 0)
            Text(
              _formatTime(_info.noticeTime!),
              style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 0.6),
        ),
        child: RichStatusText(
          text: notice,
          style: textTheme.bodyLarge?.copyWith(height: 1.6, fontSize: 15.5),
          onMention: (uid) => openUser(context, uid),
          onTopic: (name) => openTopic(context, name),
          onUrl: (url) => openLink(context, url),
        ),
      ),
      if (noticeScheme != null && noticeScheme.isNotEmpty) ...[
        const SizedBox(height: 12),
        if (noticeScheme.startsWith('http://') || noticeScheme.startsWith('https://')) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ChatLinkCard(
              url: noticeScheme,
              onOpenUrl: (url) => openLink(context, url),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 0.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openLink(context, noticeScheme),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('公告链接', style: textTheme.labelMedium?.copyWith(color: scheme.primary)),
                        const SizedBox(height: 2),
                        Text(
                          noticeScheme,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildEditor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return [
      TextField(
        controller: _content,
        autofocus: true,
        minLines: 6,
        maxLines: 14,
        decoration: InputDecoration(
          hintText: '写点什么让大家都知道（留空发布可清空公告）',
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _scheme,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: '附带链接（可选）',
          hintText: 'https://...',
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '仅群主与管理员可以发布或清空群公告。',
        style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ];
  }
}
