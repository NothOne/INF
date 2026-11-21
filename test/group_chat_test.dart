import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/image_url.dart';
import 'package:inf_flutter/core/look.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/theme.dart';
import 'package:inf_flutter/features/message/chat_cards.dart';
import 'package:inf_flutter/features/message/group_notice_page.dart';

void main() {
  group('webim group message parsing', () {
    test('parses text, image, live photo, GIF, video, and url_objects with cursor', () {
      final raw = {
        'messages': [
          {
            'id': 1005,
            'from_uid': 111,
            'from_user': {'screen_name': 'Alice', 'avatar_large': 'http://tva1.sinaimg.cn/a.jpg'},
            'content': 'hello group',
            'time': 1700000500,
          },
          {
            'id': 1004,
            'from_uid': 222,
            'content': '分享图片',
            'media_type': 1,
            'fids': [9001],
            'time': 1700000400,
          },
          {
            'id': 1003,
            'from_uid': 222,
            'content': '分享图片',
            'media_type': 1,
            'fids': [9002],
            'live_photo_video_fid': 9003,
            'time': 1700000300,
          },
          {
            'id': 1002,
            'from_uid': 333,
            'content': '[动画表情]',
            'pic_infos': {
              'p1': {
                'url': 'https://wx1.sinaimg.cn/large/gif1.gif',
                'thumbnail': 'https://wx1.sinaimg.cn/thumb/gif1.gif',
                'width': 240,
                'height': 240,
              },
            },
            'time': 1700000200,
          },
          {
            'id': 1001,
            'from_uid': 444,
            'content': '分享视频',
            'media_type': 10,
            'fids': [9010],
            'ext_text': '{"video_pic_fid":"9011"}',
            'time': 1700000100,
          },
          {
            'id': 1000,
            'from_uid': 555,
            'content': '看这条微博 http://t.cn/A6test1',
            'time': 1700000000,
            'url_objects': [
              {
                'url_ori': 'http://t.cn/A6test1',
                'info': {
                  'url_short': 'http://t.cn/A6test1',
                  'url_long': 'https://weibo.com/12345/Q123456',
                  'title': '微博正文',
                },
                'status': {
                  'id': '5000000000000001',
                  'text': '这是一条被分享到群里的微博内容',
                  'created_at': 'Thu Nov 19 10:00:00 +0800 2026',
                  'reposts_count': 12,
                  'comments_count': 34,
                  'attitudes_count': 56,
                  'user': {
                    'id': 12345,
                    'screen_name': '测试博主',
                    'verified': true,
                    'profile_image_url': 'https://tva1.sinaimg.cn/u.jpg',
                  },
                },
              },
            ],
          },
        ],
      };

      final page = parseWebimGroupMessages(raw, requestedCount: 6);
      expect(page.items, hasLength(6));
      expect(page.nextCursor, '999');

      // When fewer messages than requestedCount are returned, there are no older pages.
      expect(parseWebimGroupMessages(raw, requestedCount: 20).nextCursor, isNull);

      // 0: plain text
      final textMsg = page.items[0];
      expect(textMsg.id, '1005');
      expect(textMsg.senderId, '111');
      expect(textMsg.senderName, 'Alice');
      expect(textMsg.senderAvatar, 'https://tva1.sinaimg.cn/a.jpg');
      expect(textMsg.text, 'hello group');
      expect(textMsg.media, isNull);
      expect(textMsg.hasTextBesideMedia, isTrue);

      // 1: image
      final imgMsg = page.items[1];
      expect(imgMsg.media, isNotNull);
      expect(imgMsg.media!.isVideo, isFalse);
      expect(imgMsg.media!.fid, '9001');
      expect(imgMsg.media!.url, chatMssUrl('9001', imageOrigin: true));
      expect(imgMsg.hasTextBesideMedia, isFalse);

      // 2: live photo
      final liveMsg = page.items[2];
      expect(liveMsg.media, isNotNull);
      expect(liveMsg.media!.isLive, isTrue);
      expect(liveMsg.media!.liveVideoUrl, chatMssUrl('9003'));
      expect(liveMsg.media!.toMedia().isLive, isTrue);

      // 3: GIF sticker
      final gifMsg = page.items[3];
      expect(gifMsg.media, isNotNull);
      expect(gifMsg.media!.isGif, isTrue);
      expect(gifMsg.media!.width, 240);
      expect(gifMsg.media!.height, 240);
      expect(gifMsg.hasTextBesideMedia, isFalse);

      // 4: video with cover fid
      final videoMsg = page.items[4];
      expect(videoMsg.media, isNotNull);
      expect(videoMsg.media!.isVideo, isTrue);
      expect(videoMsg.media!.fid, '9010');
      expect(videoMsg.media!.url, chatMssUrl('9010'));
      expect(videoMsg.media!.coverFid, '9011');
      expect(videoMsg.media!.thumbnailUrl, chatMssUrl('9011', imageOrigin: true));
      expect(videoMsg.hasTextBesideMedia, isFalse);

      // 5: embedded Weibo status in url_objects
      final linkMsg = page.items[5];
      expect(linkMsg.links, hasLength(1));
      final meta = linkMsg.links.first;
      expect(meta.shortUrl, 'http://t.cn/A6test1');
      expect(meta.longUrl, 'https://weibo.com/12345/Q123456');
      expect(meta.status, isNotNull);
      expect(meta.status!.id, '5000000000000001');
      expect(meta.status!.author.screenName, '测试博主');
      expect(meta.status!.likesCount, 56);
    });
  });

  group('chat media meta & headers', () {
    test('parseChatMediaMeta extracts playable video fid, dimensions, duration, and thumbnail', () {
      final meta = parseChatMediaMeta({
        'fid': '9099',
        'extension': 'mp4',
        'videosize': '720x1280',
        'videotime': 18,
        'thumbnail_600': 'https://upload.api.weibo.com/thumb600.jpg',
      }, fallbackFid: '9010');

      expect(meta, isNotNull);
      expect(meta!.fid, '9099');
      expect(meta.extension, 'mp4');
      expect(meta.width, 720);
      expect(meta.height, 1280);
      expect(meta.durationSec, 18);
      expect(meta.thumbnail600, 'https://upload.api.weibo.com/thumb600.jpg?source=209678993');
    });

    test('weiboImageHeaders uses webim chat Referer for upload.api.weibo.com', () {
      final mssHeaders = weiboImageHeaders('https://upload.api.weibo.com/2/mss/msget?fid=123');
      expect(mssHeaders['Referer'], 'https://api.weibo.com/chat');

      final cdnHeaders = weiboImageHeaders('https://wx1.sinaimg.cn/mw690/abc.jpg');
      expect(cdnHeaders['Referer'], 'https://m.weibo.cn/');
    });
  });

  group('group info & full members parsing', () {
    test('parseGroupInfo and mergeWith preserve announcement, summary, avatar, and roles', () {
      final fromQuery = parseGroupInfo('88888', {
        'name': '测试交流群',
        'member_count': 120,
        'max_member': 500,
        'owner': 10001,
        'admins': [10002, 10003],
        'bulletin': {
          'content': '第一行公告\n第二行规则',
          'scheme': 'https://weibo.com/10001/Qabc',
          'time': 1700000000,
        },
        'summary': '欢迎文明交流',
      });
      final fromFull = parseGroupInfo('88888', {
        'name': '测试交流群',
        'round_avatar': 'http://tva1.sinaimg.cn/group.jpg',
        'member_count': 121,
        'max_member': 500,
        'owner': 10001,
        'admins': [10002],
        'bulletin': {'content': ''},
      });

      final merged = fromQuery.mergeWith(fromFull);
      expect(merged.name, '测试交流群');
      expect(merged.avatarUrl, 'https://tva1.sinaimg.cn/group.jpg');
      expect(merged.summary, '欢迎文明交流');
      expect(merged.notice, '第一行公告\n第二行规则');
      expect(merged.noticeScheme, 'https://weibo.com/10001/Qabc');
      expect(merged.noticeTime, 1700000000);
      expect(merged.memberCount, 121);
      expect(merged.isOwner('10001'), isTrue);
      expect(merged.isAdmin('10001'), isTrue);
      expect(merged.isAdmin('10002'), isTrue);
      expect(merged.isAdmin('99999'), isFalse);

      // When one endpoint carries a fuller announcement than the other, mergeWith keeps the longer text.
      final shorter = parseGroupInfo('88888', {
        'bulletin': {'content': '简短预览...'},
      });
      final fuller = parseGroupInfo('88888', {
        'bulletin': {'content': '这是一条完整的群公告内容，包含多条群规和详细说明。'},
      });
      expect(shorter.mergeWith(fuller).notice, '这是一条完整的群公告内容，包含多条群规和详细说明。');
    });

    test('parseGroupNotice preserves angle brackets in plain text and decodes HTML notices', () {
      expect(
        parseGroupNotice('群规 <禁止广告>\n1. 等级 < 5 的成员请先看公告 > 管理员'),
        '群规 <禁止广告>\n1. 等级 < 5 的成员请先看公告 > 管理员',
      );
      expect(
        parseGroupNotice('第一行<br/>第二行 &amp; 第三行'),
        '第一行\n第二行 & 第三行',
      );
      final withFull = parseGroupInfo('88888', {
        'bulletin': {
          'content': '短预览...',
          'full_content': '这是完整公告全文，远远长于短预览。',
        },
      });
      expect(withFull.notice, '这是完整公告全文，远远长于短预览。');
    });

    test('parseGroupMembers extracts jp/qp pinyin and deduplicates by uid', () {
      final members = parseGroupMembers({
        'member_infos': [
          {
            'uid': 10001,
            'screen_name': '张三',
            'avatar_large': 'http://tva1.sinaimg.cn/1.jpg',
            'jp': 'zs',
            'qp': 'zhangsan',
            'verified': true,
          },
          {
            'uid': 10001,
            'screen_name': '张三重复',
          },
          {
            'uid': 10002,
            'screen_name': '李四',
            'jp': 'ls',
            'qp': 'lisi',
          },
        ],
      });

      expect(members, hasLength(2));
      expect(members[0].uid, '10001');
      expect(members[0].jp, 'zs');
      expect(members[0].qp, 'zhangsan');
      expect(members[0].avatarUrl, 'https://tva1.sinaimg.cn/1.jpg');
      expect(members[1].uid, '10002');
      expect(members[1].jp, 'ls');
    });
  });

  group('chat UI widgets', () {
    Widget wrap(Widget child) => MaterialApp(
          theme: infTheme(Brightness.light, AccentTheme.values.first, InfLook.classic),
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('WeiboStatusChatCard displays author, body, repost quote, and counts', (tester) async {
      final status = Status(
        id: '5001',
        author: const User(id: '101', screenName: '科技日报', verified: true),
        text: '今天的群聊卡片测试正文内容',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        repostsCount: 24,
        commentsCount: 8,
        likesCount: 150,
        repostOf: Status(
          id: '5000',
          author: const User(id: '100', screenName: '原博主'),
          text: '原微博内容摘录',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );

      await tester.pumpWidget(wrap(WeiboStatusChatCard(status: status)));

      expect(find.text('科技日报'), findsOneWidget);
      expect(find.text('今天的群聊卡片测试正文内容'), findsOneWidget);
      expect(find.textContaining('@原博主: 原微博内容摘录'), findsOneWidget);
      expect(find.text('微博'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
    });

    testWidgets('GroupNoticePage shows full announcement and empty state', (tester) async {
      final infoWithNotice = GroupInfo(
        gid: '888',
        name: '前端群',
        notice: '这是完整的群公告内容，\n支持多行显示全部详情。',
        noticeTime: DateTime(2026, 11, 20, 14, 30).millisecondsSinceEpoch ~/ 1000,
        ownerId: '10001',
      );

      await tester.pumpWidget(wrap(GroupNoticePage(key: const ValueKey('full'), info: infoWithNotice, canEdit: false)));
      expect(find.text('群公告'), findsOneWidget);
      expect(find.text('前端群'), findsOneWidget);
      expect(find.textContaining('支持多行显示全部详情'), findsOneWidget);
      expect(find.text('编辑'), findsNothing);

      const emptyInfo = GroupInfo(gid: '888', name: '前端群', notice: '');
      await tester.pumpWidget(wrap(const GroupNoticePage(key: ValueKey('empty-readonly'), info: emptyInfo, canEdit: false)));
      expect(find.text('暂无群公告'), findsOneWidget);

      await tester.pumpWidget(wrap(const GroupNoticePage(key: ValueKey('empty-edit'), info: emptyInfo, canEdit: true)));
      expect(find.text('发布'), findsOneWidget);
    });
  });
}
