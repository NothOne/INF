import 'package:flutter_test/flutter_test.dart';

import 'package:inf_flutter/core/parse.dart';

/// Reading the picture out of a bracketed emoji, which is the only way Weibo ever ships one: the
/// post's HTML carries an `<img alt="[doge]" src="…">`, and the app turns the code into that image.
///
/// Nothing here was covered, which is how the picker came to sit empty with every test green.
void main() {
  group('collectEmoji', () {
    test('reads the picture out of the usual inline emoji', () {
      // The shape m.weibo.cn returns, inside a post's `text`.
      final found = collectEmoji({
        'text': '<span class="url-icon"><img alt="[doge]" '
            'src="https://face.t.sinajs.cn/t4/appstyle/expression/ext/normal/1e/doge_thumb.png" '
            'style="width:1em; height:1em;"></span>',
      });
      expect(found, {
        '[doge]': 'https://face.t.sinajs.cn/t4/appstyle/expression/ext/normal/1e/doge_thumb.png',
      });
    });

    test('takes a protocol-relative source', () {
      final found = collectEmoji({'v': '<img alt="[微笑]" src="//face.t.sinajs.cn/x.png">'});
      expect(found['[微笑]'], 'https://face.t.sinajs.cn/x.png');
    });

    test('upgrades a plain http source', () {
      final found = collectEmoji({'v': '<img alt="[ok]" src="http://face.t.sinajs.cn/x.png">'});
      expect(found['[ok]'], 'https://face.t.sinajs.cn/x.png');
    });

    test('walks into nested lists and maps, which is where the post text really is', () {
      final found = collectEmoji({
        'data': {
          'cards': [
            {
              'mblog': {
                'text': '<img alt="[哈哈]" src="https://a/x.png">',
              },
            },
          ],
        },
      });
      expect(found['[哈哈]'], 'https://a/x.png');
    });

    test('ignores images that are not emoji', () {
      // A picture in a post has no bracketed alt: it must not land in the emoji table.
      final found = collectEmoji({
        'text': '<img src="https://wx1.sinaimg.cn/large/abc.jpg">',
        'pic': '<img alt="一张图片" src="https://wx1.sinaimg.cn/large/abc.jpg">',
      });
      expect(found, isEmpty);
    });

    test('ignores a source it cannot make https', () {
      final found = collectEmoji({'v': '<img alt="[x]" src="ftp://a/x.png">'});
      expect(found, isEmpty);
    });
  });
}
