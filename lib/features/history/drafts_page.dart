import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/error_text.dart';
import '../../core/haptics.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/parse.dart';
import '../../core/prefs.dart';
import '../../core/temp_files.dart';
import '../../core/widgets/common.dart';

class DraftsPage extends StatefulWidget {
  const DraftsPage({super.key});

  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  final Set<int> _busy = {};

  Future<void> _send(Draft draft) async {
    if (_busy.contains(draft.id)) return;
    setState(() => _busy.add(draft.id));
    try {
      if (draft.type == DraftType.original) {
        final videoPath = draft.videoPath;
        if (videoPath != null && videoPath.isNotEmpty) {
          // A draft that carries a video sends only the video: Weibo does not take both.
          final video = await WeiboApi.instance.uploadVideo(File(videoPath));
          await WeiboApi.instance.postStatus(
            draft.text.trim(),
            const [],
            visibility: draft.visibility,
            statement: draft.statement,
            video: video,
          );
        } else {
          final ids = <String>[];
          for (final path in draft.images) {
            ids.add(await WeiboApi.instance.uploadImage(File(path)));
          }
          await WeiboApi.instance.postStatus(
            draft.text.trim(),
            ids,
            visibility: draft.visibility,
            statement: draft.statement,
          );
        }
      } else {
        final ids = <String>[];
        for (final path in draft.images) {
          ids.add(await WeiboApi.instance.uploadImage(File(path)));
        }
        await WeiboApi.instance.repost(
          draft.statusId ?? '',
          draft.text.trim(),
          draft.crossPost,
          picIds: ids,
          visibility: draft.visibility,
        );
      }
      final drafts = Prefs.instance.drafts.where((d) => d.id != draft.id).toList();
      await Prefs.instance.saveDrafts(drafts);
      await DraftFiles.delete(draft.images);
      Haptic.success.play();
      if (mounted) showMessage(context, '已发送');
    } catch (error) {
      final message = friendlyError(error);
      final drafts = Prefs.instance.drafts.toList();
      final index = drafts.indexWhere((d) => d.id == draft.id);
      if (index >= 0) {
        drafts[index] = drafts[index].copyWith(
          state: DraftState.failed,
          error: message,
          updatedAt: DateTime.now(),
        );
        await Prefs.instance.saveDrafts(drafts);
      }
      Haptic.error.play();
      if (mounted) showMessage(context, message);
    } finally {
      if (mounted) setState(() => _busy.remove(draft.id));
    }
  }

  Future<void> _delete(Draft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条草稿？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final drafts = Prefs.instance.drafts.where((d) => d.id != draft.id).toList();
    await Prefs.instance.saveDrafts(drafts);
    await DraftFiles.delete(draft.images);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs.instance.draftsNotifier,
      builder: (context, _) {
        final drafts = Prefs.instance.drafts;
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: scheme.surface,
          extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
          appBar: AppBar(title: const Text('草稿箱'), flexibleSpace: lookBarBackground(context)),
          body: drafts.isEmpty
              ? const EmptyHint(text: '草稿箱是空的', icon: Icons.edit_note_rounded)
              : Builder(
                  builder: (context) => ListView.separated(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top,
                      bottom: 24 + MediaQuery.paddingOf(context).bottom,
                      left: contentGutter(context),
                      right: contentGutter(context),
                    ),
                    itemCount: drafts.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      final busy = _busy.contains(draft.id);
                      final openable = draft.state != DraftState.queued && draft.state != DraftState.sending;
                      return InkWell(
                        onTap: openable
                            ? () => openCompose(context, draftId: draft.id)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          _typeLabel(draft),
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                color: scheme.primary,
                                              ),
                                        ),
                                        const SizedBox(width: 8),
                                        _StateChip(state: draft.state),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      draft.text.trim().isEmpty ? '（无文字）' : draft.text,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _metaOf(draft),
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    if (draft.state == DraftState.failed && draft.error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          draft.error!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  if (busy)
                                    const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  else if (draft.state == DraftState.editing || draft.state == DraftState.failed)
                                    IconButton(
                                      onPressed: () => _send(draft),
                                      tooltip: draft.state == DraftState.failed ? '重试' : '发送',
                                      icon: Icon(
                                        draft.state == DraftState.failed ? Icons.refresh_rounded : Icons.send_rounded,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  IconButton(
                                    onPressed: () => _delete(draft),
                                    tooltip: '删除',
                                    icon: const Icon(Icons.delete_outline_rounded),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }

  String _typeLabel(Draft draft) => switch (draft.type) {
        DraftType.original => '原创',
        DraftType.repost => '转发',
      };

  /// What a draft carries besides its words: the media it has, and a visibility that is not the
  /// default — resending it will use both, so the tile says so before the reader taps send.
  String _metaOf(Draft draft) {
    final parts = <String>[
      if (draft.videoPath != null && draft.videoPath!.isNotEmpty)
        '[视频]'
      else if (draft.images.isNotEmpty)
        '图片 ${draft.images.length} 张',
      if (draft.visibility != PostVisibility.public) draft.visibility.label,
      relativeTime(draft.updatedAt),
    ];
    return parts.join(' · ');
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final DraftState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, container, content) = switch (state) {
      DraftState.editing => ('草稿', scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
      DraftState.queued => ('等待发送', scheme.secondaryContainer, scheme.onSecondaryContainer),
      DraftState.sending => ('发送中', scheme.primaryContainer, scheme.onPrimaryContainer),
      DraftState.failed => ('发送失败', scheme.errorContainer, scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: container, borderRadius: BorderRadius.circular(50)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: content),
      ),
    );
  }
}
