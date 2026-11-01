import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/motion.dart';
import '../../core/chrome.dart';
import '../../core/container_route.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/parse.dart';
import '../../core/native.dart';
import '../../core/navigation.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';
import '../../core/share.dart';
import '../../core/status_store.dart';
import '../../core/touches.dart';
import 'avatar.dart';
import 'common.dart';
import 'image_grid.dart';
import 'rich_text.dart';
import 'smart_image.dart';

/// What can be done with a post: the card's long press and the detail page's menu. Sharing has
/// its own sheet, [showStatusShare].
Future<void> showStatusActions(BuildContext context, Status status, {VoidCallback? onLongImage}) {
  final own = status.author.id == Session.instance.uid;
  return showActionSheet<void>(
    context: context,
    frosted: false,
    builder: (sheetContext) {
      void run(VoidCallback action) {
        Navigator.pop(sheetContext);
        action();
      }

      void copy(String text) => run(() {
            Clipboard.setData(ClipboardData(text: text));
            Haptic.success.play();
            showMessage(context, '已复制');
          });

      return SafeArea(
        child: AnimatedBuilder(
          animation: StatusStore.instance,
          builder: (context, _) {
            final current = StatusStore.instance.apply(status);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onLongImage != null)
                  _ActionTile(icon: Icons.article_outlined, label: '生成长图', onTap: () => run(onLongImage)),
                _ActionTile(
                  icon: current.favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                  label: current.favorited ? '取消收藏' : '收藏',
                  onTap: () => run(() async {
                    final message = await StatusStore.instance.toggleFavorite(current);
                    if (context.mounted) showMessage(context, message);
                  }),
                ),
                _ActionTile(icon: Icons.copy_rounded, label: '复制文本', onTap: () => copy(status.text)),
                _ActionTile(icon: Icons.link_rounded, label: '复制链接', onTap: () => copy(statusLink(status.id))),
                _ActionTile(
                  icon: Icons.open_in_browser_rounded,
                  label: '在浏览器中打开',
                  onTap: () => run(() async {
                    if (!await Native.openUrl(statusLink(status.id)) && context.mounted) {
                      showMessage(context, '没有可以打开链接的浏览器');
                    }
                  }),
                ),
                if (!own && status.author.id.isNotEmpty) ...[
                  _ActionTile(
                    icon: Icons.block_rounded,
                    label: '屏蔽 @${status.author.screenName}',
                    onTap: () => run(() => _confirmBlock(context, status.author)),
                  ),
                  _ActionTile(
                    icon: Icons.report_outlined,
                    label: '投诉',
                    onTap: () => run(() => openWeb(context, statusReportLink(status.id))),
                  ),
                ],
                const SizedBox(height: 4),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> _confirmBlock(BuildContext context, User user) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('屏蔽 @${user.screenName}？'),
      content: const Text('列表里将不再显示 TA 的微博，进入 TA 的主页仍可查看。屏蔽只保存在本机，可在「设置 · 已屏蔽的用户」里解除。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('屏蔽')),
      ],
    ),
  );
  if (ok != true) return;
  await Prefs.instance.setBlocked(user, true);
  Haptic.success.play();
  if (context.mounted) showMessage(context, '已屏蔽 @${user.screenName}');
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      minLeadingWidth: 24,
      leading: Icon(icon, size: 21),
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      onTap: onTap,
    );
  }
}

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

  /// Opens this post's own page, which grows out of the card. On a phone the page's copy of the
  /// card starts exactly over this one, below the status bar and the page's toolbar. Beside the
  /// rail the card is laid out narrower than the full-screen page, so its text wraps differently
  /// and no copy can cover it: the page grows out of the card's shape instead.
  void _openSelf(String id) {
    final open = widget.onOpenStatus;
    if (open == null) return;
    if (WindowClass.of(context).wide) {
      ContainerOrigin.capture(context, radius: 12, color: Theme.of(context).colorScheme.surface);
    } else {
      final view = View.of(context);
      ContainerOrigin.capture(context, alignTop: view.padding.top / view.devicePixelRatio + kToolbarHeight);
    }
    open(id);
  }

  /// A 「…的微博视频」 link in the text is the video the post already carries: it plays here
  /// instead of opening the video's web page.
  ValueChanged<String>? _urlHandler(Status status) {
    final open = widget.onOpenUrl;
    final openMedia = widget.onOpenMedia;
    if (open == null) return null;
    return (url) {
      final index = status.media.indexWhere((media) => media.kind == MediaKind.video);
      final kind = status.links[url]?.kind;
      if (openMedia != null && index >= 0 && kind == LinkKind.video) {
        openMedia(status.media, index, null);
      } else if (kind == LinkKind.place && status.place != null) {
        openPlace(context, status.place!);
      } else {
        open(url);
      }
    };
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
    await showStatusActions(context, status, onLongImage: widget.onLongImage);
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
              // A birthday or medal post is only its card; an empty line would leave a gap.
              if (status.text.trim().isNotEmpty || status.isLongText)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.detail ? null : () => _openSelf(status.id),
                onLongPress: () => _openMenu(status),
                child: RichStatusText(
                  text: status.text,
                  links: status.links,
                  style: Theme.of(context).textTheme.bodyLarge,
                  maxLines: widget.detail ? 1000 : (status.isLongText ? 6 : 1000),
                  onMention: widget.onOpenUser,
                  onTopic: widget.onOpenTopic,
                  onUrl: _urlHandler(status),
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
              if (status.card != null) ...[
                const SizedBox(height: 9),
                _LinkCardView(card: status.card!, onOpen: () => _openCard(context, status, widget.onOpenUrl)),
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
                  onOpenUrl: _urlHandler(status.repostOf!),
                  onOpenMedia: widget.onOpenMedia,
                  heroEnabled: widget.enableImageHeroes,
                ),
              ],
              if (status.place != null) ...[
                const SizedBox(height: 7),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpenUrl == null ? null : () => openPlace(context, status.place!),
                  child: Row(
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
    final region = status.region?.trim() ?? '';
    final subtitleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 11.5,
        );
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
                  // A long client name gives way; the region always shows.
                  Flexible(
                    child: Text(source, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle),
                  ),
                  if (region.isNotEmpty) Text(' · $region', maxLines: 1, style: subtitleStyle),
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

/// A card without an address asks weibo.com's copy of the post for it; failing that, the post
/// can still be opened outside. Banners ask first even with one: m.weibo.cn's copy drops the
/// `mid` the birthday page needs, and that page is then empty.
Future<void> _openCard(BuildContext context, Status status, ValueChanged<String>? open) async {
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
class _LinkCardView extends StatelessWidget {
  const _LinkCardView({required this.card, required this.onOpen});

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
                  links: original.links,
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
              if (original.card != null) ...[
                const SizedBox(height: 8),
                _LinkCardView(card: original.card!, onOpen: () => _openCard(context, original, onOpenUrl)),
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