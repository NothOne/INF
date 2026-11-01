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

  group('pages only the Weibo app shows', () {
    test('a wbox mini program opens in the app’s browser', () {
      const award = 'https://m.weibo.cn/c/wbox?id=c0p9sg9tw9&page=pages/fieldscore/playerdetail&match_id=32910';
      final target = linkTargetOf(award) as ClientPageTarget;
      expect(target.url, award);
      expect(target.appUrl, 'sinaweibo://browser?url=${Uri.encodeComponent(award)}');
    });

    test('an article column, by either of its addresses', () {
      const wbox = 'https://m.weibo.cn/c/wbox?id=wqh75bb2ni&cid=4650846149408163';
      expect((linkTargetOf('http://weibo.com/a/hot/4650846149408163_1.html?type=new') as ClientPageTarget).url, wbox);
      expect((linkTargetOf('http://m.weibo.cn/p/2327184650846149408163?luicode=20000061') as ClientPageTarget).url, wbox);
      expect(linkKindOf('http://weibo.com/a/hot/4650846149408163_1.html?type=new'), LinkKind.article);
    });
  });

  test('linkInText finds the link in a paste, or says it is a search', () {
    expect(linkInText('https://m.weibo.cn/detail/5360381883319974'), 'https://m.weibo.cn/detail/5360381883319974');
    expect(linkInText('【国乒包揽女单四强】 https://weibo.com/2656274875/QaBcDeFgH 来自微博'),
        'https://weibo.com/2656274875/QaBcDeFgH');
    expect(linkInText('weibo.com/5051815423/Rk576FuEr'), 'https://weibo.com/5051815423/Rk576FuEr');
    expect(linkInText('孙颖莎'), isNull);
  });

  test('app and site names', () {
    expect(appNameOf('bilibili://video/BV1fNxp6tEaq'), '哔哩哔哩');
    expect(appNameOf('intent://video/1#Intent;scheme=bilibili;package=tv.danmaku.bili;end'), '哔哩哔哩');
    expect(appNameOf('foo://bar'), isNull);
    expect(siteNameOf('https://weibo.cn/sinaurl?u=https%3A%2F%2Fshare.b23.tv%2FBV1fNxp6tEaq'), '哔哩哔哩');
    expect(siteNameOf('https://m.bilibili.com/video/BV1'), '哔哩哔哩');
    expect(siteNameOf('https://example.com/'), isNull);
  });

  test('a birthday or medal post becomes a banner card', () {
    final mobile = toStatus({
      'id': '5355159049996178',
      'text': ' ',
      'user': {'id': '1', 'screen_name': '甲'},
      'page_info': {
        'type': 'bigPic',
        'page_pic': {'url': 'https://pc.us.sinaimg.cn/fg.png', 'scheme': 'https://new.vip.weibo.cn/birthday/index?uid=1'},
        'media_pic_url': 'https://pc.us.sinaimg.cn/bg.png',
        'title': '今天是我的生日10月18日，来祝福我吧~',
      },
    })!;
    expect(mobile.card!.banner, isTrue);
    expect(mobile.card!.imageUrl, 'https://pc.us.sinaimg.cn/fg.png');
    expect(mobile.card!.backgroundUrl, 'https://pc.us.sinaimg.cn/bg.png');
    expect(mobile.card!.url, 'https://new.vip.weibo.cn/birthday/index?uid=1');
    expect(mobile.card!.title, '今天是我的生日10月18日，来祝福我吧~');

    final medal = toStatus({
      'id': '5347862209889275',
      'text': '',
      'user': {'id': '1', 'screen_name': '甲'},
      'page_info': {'type': 'bigPic', 'page_pic': {'url': 'https://wx1.sinaimg.cn/large/fg.jpg'}},
    })!;
    expect(medal.card!.banner, isTrue);
    expect(medal.card!.url, isEmpty);

    final web = toStatus({
      'id': '5347862209889275',
      'text': 'http://t.cn/AXWGrmDM',
      'user': {'id': '1', 'screen_name': '甲'},
      'page_info': {
        'type': '23',
        'object_type': 'webpage',
        'page_title': '祝贺孙颖莎获得乒乓球女单亚军',
        'page_url': 'https://m.weibo.cn/c/wbox?id=c0p9sg9tw9',
        'card_info': {
          'card_type': '107',
          'pic_url': 'https://wx1.sinaimg.cn/large/fg.jpg',
          'title': '',
          'page_info': {
            'pic_info': {'pic_big': {'url': 'https://d.sinaimg.cn/bg.png'}},
          },
        },
      },
    })!;
    expect(web.card!.banner, isTrue);
    expect(web.card!.backgroundUrl, 'https://d.sinaimg.cn/bg.png');
    expect(web.card!.url, 'https://m.weibo.cn/c/wbox?id=c0p9sg9tw9');
  });
}
