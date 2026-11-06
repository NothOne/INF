import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/widgets/rich_text.dart';

void main() {
  test('inlineImageUrls finds the picture links in a comment and nothing else', () {
    const text = '看图 https://wx1.sinaimg.cn/large/abc.jpg 还有 https://m.weibo.cn/sinaurl?u=https%3A%2F%2Fwx2.sinaimg.cn%2Forj360%2Fdef.png '
        '@小明 https://weibo.com/1234/abc';
    final urls = inlineImageUrls(text);
    expect(urls, hasLength(2));
    expect(urls.first, contains('abc.jpg'));
    expect(urls.last, contains('def.png'));
  });

  test('inlineImageUrls is empty for a reply that only talks', () {
    expect(inlineImageUrls('同意，转发微博'), isEmpty);
    expect(inlineImageUrl('https://video.weibo.com/show?fid=1034:1'), isNull);
  });
}
