import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/comment_store.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The comments a session sends, as any list of that post reads them.
///
/// What used to happen instead: the panel called the API itself and the caller reloaded the whole
/// thread, which is why a comment sent from the third page of a discussion came back at the top of
/// the first, and why a comment sent from the feed appeared on no screen at all.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  Status post([String? id]) => Status(
        id: id ?? 'p-${_mint++}',
        author: const User(id: 'u', screenName: '楼主'),
        text: '正文',
        createdAt: DateTime(2026),
      );

  test('a comment that has been sent is pending until a page containing it arrives', () {
    final status = post();
    CommentStore.instance.addPending(status, '第一条');

    final pending = CommentStore.instance.pendingFor(status.id);
    expect(pending, hasLength(1));
    expect(pending.single.text, '第一条');
    expect(CommentStore.instance.isPending(pending.single), isTrue);

    // A first page that does not include it — a hot-ordered list often does not — leaves it be.
    CommentStore.instance.settle(status.id, loaded: const []);
    expect(CommentStore.instance.pendingFor(status.id), hasLength(1));

    // Once the server's own copy of it shows up, the local one goes.
    final server = Comment(
      id: '5358955052142106',
      statusId: status.id,
      author: pending.single.author,
      text: '第一条',
      createdAt: DateTime(2026),
    );
    CommentStore.instance.settle(status.id, loaded: [server]);
    expect(CommentStore.instance.pendingFor(status.id), isEmpty);
  });

  test('a pending comment that never turns up is dropped once it is old', () {
    // Without this a copy whose confirmation never arrived would sit at the top of the list for
    // the rest of the session.
    final status = post();
    CommentStore.instance.addPending(status, '旧的一条');
    CommentStore.instance.settle(status.id, loaded: const [], staleAfter: Duration.zero);
    expect(CommentStore.instance.pendingFor(status.id), isEmpty);
  });

  test('a second comment sits above the first while both wait', () {
    final status = post();
    CommentStore.instance.addPending(status, '先发的');
    CommentStore.instance.addPending(status, '后发的');

    expect(
      CommentStore.instance.pendingFor(status.id).map((comment) => comment.text),
      ['后发的', '先发的'],
    );
  });

  test('pending comments belong to one post and are not shown under another', () {
    final a = post();
    final b = post();
    CommentStore.instance.addPending(a, '只在 A 下');

    expect(CommentStore.instance.pendingFor(b.id), isEmpty);
  });

  test('settling a post that has nothing pending is harmless', () {
    expect(() => CommentStore.instance.settle('never-commented'), returnsNormally);
  });

  test('a real comment from the server is not mistaken for a pending one', () {
    final real = Comment(
      id: '5358955052142106',
      statusId: 'p',
      author: const User(id: '9', screenName: '甲'),
      text: '服务器上的一条',
      createdAt: DateTime(2026),
    );
    expect(CommentStore.instance.isPending(real), isFalse);
  });

  test('server-confirmed comment added via addPosted is interactive and settles by id', () {
    final status = post();
    final created = Comment(
      id: '90001',
      statusId: status.id,
      author: const User(id: 'me', screenName: '我'),
      text: '已确认的评论',
      createdAt: DateTime.now(),
    );
    CommentStore.instance.addPosted(status.id, created);
    expect(CommentStore.instance.pendingFor(status.id), hasLength(1));
    expect(CommentStore.instance.isPending(created), isFalse);

    CommentStore.instance.settle(status.id, loaded: [created]);
    expect(CommentStore.instance.pendingFor(status.id), isEmpty);
  });

  test('pending replies under a root comment are tracked and settled independently', () {
    final status = post();
    final created = Comment(
      id: '91001',
      statusId: status.id,
      author: const User(id: 'me', screenName: '我'),
      text: '楼中楼回复',
      createdAt: DateTime.now(),
    );
    CommentStore.instance.addPendingReply('root-1', status.id, '楼中楼回复', created: created);
    expect(CommentStore.instance.pendingRepliesFor('root-1').map((c) => c.id), ['91001']);
    expect(CommentStore.instance.pendingFor(status.id), isEmpty);

    CommentStore.instance.settleReplies('root-1', loaded: [created]);
    expect(CommentStore.instance.pendingRepliesFor('root-1'), isEmpty);
  });

  test('local pending placeholder settles even when server adds a reply prefix or normalizes whitespace', () {
    final status = post();
    CommentStore.instance.addPending(status, '你好   世界');
    final copy = CommentStore.instance.pendingFor(status.id).single;
    final fromServer = Comment(
      id: '92001',
      statusId: status.id,
      author: copy.author,
      text: '回复@某人: 你好 世界',
      createdAt: DateTime.now(),
    );
    CommentStore.instance.settle(status.id, loaded: [fromServer]);
    expect(CommentStore.instance.pendingFor(status.id), isEmpty);
  });
}

int _mint = 0;
