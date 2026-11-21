import 'package:flutter/material.dart';

import '../../core/container_route.dart';
import '../../core/group_chat_api.dart';
import '../../core/link_preview.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/parse.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/rich_text.dart';
import '../../core/widgets/smart_image.dart';
import '../../core/widgets/viewer_hero.dart';

/// Renders an image (still, GIF, or Live Photo) or video bubble inside a chat conversation.
class ChatMediaBubble extends StatefulWidget {
  const ChatMediaBubble({
    super.key,
    required this.messageId,
    required this.media,
    required this.onOpenImage,
  });

  final String messageId;
  final ChatMedia media;
  final VoidCallback onOpenImage;

  @override
  State<ChatMediaBubble> createState() => _ChatMediaBubbleState();
}

class _ChatMediaBubbleState extends State<ChatMediaBubble> {
  ChatMediaMeta? _meta;
  String? _coverUrl;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void didUpdateWidget(ChatMediaBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.fid != widget.media.fid || oldWidget.media.coverFid != widget.media.coverFid) {
      _meta = null;
      _coverUrl = null;
      _loadMeta();
    }
  }

  Future<void> _loadMeta() async {
    final fid = widget.media.fid;
    if (fid == null || fid.isEmpty) return;
    final meta = await GroupChatApi.instance.mediaMeta(fid);
    if (!mounted) return;
    setState(() => _meta = meta);

    final coverFid = widget.media.coverFid;
    if (widget.media.isVideo && coverFid != null && coverFid.isNotEmpty) {
      final coverMeta = await GroupChatApi.instance.mediaMeta(coverFid);
      if (!mounted) return;
      final thumb = coverMeta?.thumbnail600 ?? coverMeta?.thumbnail240;
      if (thumb != null && thumb.isNotEmpty) {
        setState(() => _coverUrl = thumb);
      }
    }
  }

  double get _aspectRatio {
    final raw = widget.media.aspectRatio ?? _meta?.aspectRatio;
    if (raw == null) return widget.media.isVideo ? 16 / 10 : 4 / 3;
    return raw.clamp(0.55, 1.85);
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s < 10 ? '0$s' : '$s'}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isVideo || (_meta?.isVideo ?? false)) {
      return _buildVideo(context);
    }
    return _buildImage(context);
  }

  Widget _buildImage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = widget.media;
    final isGif = media.isGif || (_meta?.isGif ?? false);
    final previewUrl = _meta?.thumbnail600 ?? _meta?.thumbnail240 ?? media.thumbnailUrl;
    final displayUrl = media.url;
    final ratio = _aspectRatio;
    final width = ratio >= 1 ? 220.0 : (220.0 * ratio).clamp(132.0, 220.0);
    final height = (width / ratio).clamp(110.0, 270.0);
    final tag = 'chat:${widget.messageId}';

    return GestureDetector(
      onTap: widget.onOpenImage,
      child: ViewerHero(
        tag: tag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                SmartImage(
                  url: displayUrl,
                  placeholderUrl: previewUrl,
                  fit: BoxFit.cover,
                ),
                if (media.isLive)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _MediaPill(icon: Icons.motion_photos_on_rounded, label: '实况'),
                  )
                else if (isGif)
                  const Positioned(
                    right: 8,
                    bottom: 8,
                    child: _MediaPill(label: 'GIF'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = widget.media;
    final playableFid = (_meta?.fid.isNotEmpty ?? false) ? _meta!.fid : media.fid;
    final videoUrl = (playableFid != null && playableFid.isNotEmpty) ? chatMssUrl(playableFid) : media.url;
    final cover = _coverUrl ?? media.thumbnailUrl ?? _meta?.thumbnail600 ?? _meta?.thumbnail240;
    final duration = media.durationSec ?? _meta?.durationSec;
    final ratio = _aspectRatio;
    final width = ratio >= 1 ? 228.0 : (228.0 * ratio).clamp(144.0, 228.0);
    final height = (width / ratio).clamp(124.0, 260.0);

    return GestureDetector(
      onTap: () => openVideo(context, videoUrl, coverUrl: cover),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C20),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 0.6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null && cover.isNotEmpty)
                SmartImage(
                  url: cover,
                  fit: BoxFit.cover,
                  placeholderColor: const Color(0xFF1E2025),
                )
              else
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF242830), Color(0xFF15171C)],
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x14000000), Color(0x36000000), Color(0x66000000)],
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.52),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.72), width: 1.4),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: _MediaPill(icon: Icons.videocam_rounded, label: '视频'),
              ),
              if (duration != null && duration > 0)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _MediaPill(label: _formatDuration(duration)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPill extends StatelessWidget {
  const _MediaPill({this.icon, required this.label});

  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Link preview card shown inside chat messages.
///
/// Resolves via [LinkPreviews] and renders a tailored [WeiboStatusChatCard] for Weibo posts,
/// [WeiboUserChatCard] for user profiles, and a polished general preview card for all other URLs.
class ChatLinkCard extends StatelessWidget {
  const ChatLinkCard({
    super.key,
    required this.url,
    this.meta,
    required this.onOpenUrl,
  });

  final String url;
  final ChatLinkMeta? meta;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LinkPreview?>(
      future: LinkPreviews.instance.of(url, meta: meta),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        if (preview?.status != null) {
          return WeiboStatusChatCard(status: preview!.status!);
        }
        if (preview?.user != null) {
          return WeiboUserChatCard(user: preview!.user!);
        }
        if (loading && meta?.status != null) {
          return WeiboStatusChatCard(status: meta!.status!);
        }
        return GeneralLinkChatCard(
          url: preview?.url ?? meta?.targetUrl ?? url,
          preview: preview,
          loading: loading,
          onTap: () => onOpenUrl(preview?.url ?? meta?.targetUrl ?? url),
        );
      },
    );
  }
}

/// A dedicated compact Weibo post card rendered when a chat link points at a Weibo status.
class WeiboStatusChatCard extends StatelessWidget {
  const WeiboStatusChatCard({super.key, required this.status});

  final Status status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bodyText = status.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final repost = status.repostOf;
    final ownMedia = status.media;
    final displayMedia = ownMedia.isNotEmpty ? ownMedia : (repost?.media ?? const <Media>[]);
    final images = displayMedia.where((m) => m.kind == MediaKind.image).toList(growable: false);
    final video = displayMedia.where((m) => m.kind == MediaKind.video).firstOrNull;
    final hasStats = status.repostsCount > 0 || status.commentsCount > 0 || status.likesCount > 0;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 282),
      child: Builder(
        builder: (cardContext) => Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65), width: 0.75),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              ContainerOrigin.capture(cardContext, radius: 14);
              openStatus(context, statusId: status.id, seed: status);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Author header
                  Row(
                    children: [
                      Avatar(url: status.author.avatarUrl, size: 22, verified: status.author.verified),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          status.author.screenName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        relativeTime(status.createdAt),
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                  // Post body
                  if (bodyText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    RichStatusText(
                      text: bodyText,
                      maxLines: 3,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.92),
                        height: 1.38,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  // Quoted repost snippet (when reposting another post)
                  if (repost != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(color: scheme.primary.withValues(alpha: 0.55), width: 2.5),
                        ),
                      ),
                      child: Text(
                        '@${repost.author.screenName}: ${repost.text.replaceAll(RegExp(r'\s+'), ' ').trim()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11.5,
                          height: 1.32,
                        ),
                      ),
                    ),
                  ],
                  // Media strip (video cover, single photo, or up-to-3 thumbnail strip)
                  if (video != null) ...[
                    const SizedBox(height: 8),
                    _VideoThumbStrip(coverUrl: video.previewUrl.isNotEmpty ? video.previewUrl : null),
                  ] else if (images.length == 1) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        width: double.infinity,
                        height: 132,
                        child: SmartImage(url: images.first.previewUrl, fit: BoxFit.cover),
                      ),
                    ),
                  ] else if (images.length > 1) ...[
                    const SizedBox(height: 8),
                    _MultiImageStrip(images: images),
                  ],
                  // Footer bar
                  const SizedBox(height: 8),
                  Divider(height: 1, thickness: 0.5, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.article_outlined, size: 13, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        '微博',
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      if (hasStats) ...[
                        if (status.repostsCount > 0)
                          _MiniStat(icon: Icons.repeat_rounded, count: status.repostsCount),
                        if (status.commentsCount > 0) ...[
                          const SizedBox(width: 8),
                          _MiniStat(icon: Icons.chat_bubble_outline_rounded, count: status.commentsCount),
                        ],
                        if (status.likesCount > 0) ...[
                          const SizedBox(width: 8),
                          _MiniStat(icon: Icons.favorite_border_rounded, count: status.likesCount),
                        ],
                      ] else
                        Text(
                          '查看详情',
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
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

class _VideoThumbStrip extends StatelessWidget {
  const _VideoThumbStrip({this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverUrl != null && coverUrl!.isNotEmpty)
              SmartImage(url: coverUrl, fit: BoxFit.cover)
            else
              const ColoredBox(color: Color(0xFF1E2025)),
            const ColoredBox(color: Color(0x38000000)),
            Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1.2),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
              ),
            ),
            const Positioned(
              right: 6,
              bottom: 6,
              child: _MediaPill(icon: Icons.videocam_rounded, label: '视频'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiImageStrip extends StatelessWidget {
  const _MultiImageStrip({required this.images});

  final List<Media> images;

  @override
  Widget build(BuildContext context) {
    final shown = images.take(3).toList(growable: false);
    final extra = images.length - shown.length;
    return SizedBox(
      height: 76,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SmartImage(url: shown[i].previewUrl, fit: BoxFit.cover),
                    if (i == shown.length - 1 && extra > 0)
                      Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        alignment: Alignment.center,
                        child: Text(
                          '+$extra',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          compactCount(count),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontSize: 10.5),
        ),
      ],
    );
  }
}

/// Compact profile card for links pointing at a Weibo user.
class WeiboUserChatCard extends StatelessWidget {
  const WeiboUserChatCard({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bio = user.description;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 276),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65), width: 0.75),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openUser(context, user.id),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Avatar(url: user.avatarUrl, size: 42, verified: user.verified),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.screenName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(fontSize: 13.5),
                      ),
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          bio,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11.5),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        '微博用户',
                        style: textTheme.labelSmall?.copyWith(color: scheme.primary, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Preview card for general web links, topics, super-topics, articles, and third-party sites.
class GeneralLinkChatCard extends StatelessWidget {
  const GeneralLinkChatCard({
    super.key,
    required this.url,
    required this.preview,
    required this.loading,
    required this.onTap,
  });

  final String url;
  final LinkPreview? preview;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final site = preview?.site ?? Uri.tryParse(url)?.host ?? '';
    final title = preview?.title;
    final description = preview?.description;
    final picture = preview?.imageUrl;
    final kind = preview?.kind ?? LinkKind.web;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 282),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6), width: 0.75),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (loading && title == null) ...[
                        Container(
                          height: 13,
                          width: 150,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          height: 11,
                          width: 110,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ] else ...[
                        if (title != null && title.isNotEmpty)
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              height: 1.32,
                            ),
                          ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11.5,
                              height: 1.32,
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(linkKindIcon(kind), size: 13, color: scheme.primary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              site.isEmpty ? url : site,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall?.copyWith(color: scheme.primary, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (picture != null && picture.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  SmartImage(url: picture, width: 58, height: 58, radius: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
