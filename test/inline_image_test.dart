import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/widgets/image_grid.dart';
import 'package:inf_flutter/core/widgets/rich_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('inlineImageUrls finds the picture links in a comment and nothing else', () {
    const text = '看图 https://wx1.sinaimg.cn/large/abc.jpg 还有 https://m.weibo.cn/sinaurl?u=https%3A%2F%2Fwx2.sinaimg.cn%2Forj360%2Fdef.png '
        '@小明 https://weibo.com/1234/abc';
    final urls = inlineImageUrls(text);
    expect(urls, hasLength(2));
    expect(urls.first, contains('abc.jpg'));
    expect(urls.last, contains('def.png'));
  });

  test('inlineImageUrls is empty for a reply that only talks', () {
    expect(inlineImageUrls('同意，转发微博'), isEmpty);
    expect(inlineImageUrl('https://video.weibo.com/show?fid=1034:1'), isNull);
  });

  group('over-9 pictures and mixed-media videos', () {
    test('completes pic_ids beyond the 9 entries m.weibo.cn puts in pics', () {
      final pids = [for (var i = 1; i <= 13; i++) '006dL2hTly1ij8jpulr7tj30u00cpd${i.toString().padLeft(2, '0')}'];
      final status = toStatus({
        'id': '5367306396107439',
        'text': '13张图测试',
        'created_at': 'Fri Nov 20 12:00:00 +0800 2026',
        'user': {'id': '5700099573', 'screen_name': '作者'},
        'pic_num': 13,
        'pic_ids': pids,
        'pics': [
          for (final pid in pids.take(9))
            {
              'pid': pid,
              'url': 'https://wx3.sinaimg.cn/orj360/$pid.jpg',
              'large': {'url': 'https://wx3.sinaimg.cn/mw2000/$pid.jpg', 'geo': {'width': 1080, 'height': 720}},
            },
        ],
      })!;

      expect(status.media, hasLength(13));
      expect(status.media[0].url, contains(pids[0]));
      expect(status.media[12].url, 'https://wx3.sinaimg.cn/large/${pids[12]}.jpg');
      expect(status.media[12].previewUrl, 'https://wx3.sinaimg.cn/orj360/${pids[12]}.jpg');
    });

    test('parses weibo.com mix_media_info with multiple pictures and videos in order', () {
      final status = toStatus({
        'id': '5367306396107439',
        'text': '图文混排',
        'created_at': 'Fri Nov 20 12:00:00 +0800 2026',
        'user': {'id': '5700099573', 'screen_name': '作者'},
        'pic_num': 4,
        'mix_media_info': {
          'items': [
            {
              'type': 'pic',
              'id': 'pid1',
              'data': {
                'bmiddle': {'url': 'https://wx3.sinaimg.cn/wap360/pid1.jpg'},
                'mw2000': {'url': 'https://wx3.sinaimg.cn/mw2000/pid1.jpg', 'width': 1080, 'height': 600},
              },
            },
            {
              'type': 'video',
              'id': '1034:1',
              'data': {
                'object_type': 'video',
                'page_pic': 'https://wx4.sinaimg.cn/orj480/v1.jpg',
                'media_info': {
                  'mp4_720p_mp4': 'https://f.video.weibocdn.com/v1.mp4',
                  'duration': 6,
                },
              },
            },
            {
              'type': 'video',
              'id': '1034:2',
              'data': {
                'object_type': 'video',
                'media_info': {
                  'mp4_hd_url': 'https://f.video.weibocdn.com/v2.mp4',
                  'duration': 12.5,
                  'big_pic_info': {'pic_big': {'url': 'https://wx4.sinaimg.cn/orj1080/v2.jpg'}},
                },
              },
            },
            {
              'type': 'pic',
              'id': 'pid2',
              'data': {
                'bmiddle': {'url': 'https://wx3.sinaimg.cn/wap360/pid2.jpg'},
                'largest': {'url': 'https://wx3.sinaimg.cn/large/pid2.jpg', 'width': 800, 'height': 800},
              },
            },
          ],
        },
      })!;

      expect(status.media, hasLength(4));
      expect(status.media.map((m) => m.kind).toList(), [
        MediaKind.image,
        MediaKind.video,
        MediaKind.video,
        MediaKind.image,
      ]);
      expect(status.media[1].url, 'https://f.video.weibocdn.com/v1.mp4');
      expect(status.media[1].previewUrl, 'https://wx4.sinaimg.cn/orj480/v1.jpg');
      expect(status.media[1].durationMs, 6000);
      expect(status.media[2].url, 'https://f.video.weibocdn.com/v2.mp4');
      expect(status.media[2].previewUrl, 'https://wx4.sinaimg.cn/orj1080/v2.jpg');
      expect(status.media[2].durationMs, 12500);
    });
  });

  group('multi-picture links inside repost chains', () {
    test('parses data-pids and url_struct pic_infos and merges them onto m.weibo.cn copy', () {
      const pid1 = '008KczEmly1ij3940pl3uj30u011pgpq';
      const pid2 = '008KczEmly1ij39418dypj30u012tgpr';
      const firstUrl = 'https://wx2.sinaimg.cn/large/$pid1.jpg';

      final mWeibo = toStatus({
        'id': '5366653686120773',
        'text':
            '//@泊舟渡长安:给不太了解希腊神话的朋友： <a href="https://weibo.cn/sinaurl?u=${Uri.encodeComponent(firstUrl)}"><span class="surl-text">查看图片</span></a>',
        'created_at': 'Fri Nov 20 12:00:00 +0800 2026',
        'user': {'id': '1404521940', 'screen_name': '转发者'},
      })!;

      final weiboCom = toStatus({
        'id': '5366653686120773',
        'text':
            '//@泊舟渡长安:给不太了解希腊神话的朋友： <a target="_blank" data-pids=$pid1,$pid2 href="$firstUrl">查看2张图片</a>',
        'created_at': 'Fri Nov 20 12:00:00 +0800 2026',
        'user': {'id': '1404521940', 'screen_name': '转发者'},
        'url_struct': [
          {
            'url_title': '查看2张图片',
            'short_url': 'http://t.cn/AXYkIiPH',
            'pic_ids': [pid1, pid2],
            'pic_infos': {
              pid1: {
                'bmiddle': {'url': 'http://wx2.sinaimg.cn/bmiddle/$pid1.jpg'},
                'large': {'url': 'http://wx2.sinaimg.cn/large/$pid1.jpg', 'width': 1080, 'height': 1357},
              },
              pid2: {
                'bmiddle': {'url': 'http://wx1.sinaimg.cn/bmiddle/$pid2.jpg'},
                'large': {'url': 'http://wx1.sinaimg.cn/large/$pid2.jpg', 'width': 1080, 'height': 1397},
              },
            },
          },
        ],
      })!;

      expect(weiboCom.links[firstUrl]?.images, hasLength(2));
      expect(weiboCom.links[firstUrl]?.images[1].url, contains(pid2));

      final merged = mergeStatusDetails(mWeibo, weiboCom);
      expect(merged.links[firstUrl]?.label, '查看2张图片');
      expect(merged.links[firstUrl]?.images, hasLength(2));
      expect(merged.links[firstUrl]?.images[0].url, contains(pid1));
      expect(merged.links[firstUrl]?.images[1].url, contains(pid2));
    });
  });

  group('StatusImageGrid overflow and full display', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'image_preload': ImagePreload.off.name});
      await Prefs.instance.init();
    });

    testWidgets('shows +N badge in capped mode while opening full media list, and shows all when uncapped',
        (tester) async {
      final media = [
        for (var i = 0; i < 13; i++)
          Media.image('https://wx3.sinaimg.cn/large/pic$i.jpg', previewUrl: 'https://wx3.sinaimg.cn/orj360/pic$i.jpg'),
      ];
      List<Media>? opened;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: StatusImageGrid(
              media: media,
              statusId: 's1',
              maxItems: 9,
              onOpen: (list, index, tag) => opened = list,
            ),
          ),
        ),
      ));

      expect(find.text('+4'), findsOneWidget);
      await tester.tap(find.text('+4'));
      expect(opened, hasLength(13));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: StatusImageGrid(
                media: media,
                statusId: 's1',
                maxItems: null,
                onOpen: (list, index, tag) => opened = list,
              ),
            ),
          ),
        ),
      ));

      expect(find.text('+4'), findsNothing);
      expect(find.byType(GestureDetector), findsNWidgets(13));
    });
  });
}
