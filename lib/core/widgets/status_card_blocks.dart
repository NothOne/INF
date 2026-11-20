import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/chrome.dart';
import '../../core/container_route.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/status_store.dart';
import 'audio_card.dart';
import 'image_grid.dart';
import 'rich_text.dart';
import 'smart_image.dart';

/// The pieces a post can carry under its words: an article, a link card (or a birthday banner), and
/// — when the post is a repost — the post it quotes.
///
/// They used to live inside `status_card.dart` with the card, its header and its action bar; a file
/// that has to be read whole before changing any one of them. Each is drawn by the card and by
/// nothing else, but each is a different kind of thing, so each is findable by name now.

class ArticleCard extends StatelessWidget {
  const ArticleCard({super.key, required this.article, required this.onOpen});

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

/// A card without an address asks weibo.com's copy of the post for it; failing that, the post
/// can still be opened outside. Banners ask first even with one: m.weibo.cn's copy drops the
/// `mid` the birthday page needs, and that page is then empty.
Future<void> openStatusCard(BuildContext context, Status status, ValueChanged<String>? open) async {
  final card = status.card;
  if (card == null || open == null) return;
  if (card.url.isNotEmpty && !card.banner) return open(card.url);
  String? url;
  try {
    url = await WeiboApi.instance.cardUrl(status.id);
  } catch (_) {}
  if (!context.mounted) return;
  url ??= card.url.isEmpty ? null : card.url;
  if (url != null) return open(url);
  await openLinkFallback(context, 'https://m.weibo.cn/detail/${status.id}', title: '没有找到这张卡片的链接');
}

/// A vote, a web page, a group and any other card m.weibo.cn attaches: picture, title, a line of
/// description and what kind of thing it is.
class LinkCardView extends StatelessWidget {
  const LinkCardView({super.key, required this.card, required this.onOpen});

  final LinkCard card;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (card.banner) return _banner(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.65),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Row(
          children: [
            if (card.imageUrl != null)
              SizedBox(
                width: 72,
                height: 72,
                child: SmartImage(url: card.imageUrl, fit: BoxFit.cover),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    if (card.summary != null && card.summary!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        card.summary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(linkKindIcon(card.kind), size: 13, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(card.typeLabel, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Both layers are drawn for a white page, so the card stays white in the dark theme too; the
  /// title goes in the blank band the foreground leaves under its picture.
  Widget _banner(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                if (card.backgroundUrl != null)
                  SmartImage(url: card.backgroundUrl, fit: BoxFit.cover, placeholderColor: Colors.transparent),
                SmartImage(url: card.imageUrl, fit: BoxFit.cover, placeholderColor: Colors.transparent),
                if (card.title.isNotEmpty)
                  Align(
                    alignment: const Alignment(0, 0.42),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        card.title,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF333333),
                          fontSize: constraints.maxWidth * 0.042,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusRepostBlock extends StatelessWidget {
  const StatusRepostBlock({
    super.key,
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

    // Tapping anywhere here opens the original's own page, which shows it whole; see
    // [_StatusCardState._prefetch]. This block opens it from a detail page too.
    void prefetch() {
      if (original.isLongText) StatusStore.instance.longText(original.id).ignore();
    }

    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.62),
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTapDown: detail ? null : (_) => prefetch(),
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
                onTapDown: detail ? null : (_) => prefetch(),
                onTap: open,
                child: RichStatusText(
                  text: '$prefix${original.text}',
                  links: original.links,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: detail ? 1000 : (original.isLongText ? 6 : 1000),
                  onMention: onOpenUser,
                  onTopic: onOpenTopic,
                  onUrl: onOpenUrl,
                  inlineImages: true,
                  onOpenImages: onOpenMedia == null
                      ? null
                      : (images, index, tag) => onOpenMedia!(images, index, tag),
                ),
              ),
              if (original.audio != null) ...[
                const SizedBox(height: 8),
                AudioCard(audio: original.audio!, statusId: original.id),
              ],
              if (original.article != null) ...[
                const SizedBox(height: 8),
                ArticleCard(article: original.article!, onOpen: () => onOpenUrl?.call(original.article!.url)),
              ],
              if (original.card != null) ...[
                const SizedBox(height: 8),
                LinkCardView(card: original.card!, onOpen: () => openStatusCard(context, original, onOpenUrl)),
              ],
              if (original.media.isNotEmpty) ...[
                const SizedBox(height: 8),
                StatusImageGrid(
                  media: original.media,
                  statusId: '${heroScope ?? original.id}-repost',
                  onOpen: onOpenMedia ?? (a, b, c) {},
                  enabled: onOpenMedia != null,
                  heroEnabled: heroEnabled,
                  maxItems: detail ? null : 9,
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
