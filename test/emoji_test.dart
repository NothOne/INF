import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/emoji.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/widgets/mention_picker.dart';
import 'package:inf_flutter/core/widgets/rich_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _heart = 'https://face.t.sinajs.cn/t4/appstyle/expression/ext/normal/40/heart.png';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  test('a learned emoji survives a restart: the mapping is in Prefs, not in the cache', () async {
    EmojiStore.instance.learn({'[心]': _heart});
    expect(EmojiStore.instance.urlFor('[心]'), _heart);

    // What a cold start does: read the map back from SharedPreferences.
    EmojiStore.instance.init();
    expect(EmojiStore.instance.urlFor('[心]'), _heart);
    expect(EmojiStore.instance.urls, contains(_heart));
  });

  testWidgets('a post renders its emoji as a picture', (tester) async {
    EmojiStore.instance.learn({'[心]': _heart});
    await tester.pumpWidget(_host(RichStatusText(text: '爱了[心]', links: const {})));
    // The bracket code becomes an image widget, not loose text.
    expect(find.textContaining('[心]'), findsNothing);
    expect(
      tester.widgetList<Widget>(find.byType(Padding)).where((w) => w is Padding).length,
      greaterThan(0),
    );
  });

  testWidgets('the emoji panel lists the learned emoji', (tester) async {
    EmojiStore.instance.learn({'[心]': _heart});
    await tester.pumpWidget(_host(const EmojiPanel(height: 280)));
    // Not the empty placeholder: there is something to draw.
    expect(find.text('浏览微博时见到的表情会出现在这里'), findsNothing);
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('with nothing learned the panel says so rather than showing blank tiles', (tester) async {
    // A cold start with nothing on disk: the store reads an empty map rather than keeping what a
    // previous run learned.
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
    EmojiStore.instance.init();

    await tester.pumpWidget(_host(const EmojiPanel(height: 280)));
    expect(find.text('浏览微博时见到的表情会出现在这里'), findsOneWidget);
  });
}
