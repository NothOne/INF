import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';
import 'package:inf_flutter/core/widgets/app_logo.dart';

void main() {
  test('recommend channels are the type-1 groups, featured first', () {
    final channels = parseRecommendChannels({
      'groups': [
        {
          'title': '默认分组',
          'group_type': 0,
          'group': [
            {'gid': '100011', 'title': '全部关注'},
          ],
        },
        {
          'title': '我的频道',
          'group_type': 1,
          'group': [
            {'gid': '102803', 'containerid': '102803', 'title': '热门'},
            {'gid': '1028034388', 'containerid': '102803_ctg1_4388_-_ctg1_4388', 'title': '搞笑'},
          ],
        },
        {
          'title': '频道推荐',
          'group_type': 1,
          'group': [
            {'gid': '1028036388', 'containerid': '102803_ctg1_6388_-_ctg1_6388', 'title': '财经'},
            {'gid': '102803', 'containerid': '102803', 'title': '热门'},
          ],
        },
      ],
    });
    expect(channels.map((c) => c.title), ['热门', '推荐', '搞笑', '财经']);
    expect(channels.map((c) => c.featured), [true, true, true, false]);
    expect(channels.first.personal, isTrue);
    expect(channels.map((c) => c.key).toSet().length, channels.length);
    expect(channels[2].containerId, '102803_ctg1_4388_-_ctg1_4388');
  });

  test('weibo.com hottimeline statuses keep their video and region', () {
    final items = parseHotTimeline({
      'ok': 1,
      'statuses': [
        {
          'id': 5353705483277305,
          'idstr': '5353705483277305',
          'text': '视频',
          'created_at': 'Sun Nov 01 08:39:45 +0800 2026',
          'region_name': '发布于 浙江',
          'user': {'id': 1, 'screen_name': 'a'},
          'page_info': {
            'type': '11',
            'object_type': 'video',
            'page_pic': 'https://wx1.sinaimg.cn/a.jpg',
            'media_info': {'stream_url_hd': 'https://f.video.weibocdn.com/hd.mp4', 'duration': 12},
          },
        },
      ],
    });
    expect(items.single.media.single.kind, MediaKind.video);
    expect(items.single.media.single.url, 'https://f.video.weibocdn.com/hd.mp4');
    expect(items.single.card, isNull);
    expect(items.single.region, '发布于 浙江');
  });

  test('recommend channel survives a round trip', () {
    const channel = RecommendChannel(gid: '1028034388', containerId: '102803_ctg1_4388_-_ctg1_4388', title: '搞笑');
    final back = RecommendChannel.fromJson(channel.toJson());
    expect(back?.gid, channel.gid);
    expect(back?.containerId, channel.containerId);
    expect(RecommendChannel.fromJson(null), isNull);
    expect(RecommendChannel.fromJson(RecommendChannel.everyone.toJson())?.personal, isFalse);
    expect(RecommendChannel.fromJson(RecommendChannel.hot.toJson())?.personal, isTrue);
    // Saved by the version before 推荐 split off.
    expect(RecommendChannel.fromJson({'gid': '102803', 'containerid': '102803', 'title': '热门'})?.personal, isTrue);
  });

  testWidgets('InfLogo paints two coloured rings on a transparent background', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(Center(child: RepaintBoundary(key: key, child: const InfLogo(height: 76))));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late ui.Image image;
    late List<int> rgba;
    await tester.runAsync(() async {
      image = await boundary.toImage(pixelRatio: 2);
      rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = Platform.environment['INF_LOGO_PNG'];
      if (out != null) File(out).writeAsBytesSync(png!.buffer.asUint8List());
    });
    int alphaAt(double fx, double fy) {
      final x = (image.width * fx).round().clamp(0, image.width - 1);
      final y = (image.height * fy).round().clamp(0, image.height - 1);
      return rgba[(y * image.width + x) * 4 + 3];
    }

    expect(alphaAt(0.01, 0.01), 0, reason: 'corner is transparent');
    expect(alphaAt(0.5, 0.5), 0, reason: 'between the rings is transparent');
    var opaque = 0;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] > 200) opaque++;
    }
    expect(opaque, greaterThan(image.width * image.height ~/ 6));
  });
}
