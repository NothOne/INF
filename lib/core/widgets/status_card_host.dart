import 'package:flutter/material.dart';

import '../api.dart';
import '../comment_store.dart';
import '../container_route.dart';
import '../entities.dart';
import '../models.dart';
import '../navigation.dart';
import '../parse.dart';
import '../prefs.dart';
import '../status_store.dart';
import 'comment_sheet.dart';
import 'status_card.dart';

/// A post in a list, wired to everything a tap on it can do.
///
/// Four lists show a [StatusCard] — the feed, `PagedStatusList`, the detail page and the long
/// picture page — and each of them used to write the same fifteen lines of callbacks: open the post
/// with itself as the seed, open a user, a topic, a link, a video or a picture, repost, comment. Any
/// new callback on the card had to be threaded through all four. This is that wiring once.
///
/// [heroScope] is what the card's Hero tags are namespaced by; it has to be unique per row, because
/// the same post can appear twice in one list (a repost and the post it reposts).
///
/// [interactive] is off where the card is only being drawn — the long picture — so a tap on it does
/// nothing instead of opening a page behind the picture being generated.
Widget buildStatusCard(
  BuildContext context,
  Status status, {
  required String heroScope,
  bool detail = false,
  bool interactive = true,
  String? detailStatusId,
  VoidCallback? onToggleLike,
  VoidCallback? onLongImage,
  bool saveAllButton = false,
  bool enableImageHeroes = true,
}) {
  if (!interactive) {
    return StatusCard(
      status: status,
      detail: detail,
      saveAllButton: saveAllButton,
      enableImageHeroes: enableImageHeroes,
      heroScope: heroScope,
      onOpenStatus: (_) {},
      onOpenUser: (_) {},
      onOpenTopic: (_) {},
      onOpenUrl: (_) {},
      onOpenMedia: (_, _, _) {},
    );
  }
  return StatusCard(
    status: status,
    detail: detail,
    saveAllButton: saveAllButton,
    enableImageHeroes: enableImageHeroes,
    heroScope: heroScope,
    onOpenStatus: (id) => openStatus(context, statusId: id, seed: status),
    onOpenUser: (uid) => openUser(context, uid),
    onOpenTopic: (name) => openTopic(context, name),
    onOpenUrl: (url) => openLink(context, url),
    onOpenMedia: (media, index, heroTag) {
      if (media[index].kind == MediaKind.video) {
        // The post the video came with, so a signature that has expired can be replaced.
        openVideo(context, media[index].url, coverUrl: media[index].previewUrl, statusId: detailStatusId ?? status.id);
      } else {
        final more = (media.length == 1 && heroTag != null && heroTag.startsWith('link-img-'))
            ? _resolveInlineImages(status, media.first.url)
            : null;
        openImage(context, media: media, index: index, heroTag: heroTag, moreImages: more);
      }
    },
    onToggleLike: onToggleLike,
    onRepost: (_) => openCompose(context, type: DraftType.repost, statusId: status.id),
    onComment: (anchor) {
      final current = StatusStore.instance.apply(status);
      if (detail) {
        showCommentSheet(context, anchor: anchor, status: current);
        return;
      }
      final hasComments = current.commentsCount > 0 || CommentStore.instance.pendingFor(current.id).isNotEmpty;
      if (hasComments) {
        if (current.isLongText) StatusStore.instance.longText(current.id).ignore();
        ContainerOrigin.capture(anchor, radius: 18);
        openStatus(context, statusId: current.id, seed: current, jumpToComments: true);
      } else {
        showCommentSheet(context, anchor: anchor, status: current);
      }
    },
    onLongImage: onLongImage,
  );
}

/// Whether a list should leave this post out: someone blocked on this device wrote it.
///
/// Its own function so the check is spelled the same way wherever a list asks — the feed and
/// `PagedStatusList` both skip a blocked author, and a profile page does not.
bool hiddenByBlock(Status status) => Prefs.instance.isBlocked(status.author.id);

Future<List<Media>> _resolveInlineImages(Status status, String imageUrl) async {
  final images = await WeiboApi.instance.resolveInlineImages(status.id, imageUrl);
  if (images.length <= 1) return images;
  final current = Entities.instance.status(status.id) ?? status;
  final key = current.links.keys.firstWhere(
    (k) => k == imageUrl || picIdOfUrl(k) == picIdOfUrl(imageUrl),
    orElse: () => imageUrl,
  );
  final existing = current.links[key];
  final updated = current.copyWith(
    links: {
      ...current.links,
      key: WeiboLink(
        url: key,
        label: '查看${images.length}张图片',
        kind: existing?.kind ?? LinkKind.web,
        images: images,
      ),
    },
  );
  StatusStore.instance.remember(updated, notify: true);
  return images;
}
