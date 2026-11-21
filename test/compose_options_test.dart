import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/api.dart';
import 'package:inf_flutter/core/look.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/theme.dart';
import 'package:inf_flutter/core/widgets/compose_options.dart';
import 'package:inf_flutter/features/compose/compose_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The composer's form fields and the sheets that choose them, away from the page that uses them.
///
/// `buildWeiboComPostFields` / `buildWeiboComRepostFields` are the whole of what a post sends to
/// weibo.com, so they are pinned here field by field: a rename on either side would otherwise only
/// show up as a post that goes out with no pictures, or with the wrong audience.

Map<String, dynamic> _decode(String? value) => jsonDecode(value!) as Map<String, dynamic>;

Map<String, dynamic> _media(Map<String, String> fields) => _decode(fields['media']);

void main() {
  group('buildWeiboComPostFields', () {
    test('plain text carries the content and the public visibility only', () {
      final fields = buildWeiboComPostFields(content: '今天天气不错');
      expect(fields['content'], '今天天气不错');
      expect(fields['visible'], '0');
      expect(fields.containsKey('pic_id'), isFalse);
      expect(fields.containsKey('need_transcode'), isFalse);
      expect(fields.containsKey('media'), isFalse);
      expect(fields.containsKey('mblog_statement'), isFalse);
    });

    test('pictures are a JSON list of pids, with transcoding asked for', () {
      final fields = buildWeiboComPostFields(content: '两张', picIds: ['p1', 'p2']);
      final pics = jsonDecode(fields['pic_id']!) as List;
      expect(pics, [
        {'type': 'image/jpeg', 'pid': 'p1'},
        {'type': 'image/jpeg', 'pid': 'p2'},
      ]);
      expect(fields['need_transcode'], '1');
      expect(fields.containsKey('media'), isFalse);
    });

    test('every visibility sends its weibo.com code', () {
      for (final visibility in PostVisibility.values) {
        final fields = buildWeiboComPostFields(content: 'x', visibility: visibility);
        expect(fields['visible'], '${visibility.code}', reason: visibility.name);
      }
      expect(buildWeiboComPostFields(content: 'x', visibility: PostVisibility.public)['visible'], '0');
      expect(buildWeiboComPostFields(content: 'x', visibility: PostVisibility.fans)['visible'], '10');
      expect(buildWeiboComPostFields(content: 'x', visibility: PostVisibility.friends)['visible'], '6');
      expect(buildWeiboComPostFields(content: 'x', visibility: PostVisibility.self)['visible'], '1');
    });

    test('a content declaration sends its code, and 无 sends nothing', () {
      expect(
        buildWeiboComPostFields(content: 'x', statement: ContentStatement.original)['mblog_statement'],
        '4',
      );
      expect(
        buildWeiboComPostFields(content: 'x', statement: ContentStatement.repost)['mblog_statement'],
        '3',
      );
      expect(buildWeiboComPostFields(content: 'x', statement: ContentStatement.ai)['mblog_statement'], '1');
      expect(
        buildWeiboComPostFields(content: 'x', statement: ContentStatement.fiction)['mblog_statement'],
        '2',
      );
      expect(
        buildWeiboComPostFields(content: 'x', statement: ContentStatement.none).containsKey('mblog_statement'),
        isFalse,
      );
    });

    test('a video replaces pictures: media JSON, no pic_id', () {
      final fields = buildWeiboComPostFields(
        content: '看这个',
        video: const VideoUploadResult(mediaId: 'm-1', coverPid: 'cover-1', coverUrl: 'https://x/c.jpg'),
      );
      final media = _media(fields);
      expect(media['type'], 'video');
      expect(media['media_id'], 'm-1');
      expect(media['titles'], [
        {'title': '看这个', 'default': 'true'},
      ]);
      expect(media['covers'], [
        {'pid': 'cover-1'},
      ]);
      expect(media['resource'], {'video_tail': false});
      expect(fields.containsKey('pic_id'), isFalse);
      expect(fields.containsKey('need_transcode'), isFalse);
    });

    test('a video title wins over the post text, and text backs up an untitled video', () {
      final titled = buildWeiboComPostFields(
        content: '正文',
        video: const VideoUploadResult(mediaId: 'm-1'),
        videoTitle: '  标题  ',
      );
      expect((_media(titled)['titles'] as List).first, {'title': '标题', 'default': 'true'});

      final untitled = buildWeiboComPostFields(content: '  ', video: const VideoUploadResult(mediaId: 'm-2'));
      expect((_media(untitled)['titles'] as List).first, {'title': '视频微博', 'default': 'true'});
    });

    test('a video with no cover says nothing about covers', () {
      final media = _media(buildWeiboComPostFields(content: 'x', video: const VideoUploadResult(mediaId: 'm-3')));
      expect(media.containsKey('covers'), isFalse);
    });

    test('a video and pictures together keep only the video', () {
      final fields = buildWeiboComPostFields(
        content: 'x',
        picIds: ['p1'],
        video: const VideoUploadResult(mediaId: 'm-4'),
      );
      expect(fields.containsKey('media'), isTrue);
      expect(fields.containsKey('pic_id'), isFalse);
    });
  });

  group('buildWeiboComRepostFields', () {
    test('a bare repost answers the ids and the two flags Weibo needs', () {
      final fields = buildWeiboComRepostFields(statusId: 's1', content: '转发理由', alsoComment: true);
      expect(fields['id'], 's1');
      expect(fields['comment'], '转发理由');
      expect(fields['is_comment'], '1');
      expect(fields['comment_ori'], '0');
      expect(fields['is_repost'], '0');
      expect(fields['visible'], '0');
      expect(fields.containsKey('pic_id'), isFalse);
    });

    test('同时评论 off sends 0', () {
      final fields = buildWeiboComRepostFields(statusId: 's1', content: '', alsoComment: false);
      expect(fields['is_comment'], '0');
      expect(fields['comment'], '');
    });

    test('pictures are a comma-separated list, and empty means no field at all', () {
      final withPics = buildWeiboComRepostFields(statusId: 's1', content: 'x', alsoComment: false, picIds: ['a', 'b']);
      expect(withPics['pic_id'], 'a,b');
      final none = buildWeiboComRepostFields(statusId: 's1', content: 'x', alsoComment: false);
      expect(none.containsKey('pic_id'), isFalse);
    });

    test('the visibility code goes through', () {
      for (final visibility in PostVisibility.values) {
        final fields = buildWeiboComRepostFields(
          statusId: 's1',
          content: 'x',
          alsoComment: false,
          visibility: visibility,
        );
        expect(fields['visible'], '${visibility.code}', reason: visibility.name);
      }
    });
  });

  group('Draft JSON', () {
    test('a draft keeps its visibility, declaration and video across a round trip', () {
      final draft = Draft(
        id: 7,
        type: DraftType.original,
        text: '带视频的草稿',
        images: const ['a.jpg'],
        videoPath: '/tmp/v.mp4',
        visibility: PostVisibility.friends,
        statement: ContentStatement.ai,
        updatedAt: DateTime(2026, 11, 21, 10, 30),
      );
      final back = Draft.fromJson(jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>);
      expect(back.visibility, PostVisibility.friends);
      expect(back.statement, ContentStatement.ai);
      expect(back.videoPath, '/tmp/v.mp4');
      expect(back.images, ['a.jpg']);
      expect(back.text, '带视频的草稿');
      expect(back.type, DraftType.original);
      expect(back.updatedAt, draft.updatedAt);
    });

    test('a legacy draft without the new fields reads as public, undelcared, no video', () {
      final back = Draft.fromJson({
        'id': 3,
        'type': 'repost',
        'text': '旧草稿',
        'statusId': 's9',
        'images': <String>[],
        'crossPost': true,
        'state': 'editing',
        'updatedAt': '2026-01-02T03:04:05.000',
      });
      expect(back.visibility, PostVisibility.public);
      expect(back.statement, ContentStatement.none);
      expect(back.videoPath, isNull);
      expect(back.crossPost, isTrue);
      expect(back.statusId, 's9');
    });

    test('a video-only draft is not empty', () {
      final draft = Draft(
        type: DraftType.original,
        videoPath: '/tmp/v.mp4',
        updatedAt: DateTime(2026),
      );
      expect(draft.isEmpty, isFalse);
      expect(Draft(type: DraftType.original, updatedAt: DateTime(2026)).isEmpty, isTrue);
    });
  });

  group('showVisibilityPicker', () {
    testWidgets('every option is offered and the chosen one comes back', (tester) async {
      final page = await _open<PostVisibility>(
        tester,
        (context) => showVisibilityPicker(context, PostVisibility.public),
      );

      expect(find.text('谁可以看'), findsOneWidget);
      for (final visibility in PostVisibility.values) {
        expect(find.text(visibility.label), findsWidgets, reason: visibility.name);
        if (visibility.description != visibility.label) {
          expect(find.text(visibility.description), findsOneWidget, reason: visibility.name);
        }
      }

      // 仅自己可见 is both the label and the description of that option; either row of the tile
      // opens the same one.
      await tester.tap(find.text('仅自己可见').first);
      await tester.pumpAndSettle();

      expect(page.answer, PostVisibility.self);
      expect(find.text('谁可以看'), findsNothing);
    });

    testWidgets('the current option is the one marked, and dismissing answers null', (tester) async {
      final page = await _open<PostVisibility>(
        tester,
        (context) => showVisibilityPicker(context, PostVisibility.fans),
      );

      final marked = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          if (tile.selected) (tile.title as Text).data,
      ];
      expect(marked, ['粉丝可见']);

      // Outside the sheet's own bounds, which is where a barrier tap lands.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(page.answer, isNull);
    });
  });

  group('showContentStatementPicker', () {
    testWidgets('every declaration is offered and the chosen one comes back', (tester) async {
      final page = await _open<ContentStatement>(
        tester,
        (context) => showContentStatementPicker(context, ContentStatement.none),
      );

      expect(find.text('内容声明'), findsOneWidget);
      for (final statement in ContentStatement.values) {
        expect(find.text(statement.label), findsOneWidget, reason: statement.name);
      }

      await tester.tap(find.text('内容由AI生成'));
      await tester.pumpAndSettle();

      expect(page.answer, ContentStatement.ai);
    });

    testWidgets('无 is marked when nothing is declared', (tester) async {
      await _open<ContentStatement>(
        tester,
        (context) => showContentStatementPicker(context, ContentStatement.none),
      );
      final marked = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          if (tile.selected) (tile.title as Text).data,
      ];
      expect(marked, ['无']);
    });
  });

  group('visibilityIcon', () {
    test('each option has its own glyph', () {
      expect(visibilityIcon(PostVisibility.public), Icons.public_rounded);
      expect(visibilityIcon(PostVisibility.fans), Icons.people_outline_rounded);
      expect(visibilityIcon(PostVisibility.friends), Icons.group_outlined);
      expect(visibilityIcon(PostVisibility.self), Icons.lock_outline_rounded);
    });
  });

  testWidgets('ComposePage body clears the AppBar when extendBodyBehindAppBar is active', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 800)
      ..padding = const FakeViewPadding(top: 44)
      ..viewPadding = const FakeViewPadding(top: 44);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: infTheme(Brightness.light, AccentTheme.brand, const InfLook(VisualStyle.glass)),
      home: const ComposePage(type: DraftType.repost, initialText: '//@甲:原评论'),
    ));
    await tester.pumpAndSettle();

    final appBar = tester.getRect(find.byType(AppBar));
    final field = tester.getRect(find.byType(TextField));
    expect(field.top, greaterThanOrEqualTo(appBar.bottom));
  });
}

/// A page whose one button opens [open] and remembers what it answered.
Future<_PageState<T>> _open<T>(WidgetTester tester, Future<T?> Function(BuildContext context) open) async {
  // The pickers play a haptic, which reads the haptics setting.
  SharedPreferences.setMockInitialValues({});
  await Prefs.instance.init();

  final key = GlobalKey<_PageState<T>>();
  await tester.pumpWidget(MaterialApp(
    theme: infTheme(Brightness.light, AccentTheme.brand),
    home: _Page<T>(key: key, open: open),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return key.currentState!;
}

class _Page<T> extends StatefulWidget {
  const _Page({super.key, required this.open});

  final Future<T?> Function(BuildContext context) open;

  @override
  State<_Page<T>> createState() => _PageState<T>();
}

class _PageState<T> extends State<_Page<T>> {
  T? answer;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              final value = await widget.open(context);
              if (mounted) setState(() => answer = value);
            },
            child: const Text('open'),
          ),
        ),
      );
}
