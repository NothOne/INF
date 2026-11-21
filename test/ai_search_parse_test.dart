import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';
import 'package:inf_flutter/core/widgets/smart_image.dart';
import 'package:inf_flutter/features/topic/ai_search_view.dart';

/// 综合 / 智搜 / 实时 / 热门 / 视频 / 图片, in weibo.com's order. 智搜 is the odd one out: its `type` is
/// not a m.weibo.cn container, so the page must never ask `hotTopicPage` for it.
void main() {
  // 智搜 wraps the model's reasoning in these two tags; they are spelt piecewise so the angle
  // brackets are not read as markup of this file.
  const open = '<' 'think' '>';
  const close = '<' '/' 'think' '>';

  group('HotTopicTab', () {
    test('is the six tabs s.weibo.com shows, in its order', () {
      expect(HotTopicTab.values.map((tab) => tab.label).toList(), ['综合', '智搜', '实时', '热门', '视频', '图片']);
      expect(HotTopicTab.values.map((tab) => tab.type).toList(), [1, 0, 61, 60, 64, 63]);
    });

    test('marks only 智搜 as the AI tab', () {
      expect(HotTopicTab.ai.isAi, isTrue);
      expect(HotTopicTab.values.where((tab) => tab.isAi).toList(), [HotTopicTab.ai]);
    });

    test('keeps the container types the search endpoint expects', () {
      expect(HotTopicTab.all.type, 1);
      expect(HotTopicTab.realtime.type, 61);
      expect(HotTopicTab.hot.type, 60);
      expect(HotTopicTab.video.type, 64);
      expect(HotTopicTab.picture.type, 63);
    });
  });

  group('parseAiSearchResult', () {
    // The parser looks for the space-delimited tag, and Weibo's `msg` carries the answer's leading
    // whitespace before it.
    test('moves a closed think block into thinking and out of the answer', () {
      final result = parseAiSearchResult({
        'status': 2,
        'msg': ' $open先看看大家在讨论什么。\n再组织一下。$close\n### 结论\n这家公司发布了新芯片。',
        'model': 'DeepSeek',
      }, '科技');

      expect(result.thinking, '先看看大家在讨论什么。\n再组织一下。');
      expect(result.blocks.map((block) => block.kind).toList(), [AiSearchBlockKind.heading, AiSearchBlockKind.paragraph]);
      expect(result.blocks.first.text, '结论');
      expect(result.blocks.first.level, 3);
      expect(result.blocks.last.text, '这家公司发布了新芯片。');
      expect(result.blocks.any((block) => block.text.contains('思考')), isFalse);
    });

    test('reads an unclosed think block as the thinking while the answer is still streaming', () {
      final result = parseAiSearchResult({
        'status': 1,
        'msg': ' $open正在检索最近一天的微博…',
      }, '科技');

      expect(result.isGenerating, isTrue);
      expect(result.thinking, '正在检索最近一天的微博…');
      expect(result.blocks, isEmpty);
    });

    test('parses headings, bullets and paragraphs, keeping the inline markup for rendering', () {
      final result = parseAiSearchResult({
        'status': 2,
        'msg': '## 讨论焦点\n- 价格 **下调** 了 15%\n正文提到 <hl>补贴</hl> 和 [官网](https://example.com/a)',
      }, '科技');

      expect(result.blocks.map((block) => block.kind).toList(), [
        AiSearchBlockKind.heading,
        AiSearchBlockKind.bullet,
        AiSearchBlockKind.paragraph,
      ]);
      expect(result.blocks[0].text, '讨论焦点');
      expect(result.blocks[0].level, 2);
      expect(result.blocks[1].text, '价格 **下调** 了 15%');
      expect(result.blocks[2].text, '正文提到 <hl>补贴</hl> 和 [官网](https://example.com/a)');
    });

    test('attaches a quoted block to the paragraph above it', () {
      final result = parseAiSearchResult({
        'status': 2,
        'msg': '多数人认为价格是主因。\n'
            '```wbCustomBlock {"type":"quoted","data":{"quote_list":['
            '{"name":"@数码闲聊站","scheme":"sinaweibo://detail?mblogid=K6L8micKJ","label":"原文"},'
            '{"title":"发布会实录","url":"https://weibo.com/1/K6L8micKJ"}]}}```',
      }, '科技');

      expect(result.blocks, hasLength(1));
      final block = result.blocks.single;
      expect(block.kind, AiSearchBlockKind.paragraph);
      expect(block.text, '多数人认为价格是主因。');
      expect(block.quotes, hasLength(2));
      expect(block.quotes.first.name, '@数码闲聊站');
      expect(block.quotes.first.scheme, 'sinaweibo://detail?mblogid=K6L8micKJ');
      expect(block.quotes.first.label, '原文');
      expect(block.quotes.last.name, '发布会实录');
      expect(block.quotes.last.scheme, 'https://weibo.com/1/K6L8micKJ');
    });

    test('parses a mediablock into its own media block', () {
      final result = parseAiSearchResult({
        'status': 2,
        'msg': '现场图：\n'
            '```wbCustomBlock {"type":"mediablock","data":['
            '{"img":"https://wx1.sinaimg.cn/large/a.jpg","scheme":"sinaweibo://detail?mblogid=K6L8micKJ","cur_mid":5367306396107439},'
            '{"pic":"https://wx2.sinaimg.cn/large/b.jpg"}]}```',
      }, '科技');

      final media = result.blocks.firstWhere((block) => block.kind == AiSearchBlockKind.media);
      expect(media.media, hasLength(2));
      expect(media.media.first.imageUrl, 'https://wx1.sinaimg.cn/large/a.jpg');
      expect(media.media.first.scheme, 'sinaweibo://detail?mblogid=K6L8micKJ');
      expect(media.media.first.statusId, '5367306396107439');
      expect(media.media.last.imageUrl, 'https://wx2.sinaimg.cn/large/b.jpg');
      expect(media.media.last.statusId, isNull);
    });

    test('reads status, model, link_list and the two states a reader waits on', () {
      final generating = parseAiSearchResult({
        'status': 1,
        'model': 'DeepSeek',
        'msg': '正在写…',
        'link_list': ['https://s.weibo.com/weibo?q=%E7%A7%91%E6%8A%80', '', 'https://weibo.com/aisearch'],
      }, '科技');
      expect(generating.query, '科技');
      expect(generating.status, 1);
      expect(generating.isGenerating, isTrue);
      expect(generating.isDone, isFalse);
      expect(generating.model, 'DeepSeek');
      // Empty entries carry nothing to open, so they are not links.
      expect(generating.linkList, [
        'https://s.weibo.com/weibo?q=%E7%A7%91%E6%8A%80',
        'https://weibo.com/aisearch',
      ]);

      final done = parseAiSearchResult({'status': 2, 'msg': '结论'}, '科技');
      expect(done.isGenerating, isFalse);
      expect(done.isDone, isTrue);
    });

    test('an answer that is not a map is an empty, non-generating result', () {
      final result = parseAiSearchResult('not json', '科技');
      expect(result.status, 0);
      expect(result.blocks, isEmpty);
      expect(result.isGenerating, isFalse);
    });
  });

  group('parseTopicSuggestions', () {
    test('deduplicates, strips hashes and drops empty entries', () {
      final names = parseTopicSuggestions([
        {'topic': '#科技#'},
        {'topic': ' 科技 '},
        {'topic': ''},
        {'name': '体育'},
        '  独立字符串  ',
        {'name': '  '},
      ]);

      expect(names, ['科技', '体育', '独立字符串']);
    });
  });

  group('parseAiSearchRuns', () {
    test('splits bold, highlighted, linked and plain text', () {
      final runs = parseAiSearchRuns('先说 **重点**，再看 <hl>这一句</hl> 和 [官网](https://example.com/a)。');

      expect(runs.map((run) => run.kind).toList(), [
        AiSearchRunKind.plain,
        AiSearchRunKind.bold,
        AiSearchRunKind.plain,
        AiSearchRunKind.highlight,
        AiSearchRunKind.plain,
        AiSearchRunKind.link,
        AiSearchRunKind.plain,
      ]);
      expect(runs.first.text, '先说 ');
      expect(runs[1].text, '重点');
      expect(runs[3].text, '这一句');
      expect(runs[5].text, '官网');
      expect(runs[5].url, 'https://example.com/a');
      expect(runs.last.text, '。');
    });

    test('leaves text without markup as one plain run', () {
      final runs = parseAiSearchRuns('没有标记的一段话。');
      expect(runs, hasLength(1));
      expect(runs.single.kind, AiSearchRunKind.plain);
      expect(runs.single.text, '没有标记的一段话。');
    });
  });

  group('AiSearchBody', () {
    AiSearchResult answer() => AiSearchResult(
          query: '科技',
          status: 2,
          model: 'DeepSeek',
          thinking: '先看看大家在讨论什么。',
          blocks: [
            const AiSearchBlock(kind: AiSearchBlockKind.heading, level: 2, text: '讨论焦点'),
            AiSearchBlock(
              kind: AiSearchBlockKind.paragraph,
              text: '价格 <hl>下调</hl> 了，**官方** 也确认了，详见 [官网](https://example.com/a)。',
              quotes: const [AiSearchQuote(name: '@数码闲聊站', scheme: 'sinaweibo://detail?mblogid=1')],
            ),
            const AiSearchBlock(kind: AiSearchBlockKind.bullet, text: '线下门店同步'),
            const AiSearchBlock(
              kind: AiSearchBlockKind.media,
              media: [
                AiSearchMedia(imageUrl: 'https://wx1.sinaimg.cn/large/a.jpg', statusId: '5367306396107439'),
                AiSearchMedia(imageUrl: 'https://wx2.sinaimg.cn/large/b.jpg'),
              ],
            ),
          ],
        );

    /// The span whose own text is [text], found among everything the answer drew.
    TextSpan spanOf(WidgetTester tester, String text) {
      Iterable<TextSpan> walk(TextSpan root) sync* {
        yield root;
        for (final child in root.children ?? const <InlineSpan>[]) {
          if (child is TextSpan) yield* walk(child);
        }
      }

      final matches = <TextSpan>[
        for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
          if (rich.text is TextSpan)
            for (final span in walk(rich.text as TextSpan))
              if (span.toPlainText() == text && (span.children == null || span.children!.isEmpty)) span,
      ];
      expect(matches, isNotEmpty, reason: 'nothing drew 「$text」');
      return matches.first;
    }

    /// The span that draws the whole line [text]: `Text.rich` keeps it one level below the outer
    /// span that carries the default style, and that line's own style is what the block chose.
    TextSpan paragraphOf(WidgetTester tester, String text) {
      final matches = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((rich) => rich.text)
          .whereType<TextSpan>()
          .expand((span) => span.children ?? const <InlineSpan>[])
          .whereType<TextSpan>()
          .where((span) => span.toPlainText() == text)
          .toList();
      expect(matches, isNotEmpty, reason: 'nothing reads 「$text」');
      return matches.first;
    }

    testWidgets('renders headings, highlights, bold runs, quote chips and pictures', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AiSearchBody(result: answer()))),
      ));

      // A heading is the line's own style, not a run inside it.
      expect(paragraphOf(tester, '讨论焦点').style?.fontWeight, FontWeight.w700);

      expect(spanOf(tester, '下调').style?.fontWeight, FontWeight.w600);
      expect(spanOf(tester, '下调').style?.backgroundColor, isNotNull);
      expect(spanOf(tester, '官方').style?.fontWeight, FontWeight.w700);
      expect(spanOf(tester, '官网').recognizer, isNotNull);
      // The markup itself never reaches the screen.
      expect(find.textContaining('**', findRichText: true), findsNothing);

      // The bullet keeps its dot apart from the words.
      expect(find.text('•'), findsOneWidget);
      expect(spanOf(tester, '线下门店同步').toPlainText(), '线下门店同步');

      // The citation is a chip the reader can open.
      expect(find.text('@数码闲聊站'), findsOneWidget);

      // A mediablock draws its own strip, one thumbnail per picture.
      expect(find.byType(SmartImage), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('thinking stays closed once there is an answer, and the reader can open it', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AiSearchThinking(
            text: '先看看大家在讨论什么。',
            expanded: false,
            onToggle: () => taps++,
          ),
        ),
      ));
      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('先看看大家在讨论什么。'), findsNothing);

      await tester.tap(find.text('思考过程'));
      await tester.pump();
      expect(taps, 1);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AiSearchThinking(
            text: '先看看大家在讨论什么。',
            expanded: true,
            generating: true,
            onToggle: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('先看看大家在讨论什么。'), findsOneWidget);
      expect(find.text('正在思考…'), findsOneWidget);
    });

    testWidgets('the view shows its header without asking Weibo until the tab is on screen', (tester) async {
      final controller = AiSearchController();
      // Nothing is mounted yet, so a reload has nothing to restart and is not a failure.
      expect(await controller.reload(), isFalse);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AiSearchView(query: '科技', active: false, controller: controller)),
      ));
      await tester.pump();

      expect(find.text('微博智搜'), findsOneWidget);
      expect(find.text('网页版'), findsOneWidget);
      expect(find.text('思考过程'), findsNothing);
      expect(find.textContaining('正在整理最新微博观点'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  });
}
