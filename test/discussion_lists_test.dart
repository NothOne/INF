import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/paging.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/widgets/comment_sheet.dart';
import 'package:inf_flutter/core/widgets/comment_tile.dart';
import 'package:inf_flutter/core/widgets/detail_bottom_bar.dart';
import 'package:inf_flutter/core/widgets/status_card_host.dart';
import 'package:inf_flutter/features/detail/discussion_lists.dart';
import 'package:inf_flutter/features/detail/status_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The discussion as a widget, after it was split out of `status_detail_page.dart`.
///
/// The split is only worth anything if the pieces still behave: a comment the reader just sent
/// must head the list, a pending one must not offer actions that need a server id, and switching
/// to 转发 must show the reposts rather than the comments.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  Status post() => Status(
        id: '77',
        author: const User(id: 'author', screenName: '楼主'),
        text: '正文',
        createdAt: DateTime(2026),
        commentsCount: 2,
      );

  Comment comment(String id, String text, {String? region, User? repliesTo}) => Comment(
        id: id,
        statusId: '77',
        author: const User(id: 'other', screenName: '别人'),
        text: text,
        createdAt: DateTime(2026),
        region: region,
        replyTo: repliesTo,
      );

  PagingController<Comment> comments(List<Comment> items) => PagingController<Comment>(
        fetch: (_) async => PageResult(items, null),
        id: (item) => item.id,
      );

  Widget host({
    required PagingController<Comment> comments,
    PagingController<Status>? reposts,
    bool showingReposts = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: DiscussionLists(
          status: post(),
          comments: comments,
          reposts: reposts ??
              PagingController<Status>(
                fetch: (_) async => const PageResult([], null),
                id: (status) => status.id,
              ),
          byTime: false,
          onSort: (_) {},
          showingReposts: showingReposts,
          onShowReposts: () {},
          onShowComments: () {},
          onComment: (_) {},
        ),
      ),
    );
  }

  testWidgets('comments render, and 转发 is what shows when that tab is picked', (tester) async {
    final pager = comments([comment('1', '第一条'), comment('2', '第二条')])..refresh();
    await tester.pumpWidget(host(comments: pager));
    await tester.pump();

    expect(find.byType(CommentTile), findsNWidgets(2));
    // The body is drawn as spans (mentions, topics and emoji are their own runs), so it is looked
    // for as rich text rather than as a plain Text.
    expect(find.text('第一条', findRichText: true), findsOneWidget);
  });

  testWidgets('a comment shows who it answered', (tester) async {
    final pager = comments([
      comment('1', '不同意', repliesTo: const User(id: 'x', screenName: '甲')),
    ])..refresh();
    await tester.pumpWidget(host(comments: pager));
    await tester.pump();

    expect(find.text('回复 甲：不同意', findRichText: true), findsOneWidget);
  });

  testWidgets('a comment whose text already starts with 回复@ is not double-prefixed', (tester) async {
    final pager = comments([
      comment('1', '回复@甲:不同意', repliesTo: const User(id: 'x', screenName: '甲')),
    ])..refresh();
    await tester.pumpWidget(host(comments: pager));
    await tester.pump();

    expect(find.text('回复@甲:不同意', findRichText: true), findsOneWidget);
    expect(find.textContaining('回复 甲：回复@甲', findRichText: true), findsNothing);
  });

  testWidgets('the repost list is shown instead of the comments', (tester) async {
    final reposts = PagingController<Status>(
      fetch: (_) async => PageResult([
        Status(
          id: '88',
          author: const User(id: 'r', screenName: '转的人'),
          text: '转了',
          createdAt: DateTime(2026),
        ),
      ], null),
      id: (status) => status.id,
    )..refresh();

    await tester.pumpWidget(host(comments: comments([]), reposts: reposts, showingReposts: true));
    await tester.pump();

    expect(find.text('转了', findRichText: true), findsOneWidget);
    expect(find.byType(CommentTile), findsNothing);
  });

  testWidgets('the bottom bar offers 写评论, and disables itself with nothing to comment on', (tester) async {
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: DetailBottomBar(
            liked: false,
            enabled: true,
            onComment: (_) => asked++,
            onRepost: () {},
            onLike: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('写评论…'));
    expect(asked, 1);
  });

  testWidgets('tapping a comment opens the reply sheet directly; long pressing opens the action menu at the finger', (tester) async {
    final pager = comments([comment('1', '这是一条测试评论')])..refresh();
    await tester.pumpWidget(host(comments: pager));
    await tester.pump();

    // Tap opens the comment reply sheet directly instead of the action menu.
    await tester.tap(find.text('这是一条测试评论', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.byType(CommentSheet), findsOneWidget);
    expect(find.text('复制评论正文'), findsNothing);

    // Dismiss the sheet, then long-press the comment to open the 「评论 / 复制」 action menu.
    Navigator.of(tester.element(find.byType(CommentSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(CommentSheet), findsNothing);

    await tester.longPress(find.text('这是一条测试评论', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('回复'), findsWidgets);
    expect(find.text('转发'), findsWidgets);
    expect(find.text('点赞'), findsOneWidget);
    expect(find.text('投诉'), findsOneWidget);
    expect(find.textContaining('分享'), findsNothing);
  });

  testWidgets('feed card comment button opens CommentSheet when 0 comments, and StatusDetailPage(jumpToComments) when >0', (tester) async {
    final zero = Status(
      id: '101',
      author: const User(id: 'u1', screenName: '甲'),
      text: '零评论微博',
      createdAt: DateTime(2026),
      commentsCount: 0,
    );
    final withComments = Status(
      id: '102',
      author: const User(id: 'u2', screenName: '乙'),
      text: '有评论微博',
      createdAt: DateTime(2026),
      commentsCount: 5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Builder(builder: (context) => buildStatusCard(context, zero, heroScope: 'z')),
              Builder(builder: (context) => buildStatusCard(context, withComments, heroScope: 'w')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // 0 comments -> opens CommentSheet directly.
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    expect(find.byType(CommentSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(CommentSheet))).pop();
    await tester.pumpAndSettle();

    // >0 comments -> opens StatusDetailPage with jumpToComments: true.
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CommentSheet), findsNothing);
    final page = tester.widget<StatusDetailPage>(find.byType(StatusDetailPage));
    expect(page.jumpToComments, isTrue);
  });
}
