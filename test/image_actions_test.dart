import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inf_flutter/core/widgets/image_actions.dart';
import 'package:inf_flutter/core/widgets/status_actions.dart';

/// What a picture's long-press menu offers, in the order it offers it.
///
/// The same rows a post has, minus what does not apply to a picture, so a long press behaves alike
/// wherever it lands. The one thing worth pinning is that a row which cannot be used right now is
/// still drawn: dropping it would move the rows above it while a finger is on one.
void main() {
  StatusAction saveRow() => StatusAction(icon: Icons.download_rounded, label: '保存图片', run: () async {});

  test('a still picture offers save, share and the original', () {
    final rows = imageActions(
      save: [saveRow()],
      onShare: () {},
      original: (run: () {}, enabled: true, detail: null),
    );
    expect(rows.map((row) => row.label), ['保存图片', '分享图片', '查看原图']);
  });

  test('a live photo offers all three ways to save it, before anything else', () {
    final rows = imageActions(
      save: [
        StatusAction(icon: Icons.motion_photos_on_rounded, label: '保存实况照片', run: () async {}),
        StatusAction(icon: Icons.image_outlined, label: '仅保存图片', run: () async {}),
        StatusAction(icon: Icons.movie_outlined, label: '仅保存视频', run: () async {}),
      ],
      onShare: () {},
      original: (run: () {}, enabled: true, detail: null),
    );
    expect(rows.take(3).map((row) => row.label), ['保存实况照片', '仅保存图片', '仅保存视频']);
  });

  test('save-all only appears with more than one picture, and starts its own group', () {
    final one = imageActions(save: [saveRow()], onShare: () {});
    expect(one.where((row) => row.label.contains('保存全部')), isEmpty);

    final many = imageActions(
      save: [saveRow()],
      saveAll: (label: '保存全部 3 张', run: () {}),
      onShare: () {},
    );
    final all = many.firstWhere((row) => row.label == '保存全部 3 张');
    expect(all.startsGroup, isTrue);
  });

  test('the original row stays when it cannot be used, and says why', () {
    // Already the original: the row is there, it just cannot be picked.
    final rows = imageActions(
      save: [saveRow()],
      onShare: () {},
      original: (run: () {}, enabled: false, detail: '当前已是原图'),
    );
    final original = rows.firstWhere((row) => row.label == '查看原图');
    expect(original.run, isNull);
    expect(original.detail, '当前已是原图');
  });

  test('a picture with no larger file still keeps its rows steady', () {
    final rows = imageActions(save: [saveRow()], onShare: () {});
    expect(rows.map((row) => row.label), ['保存图片', '分享图片']);
  });
}
