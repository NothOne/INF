import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/parse.dart';

/// The comment side of [parse.dart], which had no tests of its own.
///
/// Every case here is a shape that was seen on the wire and mishandled: a reply that did not say
/// who it answered, a cursor whose type was left out of the answer, a picture whose address looked
/// like the default avatar's.
void main() {
  group('toComment', () {
    Map<String, dynamic> replyJson({String? totalNumber = '0'}) => {
          'id': '5001',
          'text': '同意',
          'created_at': 'Thu Nov 19 10:00:00 +0800 2026',
          'user': {'id': '9', 'screen_name': '甲'},
          'total_number': totalNumber,
        };

    test('reads the comment that a reply answers from reply_comment', () {
      final comment = toComment({
        'id': '5002',
        'text': '不是这样',
        'created_at': 'Thu Nov 19 10:00:00 +0800 2026',
        'user': {'id': '8', 'screen_name': '乙'},
        'reply_comment': {
          'id': '5001',
          'text': '同意',
          'user': {'id': '9', 'screen_name': '甲'},
        },
      }, '77');

      expect(comment?.replyTo?.screenName, '甲');
      expect(comment?.text, '不是这样');
    });

    test('falls back to the name in reply_text when reply_comment is missing', () {
      // Older answers carry only the name, inside the text: 「回复@甲：同意」.
      final comment = toComment({
        'id': '5003',
        'text': '同意',
        'reply_text': '回复@甲:同意',
        'created_at': 'Thu Nov 19 10:00:00 +0800 2026',
        'user': {'id': '8', 'screen_name': '乙'},
      }, '77');

      expect(comment?.replyTo?.screenName, '甲');
    });

    test('a top-level comment answers nobody', () {
      final comment = toComment({
        'id': '5004',
        'text': '前排',
        'created_at': 'Thu Nov 19 10:00:00 +0800 2026',
        'user': {'id': '8', 'screen_name': '乙'},
      }, '77');

      expect(comment?.replyTo, isNull);
    });

    test('the reply count is the total, not how many came inline', () {
      final comment = toComment({
        'id': '5005',
        'text': '楼',
        'created_at': 'Thu Nov 19 10:00:00 +0800 2026',
        'user': {'id': '8', 'screen_name': '乙'},
        'total_number': '37',
        'comments': [replyJson()],
      }, '77');

      expect(comment?.replies, hasLength(1));
      expect(comment?.repliesCount, 37);
    });

    test('keeps a picture whose address merely ends in &690', () {
      // `&690` used to be matched anywhere in the address, and it is also how m.weibo.cn sizes a
      // thumbnail — so a 690-wide picture was dropped as if it were the default avatar.
      final comment = toComment({
        'id': '5006',
        'text': '图',
        'created_at': 'Thu Nov 19 10:00:00 +0800 2026',
        'user': {'id': '8', 'screen_name': '乙'},
        'pics': [
          {'url': 'https://wx1.sinaimg.cn/orj360/abc.jpg', 'large': {'url': 'https://wx1.sinaimg.cn/large/abc.jpg'}},
        ],
      }, '77');

      expect(comment?.images.map((image) => image.url), ['https://wx1.sinaimg.cn/large/abc.jpg']);
    });

    test('drops the default avatar address that m.weibo.cn sends for pictures', () {
      final comment = toComment({
        'id': '5007',
        'text': '图',
        'created_at': 'Thu Nov 19 10:00:00 +0800 2026',
        'user': {'id': '8', 'screen_name': '乙'},
        'pics': [
          {'url': 'https://ss1.sinaimg.cn/default_avatar_male_180&690'},
        ],
      }, '77');

      expect(comment?.images, isEmpty);
    });

    test('preserves emoji-only comments and line breaks from HTML img alt tags', () {
      final comment = toComment({
        'id': '5367435542138338',
        'text':
            '<span class="url-icon"><img alt="[鲜花]" src="https://face.t.sinajs.cn/t4/appstyle/expression/ext/normal/c8/201810_xianhua_mobile.png" style="width:1em; height:1em;" /></span>'
            '<span class="url-icon"><img alt="[鲜花]" src="https://face.t.sinajs.cn/t4/appstyle/expression/ext/normal/c8/201810_xianhua_mobile.png" style="width:1em; height:1em;" /></span>'
            '<br />好棒<span class="url-icon"><img alt="[打call]" src="https://face.t.sinajs.cn/t4/appstyle/expression/ext/normal/39/moren_dacall02_org.png" /></span>',
        'created_at': 'Fri Nov 20 21:03:38 +0800 2026',
        'user': {'id': 5487695796, 'screen_name': '大冲Ge'},
        'comments': false,
      }, '5367435286808850');

      expect(comment?.text, '[鲜花][鲜花]\n好棒[打call]');
    });
  });

  group('parseCommentPage', () {
    test('keeps the cursor type the answer left out', () {
      // 按时间 asks for max_id_type=1 and the first answer often does not echo it back. Defaulting
      // to 0 turned every later page into the hot order, which repeats and reorders what was shown.
      final page = parseCommentPage(
        {
          'data': [
            {'id': '1', 'text': 'a', 'created_at': 'Thu Nov 19 10:00:00 +0800 2026', 'user': {'id': '9', 'screen_name': '甲'}},
          ],
          'max_id': '1234',
        },
        '77',
        maxIdType: '1',
      );

      expect(page.nextCursor, '1234:1');
    });

    test('the answer\'s own type wins over the one asked for', () {
      final page = parseCommentPage(
        {
          'data': [
            {'id': '1', 'text': 'a', 'created_at': 'Thu Nov 19 10:00:00 +0800 2026', 'user': {'id': '9', 'screen_name': '甲'}},
          ],
          'max_id': '1234',
          'max_id_type': '2',
        },
        '77',
        maxIdType: '1',
      );

      expect(page.nextCursor, '1234:2');
    });

    test('no max_id means no more pages', () {
      final page = parseCommentPage(
        {
          'data': [
            {'id': '1', 'text': 'a', 'created_at': 'Thu Nov 19 10:00:00 +0800 2026', 'user': {'id': '9', 'screen_name': '甲'}},
          ],
          'max_id': '0',
        },
        '77',
      );

      expect(page.nextCursor, isNull);
    });

    test('reads the list hotFlowChild wraps one level deeper', () {
      final page = parseCommentPage(
        {
          'data': {
            'data': [
              {'id': '2', 'text': 'b', 'created_at': 'Thu Nov 19 10:00:00 +0800 2026', 'user': {'id': '9', 'screen_name': '甲'}},
            ],
            'max_id': '55',
            'max_id_type': '0',
          },
        },
        '77',
      );

      expect(page.items.single.id, '2');
      expect(page.nextCursor, '55:0');
    });
  });

  group('parseRootComment', () {
    test('reads the comment a thread hangs off', () {
      final root = parseRootComment({
        'rootComment': [
          {'id': '77', 'text': '楼主', 'user': {'id': '9', 'screen_name': '甲'}},
        ],
      }, '1');

      expect(root?.id, '77');
      expect(root?.author.screenName, '甲');
    });

    test('null when the answer does not carry one', () {
      expect(parseRootComment({'data': {'data': []}}, '1'), isNull);
    });
  });
}
