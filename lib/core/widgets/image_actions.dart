import 'package:flutter/material.dart';

import 'status_actions.dart';

/// What can be done with a picture shown full screen, in the order and the groups every style shows
/// them — the same shape as a post's menu, so a long press behaves the same wherever it lands.
///
/// The rows only say what they are; the viewer runs them. A picture's actions all need the viewer's
/// own state (which page is showing, whether an original is still downloading, whether a save is
/// already running), so they cannot be closures over a model the way a post's are.
List<StatusAction> imageActions({
  /// Saving this picture, in whichever forms it has: a live photo offers all three, a still one.
  required List<StatusAction> save,
  /// Saving every picture in the viewer; null when there is only one.
  ({String label, VoidCallback run})? saveAll,
  required VoidCallback onShare,
  /// Loading the full-size file; null when the viewer is not offering it.
  ({VoidCallback run, bool enabled, String? detail})? original,
}) {
  return [
    ...save,
    if (saveAll != null)
      StatusAction(
        icon: Icons.collections_outlined,
        label: saveAll.label,
        startsGroup: true,
        run: () async => saveAll.run(),
      ),
    StatusAction(
      icon: Icons.ios_share_rounded,
      label: '分享图片',
      run: () async => onShare(),
    ),
    // Kept as a row even when it cannot run, rather than dropped: a menu whose rows move depending
    // on whether the original has downloaded would put a different action under the finger than the
    // one that was read a moment earlier.
    if (original != null)
      StatusAction(
        icon: Icons.hd_outlined,
        label: '查看原图',
        detail: original.detail,
        run: original.enabled ? () async => original.run() : null,
      ),
  ];
}
