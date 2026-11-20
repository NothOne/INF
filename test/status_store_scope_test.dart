import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/comment_store.dart';
import 'package:inf_flutter/core/entities.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/relation_store.dart';
import 'package:inf_flutter/core/session.dart';
import 'package:inf_flutter/core/status_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which rows rebuild when one post changes.
///
/// Every list used to listen to the store itself, so liking one post rebuilt the whole screen — on a
/// feed that is every visible card, with its pictures, for one tap. [StatusStore.of] is the fix: a
/// row hears about its own post and nothing else.
///
/// These tests drive the store with [StatusStore.addComment] and [StatusStore.addRepost], which are
/// the writes that need no network; `toggleLike` sends a request and is covered by its own tests.
/// What is being counted here is rebuilds, which is the only way this can be checked.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  Status post(String id) => Status(
        id: id,
        author: User(id: 'u-$id', screenName: '某人'),
        text: '正文 $id',
        createdAt: DateTime(2026),
      );

  /// Draws [id]'s comment count and records every rebuild.
  Widget counter(String id, Map<String, int> builds) => AnimatedBuilder(
        animation: StatusStore.instance.of([id]),
        builder: (context, _) {
          builds[id] = (builds[id] ?? 0) + 1;
          return Text('$id ${StatusStore.instance.apply(post(id)).commentsCount}',
              textDirection: TextDirection.ltr);
        },
      );

  testWidgets('a change to one post rebuilds only that post', (tester) async {
    final builds = <String, int>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [counter('a', builds), counter('b', builds), counter('c', builds)]),
      ),
    );
    expect(builds, {'a': 1, 'b': 1, 'c': 1});

    StatusStore.instance.addComment(post('b'));
    await tester.pump();

    expect(builds['a'], 1, reason: 'post a did not change');
    expect(builds['b'], 2, reason: 'post b is the one that changed');
    expect(builds['c'], 1, reason: 'post c did not change');
  });

  testWidgets('one post can be watched by more than one row', (tester) async {
    // The same post appears twice in a list when one entry is a repost of it.
    final builds = <String, int>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [counter('dup', builds), counter('dup', builds)]),
      ),
    );
    expect(builds['dup'], 2);

    StatusStore.instance.addRepost(post('dup'));
    await tester.pump();
    expect(builds['dup'], 4, reason: 'both copies of the post see the change');
  });

  testWidgets('a disposed listener stops being woken and leaves no entry behind', (tester) async {
    final builds = <String, int>{};
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: counter('gone', builds)),
    );
    expect(StatusStore.instance.scopedListenerCount, 1);
    expect(StatusStore.instance.scopedKeyCount, 1);

    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
    );
    expect(StatusStore.instance.scopedListenerCount, 0, reason: 'unmounted widgets must not leak listeners');
    expect(StatusStore.instance.scopedKeyCount, 0, reason: 'empty id buckets must be pruned');

    StatusStore.instance.addComment(post('gone'));
    await tester.pump();
    expect(builds['gone'], 1);
  });

  testWidgets('rebuilding a widget with a fresh StatusStore.of() does not accumulate listeners', (tester) async {
    final builds = <String, int>{};
    for (var i = 0; i < 20; i++) {
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: counter('churn-$i', builds)),
      );
    }
    expect(StatusStore.instance.scopedListenerCount, 1);
    expect(StatusStore.instance.scopedKeyCount, 1);
  });

  testWidgets('remember with notify wakes mounted cards watching that post', (tester) async {
    final original = post('full-text-id');
    StatusStore.instance.seed(original);
    String? drawnText;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: AnimatedBuilder(
          animation: StatusStore.instance.of(['full-text-id']),
          builder: (context, _) {
            drawnText = StatusStore.instance.apply(original).text;
            return Text(drawnText!, textDirection: TextDirection.ltr);
          },
        ),
      ),
    );
    expect(drawnText, '正文 full-text-id');

    StatusStore.instance.remember(
      original.copyWith(text: '正文 full-text-id 展开后的完整长文本'),
      notify: true,
    );
    await tester.pump();
    expect(drawnText, '正文 full-text-id 展开后的完整长文本');
  });

  test('logout resets all account-scoped stores', () async {
    final status = post('acct-1');
    StatusStore.instance.seed(status);
    StatusStore.instance.addComment(status);
    CommentStore.instance.addPending(status, '刚发的评论');
    RelationStore.instance.reset();

    expect(Entities.instance.status('acct-1'), isNotNull);
    expect(StatusStore.instance.apply(status).commentsCount, 1);
    expect(CommentStore.instance.pendingFor('acct-1'), hasLength(1));

    await Session.instance.logout();

    expect(Entities.instance.status('acct-1'), isNull);
    expect(StatusStore.instance.apply(status).commentsCount, 0);
    expect(CommentStore.instance.pendingFor('acct-1'), isEmpty);
  });

  testWidgets('a row watching nothing never rebuilds', (tester) async {
    var built = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: AnimatedBuilder(
          animation: StatusStore.instance.of(const []),
          builder: (context, _) {
            built++;
            return const SizedBox();
          },
        ),
      ),
    );
    final before = built;

    StatusStore.instance.addComment(post('anything'));
    await tester.pump();
    expect(built, before);
  });

  test('a post the store has never seen is returned as it was', () {
    final status = post('untouched-id');
    expect(identical(StatusStore.instance.apply(status), status), isTrue);
  });

  test('seed does not allocate like-state entries for untouched posts', () {
    StatusStore.instance.reset();
    for (var i = 0; i < 50; i++) {
      StatusStore.instance.seed(post('seen-$i'));
    }
    expect(StatusStore.instance.likeStateCount, 0);
  });

  test('status state maps are bounded to StatusStore.instance.stateKept', () {
    StatusStore.instance.reset();
    final cap = StatusStore.instance.stateKept;
    for (var i = 0; i < cap + 40; i++) {
      StatusStore.instance.addComment(post('cap-$i'));
    }
    // Oldest entries were evicted, newest entries stay intact.
    expect(StatusStore.instance.apply(post('cap-0')).commentsCount, 0);
    expect(StatusStore.instance.apply(post('cap-${cap + 39}')).commentsCount, 1);
  });
}
