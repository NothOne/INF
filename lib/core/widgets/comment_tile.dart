import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/chrome.dart';
import '../../core/comment_store.dart';
import '../../core/container_route.dart';
import '../../core/haptics.dart';
import '../../core/image_url.dart';
import '../../core/models.dart';
import '../../core/parse.dart';
import '../../core/status_store.dart';
import 'avatar.dart';
import 'common.dart';
import 'rich_text.dart';
import 'smart_image.dart';
import 'status_actions.dart';
import 'status_menu_route.dart';
import 'viewer_hero.dart';

/// Pictures in [comment] that its text does not already link to: those the text links are drawn as
/// 查看图片 next to the text, so listing them again would repeat the same picture twice.
List<(int, Media)> unlinkedPictures(Comment comment) {
  final linked = inlineImageUrls(comment.text).map(sanitizeImageUrl).toSet();
  return [
    for (final (index, image) in comment.images.indexed)
      if (!linked.contains(sanitizeImageUrl(image.url)) && !linked.contains(sanitizeImageUrl(image.previewUrl)))
        (index, image),
  ];
}

/// One comment, wherever it is drawn: the discussion under a post, a reply thread, a notification.
///
/// It knows nothing about which list it is in. Everything that acts on the comment is a callback,
/// so the page decides whether a reply goes to this comment's thread or to the one it is already in.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.onOpenUser,
    required this.onOpenTopic,
    required this.onOpenUrl,
    required this.onOpenFloor,
    required this.onReply,
    required this.onOpenImage,
    this.imagesAsLinks = false,
    this.showReplies = true,
    this.onTap,
    this.awaitable = false,
  });

  final Comment comment;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<String> onOpenTopic;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback onOpenFloor;
  final void Function(BuildContext anchor) onReply;
  final void Function(List<Media> images, int index, String? heroTag) onOpenImage;
  final bool imagesAsLinks;

  /// Off where the replies are listed in full right below, as on the floor page.
  final bool showReplies;
  final void Function(BuildContext anchor)? onTap;

  /// One of this device's own comments, shown before the server has returned it: the reply and the
  /// like that would act on an id the server does not know yet are left out, and it says so.
  final bool awaitable;

  static final RegExp _alreadyReplyPrefix = RegExp(r'^回复\s*@?');

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Only this comment: liking the post or another comment must not rebuild this row.
      animation: StatusStore.instance.of([comment.id]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = relativeTime(comment.createdAt);
    final meta = awaitable
        ? '刚刚'
        : (comment.region == null || comment.region!.isEmpty ? time : '$time · ${comment.region}');
    final answered = comment.replyTo?.screenName;
    final hasPrefix = _alreadyReplyPrefix.hasMatch(comment.text.trimLeft());
    final body = (answered == null || answered.isEmpty || hasPrefix)
        ? comment.text
        : '回复 $answered：${comment.text}';
    final pendingReplies = showReplies ? CommentStore.instance.pendingRepliesFor(comment.id) : const <Comment>[];
    final existingIds = {for (final reply in comment.replies) reply.id};
    final extraReplies = [for (final reply in pendingReplies) if (!existingIds.contains(reply.id)) reply];
    final hasInlineReplies = showReplies && (extraReplies.isNotEmpty || comment.replies.isNotEmpty);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // The row's own context is the anchor its card grows out of and returns into.
      onTap: onTap == null ? null : () => onTap!(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: awaitable ? null : () => onOpenUser(comment.author.id),
              child: Avatar(url: comment.author.avatarUrl, size: 36, verified: comment.author.verified),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: awaitable ? null : () => onOpenUser(comment.author.id),
                    child: Text(
                      comment.author.screenName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 3),
                  RichStatusText(
                    text: body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14.5),
                    onMention: onOpenUser,
                    onTopic: onOpenTopic,
                    onUrl: onOpenUrl,
                    inlineImages: !imagesAsLinks && comment.images.isEmpty,
                    onOpenImage: (url, tag) => onOpenImage([Media.image(url)], 0, tag),
                  ),
                  if (comment.images.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    if (imagesAsLinks)
                      Wrap(
                        spacing: 14,
                        children: [
                          for (final (index, _) in unlinkedPictures(comment))
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onOpenImage(comment.images, index, 'link-img-comment-${comment.id}-$index'),
                              child: ViewerHero(
                                tag: 'link-img-comment-${comment.id}-$index',
                                child: InlineLinkLabel(
                                  icon: Icons.image_outlined,
                                  label: '查看图片',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
                                ),
                              ),
                            ),
                        ],
                      )
                    else
                      _CommentImages(
                        images: comment.images,
                        commentId: comment.id,
                        onOpen: onOpenImage,
                      ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (!awaitable)
                        Builder(
                          builder: (buttonContext) => TextButton(
                            onPressed: () => onReply(buttonContext),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(42, 26),
                              padding: const EdgeInsets.symmetric(horizontal: 7),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('回复', style: TextStyle(fontSize: 11.5)),
                          ),
                        ),
                      if (!awaitable) _CommentLikeButton(comment: comment),
                    ],
                  ),
                  if (hasInlineReplies) ...[
                    const SizedBox(height: 6),
                    _InlineReplies(
                      comment: comment,
                      extraReplies: extraReplies,
                      onTap: onOpenFloor,
                      onOpenImage: onOpenImage,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentLikeButton extends StatelessWidget {
  const _CommentLikeButton({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // No listener of its own: the tile above already listens for this comment's id and rebuilds
    // with it, so a second subscription here would only double the wakeups.
    final current = StatusStore.instance.applyComment(comment);
    final color = current.liked ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () async {
            final failure = await StatusStore.instance.toggleCommentLike(comment);
            if (failure != null && context.mounted) showMessage(context, failure);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 42, minHeight: 26),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(current.liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined, size: 14, color: color),
                  if (current.likesCount > 0) ...[
                    const SizedBox(width: 3),
                    Text(
                      compactCount(current.likesCount),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
  }
}

class _CommentImages extends StatelessWidget {
  const _CommentImages({required this.images, required this.commentId, required this.onOpen});

  final List<Media> images;
  final String commentId;
  final void Function(List<Media> images, int index, String? heroTag) onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < images.length && i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpen(images, i, 'comment-$commentId-$i'),
            child: ViewerHero(
              tag: 'comment-$commentId-$i',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 86,
                  height: 86,
                  child: SmartImage(
                    url: images[i].previewUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineReplies extends StatelessWidget {
  const _InlineReplies({
    required this.comment,
    required this.extraReplies,
    required this.onTap,
    required this.onOpenImage,
  });

  final Comment comment;
  final List<Comment> extraReplies;
  final VoidCallback onTap;
  final void Function(List<Media> images, int index, String? heroTag) onOpenImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final combined = [...extraReplies, ...comment.replies];
    final shown = combined.take(3).toList();
    final total = comment.repliesCount + extraReplies.length;
    final fill = InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.58);
    final style = Theme.of(context).textTheme.bodySmall;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          ContainerOrigin.capture(context, radius: 8, color: fill);
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final reply in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: _ReplyPreview(reply: reply, style: style, onOpenImage: onOpenImage),
                ),
              if (total > shown.length)
                Text(
                  '共${compactCount(total)}条回复 >',
                  style: style?.copyWith(color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the preview. Its links are only pictures: everything else here opens the floor, so
/// a tap elsewhere in the row still reaches the [InkWell] above.
class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.reply, required this.style, required this.onOpenImage});

  final Comment reply;
  final TextStyle? style;
  final void Function(List<Media> images, int index, String? heroTag) onOpenImage;

  void _open(String url, String? tag) {
    final target = sanitizeImageUrl(url);
    final index = reply.images.indexWhere(
      (image) => sanitizeImageUrl(image.url) == target || sanitizeImageUrl(image.previewUrl) == target,
    );
    if (index < 0) {
      onOpenImage([Media.image(url)], 0, tag);
    } else {
      onOpenImage(reply.images, index, tag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A picture the text already links is drawn as 查看图片 there; listing it again would repeat it.
    final extra = unlinkedPictures(reply);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichStatusText(
          prefix: TextSpan(text: '${reply.author.screenName}：', style: TextStyle(color: scheme.primary)),
          text: reply.text,
          style: style,
          maxLines: 2,
          inlineImages: false,
          onOpenImage: _open,
        ),
        if (extra.isNotEmpty)
          Wrap(
            spacing: 14,
            children: [
              for (final (index, _) in extra)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onOpenImage(reply.images, index, 'link-img-reply-${reply.id}-$index'),
                  child: ViewerHero(
                    tag: 'link-img-reply-${reply.id}-$index',
                    child: InlineLinkLabel(
                      icon: Icons.image_outlined,
                      label: '查看图片',
                      style: style?.copyWith(fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The 「评论 / 复制」 card a tap on a comment opens, grown out of the row that was tapped.
enum CommentAction { reply, copy }

Future<void> showCommentActions(
  BuildContext context,
  Comment comment, {
  required BuildContext anchor,
  required Future<void> Function() onReply,
}) async {
  final picked = await showGlassActions(
    context,
    anchor: anchor,
    originRadius: 14,
    actions: [
      StatusAction(
        icon: Icons.reply_rounded,
        label: '评论',
        detail: '回复 @${comment.author.screenName}',
        returns: CommentAction.reply,
      ),
      StatusAction(
        icon: Icons.copy_rounded,
        label: '复制',
        detail: '复制评论正文',
        returns: CommentAction.copy,
      ),
    ],
  );
  if (!context.mounted) return;
  switch (picked) {
    case CommentAction.reply:
      await onReply();
    case CommentAction.copy:
      await Clipboard.setData(ClipboardData(text: comment.text));
      Haptic.success.play();
      if (context.mounted) showMessage(context, '评论已复制');
    case null:
      return;
  }
}
