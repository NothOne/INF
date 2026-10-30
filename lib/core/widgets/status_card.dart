import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/motion.dart';
import '../../core/chrome.dart';
import '../../core/container_route.dart';
import '../../core/haptics.dart';
import '../../core/models.dart';
import '../../core/parse.dart';
import '../../core/share.dart';
import '../../core/status_store.dart';
import '../../core/touches.dart';
import 'avatar.dart';
import 'common.dart';
import 'image_grid.dart';
import 'rich_text.dart';

/// One post, in a list or at the top of its own page. The card is the shared element between those
/// two places: the same widget grows into the detail page instead of a page sliding over a list.
class StatusCard extends StatefulWidget {
  const StatusCard({
    super.key,
    required this.status,
    this.detail = false,
    this.heroScope,
    this.enableImageHeroes = true,
    this.onOpenStatus,
    this.onOpenUser,
    this.onOpenTopic,
    this.onOpenUrl,
    this.onOpenMedia,
    this.onToggleLike,
    this.onRepost,
    this.onComment,
    this.onLongImage,
  });

  final Status status;
  final bool detail;
  final String? heroScope;
  final bool enableImageHeroes;
  final ValueChanged<String>? onOpenStatus;
  final ValueChanged<String>? onOpenUser;
  final ValueChanged<String>? onOpenTopic;
  final ValueChanged<String>? onOpenUrl;
  final void Function(List<Media> media, int index, String? heroTag)? onOpenMedia;
  final VoidCallback? onToggleLike;
  final VoidCallback? onRepost;
  final VoidCallback? onComment;
  final VoidCallback? onLongImage;

  @override
  State<StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<StatusCard> {
  @override
  void initState() {
    super.initState();
    StatusStore.instance.seed(widget.status);
  }

  /// Opens this post's own page, which grows out of the card: the page's copy of the card starts
  /// exactly over this one, below the status bar and the page's toolbar.
  void _openSelf(String id) {
    final open = widget.onOpenStatus;
    if (open == null) return;
    final view = View.of(context);
    ContainerOrigin.capture(context, alignTop: view.padding.top / view.devicePixelRatio + kToolbarHeight);
    open(id);
  }

  Future<void> _toggleLike(Status status) async {
    if (widget.onToggleLike != null) {
      widget.onToggleLike!();
      return;
    }
    final message = await StatusStore.instance.toggleLike(status);
    if (mounted) showMessage(context, message);
  }

  Future<void> _openMenu(Status status) async {
    if (Touches.multiTouch) return;
    Haptic.longPress.play();
    await showActionSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onLongImage != null)
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('生成长图'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onLongImage!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制文本'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: status.text));
                Haptic.success.play();
                Navigator.pop(sheetContext);
                showMessage(context, '已复制');
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('复制链接'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: statusLink(status.id)));
                Haptic.success.play();
                Navigator.pop(sheetContext);
                showMessage(context, '已复制');
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('分享…'),
              onTap: () {
                Navigator.pop(sheetContext);
                shareText(statusShareText(status));
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = StatusStore.instance.apply(widget.status);
    final scheme = Theme.of(context).colorScheme;
    final card = Material(
      color: scheme.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              onTap: widget.detail ? null : () => _openSelf(status.id),
              onLongPress: () => _openMenu(status),
              enableFeedback: false,
              child: const SizedBox.expand(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(status: status, detail: widget.detail, onOpenUser: widget.onOpenUser),
              const SizedBox(height: 9),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.detail ? null : () => _openSelf(status.id),
                onLongPress: () => _openMenu(status),
                child: RichStatusText(
                  text: status.text,
                  style: Theme.of(context).textTheme.bodyLarge,
                  maxLines: widget.detail ? 1000 : (status.isLongText ? 6 : 1000),
                  onMention: widget.onOpenUser,
                  onTopic: widget.onOpenTopic,
                  onUrl: widget.onOpenUrl,
                  inlineImages: status.repostOf == null,
                  onOpenImage: widget.onOpenMedia == null
                      ? null
                      : (url, tag) => widget.onOpenMedia!([Media.image(url)], 0, tag),
                ),
              ),
              if (status.isLongText && !widget.detail) ...[
                const SizedBox(height: 3),
                GestureDetector(
                  onTap: () => _openSelf(status.id),
                  child: Text(
                    '全文',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.primary),
                  ),
                ),
              ],
              if (status.article != null) ...[
                const SizedBox(height: 9),
                _ArticleCard(article: status.article!, onOpen: () => widget.onOpenUrl?.call(status.article!.url)),
              ],
              if (status.media.isNotEmpty) ...[
                const SizedBox(height: 9),
                StatusImageGrid(
                  media: status.media,
                  statusId: widget.heroScope ?? status.id,
                  onOpen: widget.onOpenMedia ?? (a, b, c) {},
                  enabled: widget.onOpenMedia != null,
                  heroEnabled: widget.enableImageHeroes,
                ),
              ],
              if (status.repostOf != null) ...[
                const SizedBox(height: 9),
                _RepostBlock(
                  original: status.repostOf!,
                  heroScope: widget.heroScope,
                  detail: widget.detail,
                  onOpen: () => widget.onOpenStatus?.call(status.repostOf!.id),
                  onOpenUser: widget.onOpenUser,
                  onOpenTopic: widget.onOpenTopic,
                  onOpenUrl: widget.onOpenUrl,
                  onOpenMedia: widget.onOpenMedia,
                  heroEnabled: widget.enableImageHeroes,
                ),
              ],
              if (status.place != null) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 15, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        status.place!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 2),
              _ActionBar(
                status: status,
                onToggleLike: () => _toggleLike(status),
                onRepost: widget.onRepost,
                onComment: widget.onComment,
              ),
            ],
          ),
        ),
        ],
      ),
    );
    return card;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status, required this.detail, this.onOpenUser});

  final Status status;
  final bool detail;
  final ValueChanged<String>? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final author = status.author;
    final time = relativeTime(status.createdAt);
    final source = (status.source == null || status.source!.isEmpty) ? time : '$time 来自 ${status.source}';
    final visibleRegion = detail ? status.region : null;
    final subtitle = (visibleRegion == null || visibleRegion.isEmpty) ? source : '$source · $visibleRegion';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => onOpenUser?.call(author.id),
          child: Avatar(url: author.avatarUrl, size: 40, verified: author.verified),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => onOpenUser?.call(author.id),
                child: Text(
                  author.screenName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15.5),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (status.pinned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: InfChrome.of(context).fill(scheme, scheme.primaryContainer, 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '置顶',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary),
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, required this.onOpen});

  final Article article;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.65),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (article.title.isNotEmpty)
                Text(
                  article.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              if (article.summary != null && article.summary!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  article.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '文章',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepostBlock extends StatelessWidget {
  const _RepostBlock({
    required this.original,
    this.heroScope,
    required this.detail,
    required this.onOpen,
    this.onOpenUser,
    this.onOpenTopic,
    this.onOpenUrl,
    this.onOpenMedia,
    this.heroEnabled = true,
  });

  final Status original;
  final String? heroScope;
  final bool detail;
  final VoidCallback onOpen;
  final ValueChanged<String>? onOpenUser;
  final ValueChanged<String>? onOpenTopic;
  final ValueChanged<String>? onOpenUrl;
  final void Function(List<Media> media, int index, String? heroTag)? onOpenMedia;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefix = original.author.screenName.isEmpty ? '' : '@${original.author.screenName}：';
    void open() {
      ContainerOrigin.capture(context, radius: 12, color: scheme.surfaceContainerHigh);
      onOpen();
    }

    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.62),
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: open,
              child: const SizedBox.expand(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: open,
                child: RichStatusText(
                  text: '$prefix${original.text}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: detail ? 1000 : (original.isLongText ? 6 : 1000),
                  onMention: onOpenUser,
                  onTopic: onOpenTopic,
                  onUrl: onOpenUrl,
                  inlineImages: true,
                  onOpenImage: onOpenMedia == null
                      ? null
                      : (url, tag) => onOpenMedia!([Media.image(url)], 0, tag),
                ),
              ),
              if (original.article != null) ...[
                const SizedBox(height: 8),
                _ArticleCard(article: original.article!, onOpen: () => onOpenUrl?.call(original.article!.url)),
              ],
              if (original.media.isNotEmpty) ...[
                const SizedBox(height: 8),
                StatusImageGrid(
                  media: original.media,
                  statusId: '${heroScope ?? original.id}-repost',
                  onOpen: onOpenMedia ?? (a, b, c) {},
                  enabled: onOpenMedia != null,
                  heroEnabled: heroEnabled,
                ),
              ],
            ],
          ),
        ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.status,
    required this.onToggleLike,
    this.onRepost,
    this.onComment,
  });

  final Status status;
  final VoidCallback onToggleLike;
  final VoidCallback? onRepost;
  final VoidCallback? onComment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionItem(
            icon: Icons.repeat_rounded,
            activeIcon: Icons.repeat_rounded,
            label: '转发',
            count: status.repostsCount,
            active: false,
            onTap: onRepost,
          ),
        ),
        Expanded(
          child: _ActionItem(
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_outline_rounded,
            label: '评论',
            count: status.commentsCount,
            active: false,
            onTap: onComment,
          ),
        ),
        Expanded(
          child: _ActionItem(
            icon: Icons.thumb_up_outlined,
            activeIcon: Icons.thumb_up_rounded,
            label: '赞',
            count: status.likesCount,
            active: status.liked,
            onTap: onToggleLike,
          ),
        ),
      ],
    );
  }
}

class _ActionItem extends StatefulWidget {
  const _ActionItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.count,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int count;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<_ActionItem> createState() => _ActionItemState();
}

class _ActionItemState extends State<_ActionItem> {
  bool _popped = false;

  Future<void> _tap() async {
    if (widget.onTap == null) return;
    setState(() => _popped = true);
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _popped = false);
    });
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.active ? scheme.primary : scheme.onSurfaceVariant;
    final text = widget.count > 0 ? compactCount(widget.count) : widget.label;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: widget.onTap == null ? null : _tap,
      child: SizedBox(
        height: 36,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: _popped ? 1.28 : 1,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutBack,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: const Duration(milliseconds: 160),
                builder: (context, value, child) => Icon(
                  widget.active ? widget.activeIcon : widget.icon,
                  size: 18,
                  color: value,
                ),
              ),
            ),
            const SizedBox(width: 5),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 170),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                text,
                key: ValueKey(text),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}