import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/links.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';

void main() {
  group('linkTargetOf', () {
    test('posts and people open on their own pages', () {
      expect((linkTargetOf('https://m.weibo.cn/detail/5311000706286209') as StatusTarget).id, '5311000706286209');
      expect((linkTargetOf('https://weibo.com/1142208455/K6L8micKJ') as StatusTarget).id, 'K6L8micKJ');
      expect((linkTargetOf('https://m.weibo.cn/u/1669879400') as UserTarget).user, '1669879400');
      expect((linkTargetOf('https://m.weibo.cn/n/%E5%B0%8F%E6%98%8E') as UserTarget).user, '小明');
      expect((linkTargetOf('sinaweibo://userinfo?uid=1669879400') as UserTarget).user, '1669879400');
      expect((linkTargetOf('sinaweibo://detail?mblogid=K6L8micKJ') as StatusTarget).id, 'K6L8micKJ');
    });

    test('topics and super topics', () {
      final topic = linkTargetOf(
          'https://m.weibo.cn/search?containerid=231522type%3D1%26t%3D10%26q%3D%23%E6%A2%85%E8%A5%BF%23&extparam=%23%E6%A2%85%E8%A5%BF%23');
      expect((topic as TopicTarget).name, '梅西');
      final superTopic = linkTargetOf(
          'https://m.weibo.cn/p/index?extparam=%E5%BC%A0%E5%87%8C%E8%B5%AB&containerid=100808b98505d1f9f8c86d9a87748fb6ecc9bd&launchid=10000360-page_H5');
      expect((superTopic as SuperTopicTarget).containerId, '100808b98505d1f9f8c86d9a87748fb6ecc9bd');
      expect(superTopic.name, '张凌赫');
      final scheme = linkTargetOf('sinaweibo://pageinfo?containerid=100808f57b3faeb25f86b43a8cc58f02286f40&extparam=肖战');
      expect((scheme as SuperTopicTarget).name, '肖战');
      expect((linkTargetOf('sinaweibo://searchall?containerid=231522&q=%23%E6%97%A5%E5%B8%B8%23') as TopicTarget).name, '日常');
    });

    test('web pages, short links and what only the app can show', () {
      expect(linkTargetOf('http://t.cn/AXjmNkMl'), isA<ShortLinkTarget>());
      expect((linkTargetOf('https://vote.weibo.com/h5/index/index?vote_id=1') as WebTarget).url, contains('vote.weibo.com'));
      expect((linkTargetOf('http://weibo.com/p/100101B209435DD76CA0F4499E') as WebTarget).url, contains('/p/100101'));
      expect((linkTargetOf('https://weibo.cn/sinaurl?u=https%3A%2F%2Fexample.com%2Fa') as WebTarget).url, 'https://example.com/a');
      expect((linkTargetOf('sinaweibo://browser?url=https%3A%2F%2Fexample.com%2F') as WebTarget).url, 'https://example.com/');
      expect((linkTargetOf('sinaweibo://video/vvs?object_id=1034:5360367258501129') as WebTarget).url,
          'https://video.weibo.com/show?fid=1034%3A5360367258501129');
      expect(linkTargetOf('sinaweibo://groupinfo?group_id=5354323888573108'), isA<AppOnlyTarget>());
    });
  });

  test('linkKindOf reads the icon and the address', () {
    expect(linkKindOf('http://weibo.com/p/100101B2', iconUrl: 'https://h5.sinaimg.cn/x/timeline_card_small_location_default.png'),
        LinkKind.place);
    expect(linkKindOf('https://vote.weibo.com/h5/index/index?vote_id=1'), LinkKind.vote);
    expect(linkKindOf('https://lottery.media.weibo.com/lottery/h5/history/list?mid=1'), LinkKind.lottery);
    expect(linkKindOf('https://weibo.com/p/2304915354323888573108'), LinkKind.group);
    expect(linkKindOf('https://example.com/'), LinkKind.web);
  });

  test('weiboHtmlToRichText keeps a link’s own words and kind', () {
    const html = '做一个坚持自己的师傅吧 <a  href="http://weibo.com/p/100101B209435DD76CA0F4499E" data-hide="">'
        "<span class='url-icon'><img style='width: 1rem;height: 1rem' "
        "src='https://h5.sinaimg.cn/upload/2015/09/25/3/timeline_card_small_location_default.png'></span>"
        '<span class="surl-text">深圳·大运烧鸡</span></a> '
        '<a  href="https://m.weibo.cn/p/index?extparam=%E5%BC%A0%E5%87%8C%E8%B5%AB&containerid=100808b98505d1f9f8c86d9a87748fb6ecc9bd" data-hide="">'
        "<span class='url-icon'><img src='https://n.sinaimg.cn/photo/timeline_card_small_super_default.png'></span>"
        '<span class="surl-text">张凌赫</span></a> '
        "<a href='http://t.cn/AXjmNkMl' data-hide=''><span class='surl-text'>网页链接</span></a>";
    final rich = weiboHtmlToRichText(html);
    final place = rich.links['http://weibo.com/p/100101B209435DD76CA0F4499E']!;
    expect(place.kind, LinkKind.place);
    expect(place.label, '深圳·大运烧鸡');
    final superTopic = rich.links.values.firstWhere((link) => link.kind == LinkKind.superTopic);
    expect(superTopic.label, '张凌赫');
    expect(rich.text, contains(superTopic.url));
    expect(rich.links['http://t.cn/AXjmNkMl']!.label, '');
  });

  test('toStatus turns other page_info cards into a generic card', () {
    final status = toStatus({
      'id': '5360212196459194',
      'text': '抽奖',
      'user': {'id': '1', 'screen_name': '甲'},
      'page_info': {
        'type': 'webpage',
        'object_type': 2,
        'page_pic': {'url': 'https://wx1.sinaimg.cn/a.jpg'},
        'page_url': 'https://lottery.media.weibo.com/lottery/h5/history/list?mid=5360212196459194',
        'page_title': '抽奖详情',
        'content1': '好用免费的官方微博抽奖平台',
      },
    })!;
    expect(status.card!.title, '抽奖详情');
    expect(status.card!.kind, LinkKind.lottery);
    expect(status.card!.imageUrl, 'https://wx1.sinaimg.cn/a.jpg');

    final place = toStatus({
      'id': '1',
      'text': '',
      'user': {'id': '1', 'screen_name': '甲'},
      'page_info': {'type': 'place', 'page_title': '深圳', 'page_url': 'http://weibo.com/p/100101B2'},
    })!;
    expect(place.card, isNull);
    expect(place.place!.url, 'http://weibo.com/p/100101B2');
  });
}
