import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/entities.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/status_store.dart';
import 'package:inf_flutter/core/widgets/status_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The flow P2 is accepted on: one post, seen from a list and from its page, reading one number.
///
/// This is the bug class the delta layer alone could not fix. [StatusStore] keeps "what this device
/// changed", so the numbers agreed; what did not travel was a *better copy*. A long post kept its
/// truncation in the list after the page had fetched the whole text, because the list's row held
/// the copy its parser produced and nothing was going to hand it another. [Entities] is where an
/// answer now lands, and these tests drive the screens that read it.
///
/// Nothing here calls [StatusStore.toggleLike]: it sends a request, and a widget test would wait on
/// it forever. What a like does to the numbers is `addComment`'s shape, which needs no network, and
/// is covered in `entities_test.dart`.
Status sample({
  String id = 'p1',
  String text = '六行的正文，后面还有…',
  bool long = true,

  /// What the list parsed: truncated, and with the counts as they were before the detail page asked
  /// again.
  int comments = 10,
  int likes = 100,
  int reposts = 5,
}) =>
    Status(
      id: id,
      author: const User(id: 'u1', screenName: '某人'),
      text: text,
      createdAt: DateTime(2026),
      isLongText: long,
      commentsCount: comments,
      likesCount: likes,
      repostsCount: reposts,
    );

Widget card(Status status) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatusCard(status: status, heroScope: 'row', onToggleLike: () {}),
        ),
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
    Entities.instance.clear();
  });

  testWidgets('the list draws the post the page fetched, without re-parsing anything', (tester) async {
    final fromList = sample(id: 'p1');

    await tester.pumpWidget(card(fromList));
    expect(find.textContaining('六行的正文'), findsOneWidget);

    // What the detail page's own request answered: the whole text, and the counts as the server
    // has them now.
    final whole = StatusStore.instance.remember(sample(
      id: 'p1',
      text: '六行的正文，后面还有…这是从详情页取回来的全文，比列表里那份长得多',
      long: false,
      comments: 12,
      likes: 101,
    ));

    // The list still holds the object it parsed; what changed is where a row reads from.
    final drawn = StatusStore.instance.apply(fromList);
    expect(drawn.text, whole.text);
    expect(drawn.commentsCount, 12);
    expect(drawn.likesCount, 101);
    expect(drawn.isLongText, isTrue, reason: 'a truncated copy in a list still offers 全文');
  });

  testWidgets('a row that is filed again keeps drawing the better copy', (tester) async {
    // Lists file what they parse. A page opened from the list may have got a better answer first,
    // so the list's own filing must not win just because it came later.
    StatusStore.instance.remember(sample(id: 'p2', text: '全文在这里，比列表那份长', long: false));
    final fromList = sample(id: 'p2');
    StatusStore.instance.remember(fromList);

    final drawn = StatusStore.instance.apply(fromList);
    expect(drawn.text, '全文在这里，比列表那份长');

    await tester.pumpWidget(card(fromList));
    expect(find.textContaining('全文在这里'), findsOneWidget);
  });

  testWidgets('a fresh answer does not undo what this device changed', (tester) async {
    final status = sample(id: 'p3', comments: 10);
    StatusStore.instance.seed(status);
    await tester.pumpWidget(card(status));

    // A comment posted from this device, with no request involved.
    StatusStore.instance.addComment(status);
    expect(StatusStore.instance.apply(status).commentsCount, 11);

    // The page's request was sent before the comment and answers after it, so it still says 10.
    final fromServer = sample(id: 'p3', comments: 10);
    StatusStore.instance.remember(fromServer);

    expect(StatusStore.instance.apply(fromServer).commentsCount, 11,
        reason: 'the comment is newer than the answer that predates it');
  });

  testWidgets('one post filed twice reads the same from both callers', (tester) async {
    final truncated = sample(id: 'p4');
    Entities.instance.put(truncated);
    Entities.instance.put(sample(id: 'p4', text: '全文在这里，比原来那份长', long: false));

    final first = StatusStore.instance.apply(truncated);
    final second = StatusStore.instance.apply(sample(id: 'p4'));
    expect(first.text, second.text);
    expect(first.text, '全文在这里，比原来那份长');
  });
}
