import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../haptics.dart';
import '../media_save.dart';
import '../models.dart';
import '../native.dart';
import '../navigation.dart' show openWeb;
import '../prefs.dart';
import '../session.dart';
import '../share.dart';
import '../status_store.dart';
import 'common.dart';

/// One row of a post's menu: what it says, and what it does. No widgets and no look of its own —
/// each style renders these in its own material, so the rows and their order are decided once for
/// every style rather than drifting apart between them.
@immutable
class StatusAction {
  const StatusAction({
    required this.icon,
    required this.label,
    this.detail,
    this.run,
    this.returns,
    this.destructive = false,
    this.startsGroup = false,
  });

  final IconData icon;
  final String label;

  /// A second line under [label], for a row whose meaning needs it ("回复 @某人").
  final String? detail;

  /// Runs the action. Called after the menu has closed, so anything it opens is not left behind a
  /// menu still on screen. Null when the row only reports itself through [returns].
  final Future<void> Function()? run;

  /// What the row hands back to whoever opened the menu, for a menu that asks a question rather
  /// than doing something — the comment card's "回复 / 复制" is one.
  final Object? returns;

  /// Drawn in the scheme's error colour, for the rows that act against the post's author.
  final bool destructive;

  /// Whether a divider belongs above this row. The menu groups what belongs together, because
  /// eight rows in one column is taller than a thumb reaches comfortably.
  final bool startsGroup;
}

/// What can be done with a post, in the order and the groups every style shows them.
///
/// [onLongImage] is the caller's own way of turning the post into a picture, which only a page
/// that can draw it can offer; leaving it out drops that row rather than showing a dead one.
List<StatusAction> statusActions(
  BuildContext context,
  Status status, {
  VoidCallback? onLongImage,
}) {
  final own = status.author.id == Session.instance.uid;
  final images = status.images;
  // Read now: the menu's rows describe the post as it is when the menu opens.
  final current = StatusStore.instance.apply(status);

  void copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    Haptic.success.play();
    showMessage(context, '已复制');
  }

  return [
    StatusAction(
      icon: current.favorited ? Icons.star_rounded : Icons.star_outline_rounded,
      label: current.favorited ? '取消收藏' : '收藏',
      run: () async {
        final message = await StatusStore.instance.toggleFavorite(current);
        if (context.mounted) showMessage(context, message);
      },
    ),
    StatusAction(
      icon: Icons.copy_rounded,
      label: '复制文本',
      run: () async => copy(status.text),
    ),
    StatusAction(
      icon: Icons.link_rounded,
      label: '复制链接',
      run: () async => copy(statusLink(status.id)),
    ),
    if (onLongImage != null)
      StatusAction(
        icon: Icons.article_outlined,
        label: '生成长图',
        startsGroup: true,
        run: () async => onLongImage(),
      ),
    if (images.isNotEmpty)
      StatusAction(
        icon: Icons.collections_outlined,
        label: saveAllLabel(images),
        // Its own group unless the long-picture row already started one.
        startsGroup: onLongImage == null,
        run: () => saveAllImages(context, images),
      ),
    StatusAction(
      icon: Icons.open_in_browser_rounded,
      label: '在浏览器中打开',
      startsGroup: onLongImage == null && images.isEmpty,
      run: () async {
        if (!await Native.openUrl(statusLink(status.id)) && context.mounted) {
          showMessage(context, '没有可以打开链接的浏览器');
        }
      },
    ),
    if (!own && status.author.id.isNotEmpty) ...[
      StatusAction(
        icon: Icons.block_rounded,
        label: '屏蔽 @${status.author.screenName}',
        destructive: true,
        startsGroup: true,
        run: () => confirmBlockUser(context, status.author),
      ),
      StatusAction(
        icon: Icons.report_outlined,
        label: '投诉',
        destructive: true,
        run: () async => openWeb(context, statusReportLink(status.id)),
      ),
    ],
  ];
}

/// Saves every picture under a post, saying how many made it.
Future<void> saveAllImages(BuildContext context, List<Media> images) async {
  showMessage(context, '正在保存 ${images.length} 张图片…');
  final result = await saveImagesToGallery(images);
  (result.saved == images.length ? Haptic.success : Haptic.error).play();
  if (!context.mounted) return;
  showMessage(context, saveAllMessage(result, images.length));
}

/// INF's own 屏蔽, kept on this device; Weibo is not told.
Future<void> confirmBlockUser(BuildContext context, User user) async {
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
