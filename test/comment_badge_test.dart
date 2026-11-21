import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/share.dart';
import 'package:inf_flutter/core/widgets/comment_tile.dart';
import 'package:inf_flutter/core/widgets/smart_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  group('CommentBadge parsing', () {
    test('toComment reads comment_badge from the comments_hotflow fixture', () {
      final raw = jsonDecode(File('test/fixtures/comments_hotflow.json').readAsStringSync()) as Map<String, dynamic>;
      final page = parseCommentPage(raw['data'], '4900000000000000');
      final withBadges = page.items.where((c) => c.badges.isNotEmpty).toList();
      expect(withBadges, isNotEmpty);
      for (final comment in withBadges) {
        for (final badge in comment.badges) {
          expect(badge.url, startsWith('http'));
          expect(badge.aspect, greaterThan(0.2));
        }
      }
    });

    test('toComment ignores malformed or non-http badges and keeps valid aspect', () {
      final comment = toComment({
        'id': '100',
        'text': '测试',
        'created_at': 'Sat Nov 21 16:00:00 +0800 2026',
        'user': {'id': 'u1', 'screen_name': '测试用户'},
        'comment_badge': [
          {'pic_url': 'https://h5.sinaimg.cn/upload/114/962/2022/07/08/member_3_bigfan3_1.png', 'length': 2.1, 'name': 'loyal_fans'},
          {'pic_url': 'not-a-url', 'length': 1.5, 'name': 'bad'},
          {'pic_url': 'https://h5.sinaimg.cn/upload/blogger.png', 'length': 99, 'name': 'blogger'},
        ],
      }, 's1');

      expect(comment, isNotNull);
      expect(comment!.badges, hasLength(2));
      expect(comment.badges[0].aspect, closeTo(2.1, 0.001));
      expect(comment.badges[0].name, 'loyal_fans');
      // Out-of-range aspect falls back to 1.33.
      expect(comment.badges[1].aspect, closeTo(1.33, 0.001));
    });
  });

  group('commentRepostText', () {
    Status post({Status? repostOf}) => Status(
          id: 's1',
          author: const User(id: 'a1', screenName: '博主'),
          text: '原微博内容',
          createdAt: DateTime(2026),
          repostOf: repostOf,
        );

    Comment comment(String id, String name, String text) => Comment(
          id: id,
          statusId: 's1',
          author: User(id: 'u-$id', screenName: name),
          text: text,
          createdAt: DateTime(2026),
        );

    test('quotes the comment author and text for a top-level comment on an original post', () {
      expect(
        commentRepostText(comment('c1', '甲', '说得对'), post()),
        '//@甲:说得对',
      );
    });

    test('includes the thread root when forwarding a floor reply', () {
      expect(
        commentRepostText(
          comment('c2', '乙', '同意楼上'),
          post(),
          rootComment: comment('c1', '甲', '第一条'),
        ),
        '//@乙:同意楼上 //@甲:第一条',
      );
    });

    test('appends the reposted status chain when forwarding a comment on a repost', () {
      final origin = Status(
        id: 's0',
        author: const User(id: 'a0', screenName: '源作者'),
        text: '源正文',
        createdAt: DateTime(2026),
      );
      expect(
        commentRepostText(comment('c1', '甲', '评论'), post(repostOf: origin)),
        '//@甲:评论 //@博主:原微博内容',
      );
    });
  });

  group('CommentTile badges & actions', () {
    testWidgets('renders CommentBadge inline beside the username without overflow', (tester) async {
      final comment = Comment(
        id: 'c1',
        statusId: 's1',
        author: const User(id: 'u1', screenName: '名字特别特别长的一个金粉测试用户'),
        text: '这是一条带金粉标识的评论',
        createdAt: DateTime(2026),
        badges: const [
          CommentBadge(url: 'https://example.com/gold_fan.png', aspect: 2.0, name: 'loyal_fans'),
          CommentBadge(url: 'https://example.com/blogger.png', aspect: 1.5, name: 'blogger'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: CommentTile(
                comment: comment,
                onOpenUser: (_) {},
                onOpenTopic: (_) {},
                onOpenUrl: (_) {},
                onOpenFloor: () {},
                onReply: (_) {},
                onOpenImage: (_, _, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final badgeImages = tester.widgetList<SmartImage>(find.byType(SmartImage)).where(
            (img) => img.url == 'https://example.com/gold_fan.png' || img.url == 'https://example.com/blogger.png',
          );
      expect(badgeImages, hasLength(2));
    });

    testWidgets('showCommentActions offers 复制, 回复, 转发, 点赞, 投诉', (tester) async {
      final status = Status(
        id: 's1',
        author: const User(id: 'a1', screenName: '博主'),
        text: '正文',
        createdAt: DateTime(2026),
      );
      final comment = Comment(
        id: 'c1',
        statusId: 's1',
        author: const User(id: 'other-user', screenName: '路人'),
        text: '测试评论',
        createdAt: DateTime(2026),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showCommentActions(
                    context,
                    comment: comment,
                    status: status,
                    anchor: context,
                    pointer: const Offset(200, 300),
                    onReply: () {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('复制'), findsOneWidget);
      expect(find.text('回复'), findsOneWidget);
      expect(find.text('转发'), findsOneWidget);
      expect(find.text('点赞'), findsOneWidget);
      expect(find.text('投诉'), findsOneWidget);
    });
  });
}
