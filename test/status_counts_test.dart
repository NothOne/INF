import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/entities.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/status_store.dart';

/// A post under its own id, so one test's counts cannot be another's. [StatusStore] is a singleton
/// with no reset, which is also why the ids are minted per call rather than shared.
///
/// The post is also filed into [Entities], because that is where `apply` reads the copy it draws
/// from — a test that only hands a `Status` around without filing it would be testing a state the
/// app never produces.
Status post({int comments = 0, int reposts = 0, String? id}) {
  final status = Status(
    id: id ?? 'post-${_mint++}',
    author: const User(id: 'u', screenName: '某人'),
    text: '正文',
    createdAt: DateTime(2026),
    commentsCount: comments,
    repostsCount: reposts,
  );
  Entities.instance.put(status);
  return status;
}

int _mint = 0;

/// A second copy of [status]: the same post, as a different list parsed it.
///
/// Not filed into [Entities] — that is the point. It stands for a copy a *caller* is holding, which
/// is what `apply` is given and what it must read through the stored post rather than trusting.
Status copyOf(Status status, {int? comments, int? reposts}) => Status(
      id: status.id,
      author: status.author,
      text: status.text,
      createdAt: status.createdAt,
      commentsCount: comments ?? status.commentsCount,
      repostsCount: reposts ?? status.repostsCount,
    );

/// Counts this device changed, as every screen reads them.
///
/// The detail page used to raise only its own copy of the post, so the card in the list behind it
/// showed the old number on the way back, and nothing at all was raised from a notification.
void main() {
  test('a comment raises the count every copy of the post sees', () {
    final before = post(comments: 12);
    final fromFeed = copyOf(before);

    StatusStore.instance.addComment(before);

    expect(StatusStore.instance.apply(before).commentsCount, 13);
    expect(StatusStore.instance.apply(fromFeed).commentsCount, 13,
        reason: 'a second copy of the same post is not a second comment');
  });

  test('two comments count as two', () {
    final status = post(comments: 3);
    StatusStore.instance.addComment(status);
    StatusStore.instance.addComment(status);

    expect(StatusStore.instance.apply(status).commentsCount, 5);
  });

  test('a server copy that already counted the comment is not counted twice', () {
    // The refresh comes back with the comment included; adding the change again would show one more
    // than exists.
    final status = post(comments: 20);
    StatusStore.instance.addComment(status);
    expect(StatusStore.instance.apply(status).commentsCount, 21);

    // A refresh replaces what is stored, the way a pager's answer does.
    final refreshed = StatusStore.instance.remember(copyOf(status, comments: 21));
    expect(StatusStore.instance.apply(refreshed).commentsCount, 21);
  });

  test('a comment on one post does not touch another', () {
    final a = post(comments: 5);
    final b = post(comments: 5);

    StatusStore.instance.addComment(a);

    expect(StatusStore.instance.apply(a).commentsCount, 6);
    expect(StatusStore.instance.apply(b).commentsCount, 5);
  });

  test('a repost raises the repost count and leaves comments alone', () {
    final status = post(comments: 4, reposts: 7);

    StatusStore.instance.addRepost(status);

    final applied = StatusStore.instance.apply(status);
    expect(applied.repostsCount, 8);
    expect(applied.commentsCount, 4);
  });

  test('a post the store has never seen is returned unchanged', () {
    final status = post(comments: 9);
    expect(identical(StatusStore.instance.apply(status), status), isTrue);
  });

  test('two local comments keep their total when the server has only accounted for one so far', () {
    final status = post(comments: 10);
    StatusStore.instance.addComment(status);
    StatusStore.instance.addComment(status);
    expect(StatusStore.instance.apply(status).commentsCount, 12);

    // Server catches up partially to 11; the second local comment must still be reflected.
    final partial = StatusStore.instance.remember(copyOf(status, comments: 11));
    expect(StatusStore.instance.apply(partial).commentsCount, 12);

    // Once the server reaches 12 (or more), the server count takes over cleanly.
    final caughtUp = StatusStore.instance.remember(copyOf(status, comments: 13));
    expect(StatusStore.instance.apply(caughtUp).commentsCount, 13);
  });
}
