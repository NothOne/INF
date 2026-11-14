import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/image_url.dart';
import 'package:inf_flutter/core/links.dart';
import 'package:inf_flutter/core/media_save.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';

Map<String, dynamic> _post(String id, [Map<String, dynamic> extra = const {}]) => {
      'id': id,
      'text': '正文',
      'user': {'id': '1', 'screen_name': '甲'},
      ...extra,
    };

void main() {
  group('sound', () {
    test('a voice post plays its blog_audio, in milliseconds, over https', () {
      final status = toStatus(_post('1', {
        'blog_audio': {
          'media_url': 'http://audio.weibocdn.com/a.aac',
          'transcript': ' 你好 ',
          'duration': 12500,
        },
      }))!;
      expect(status.audio!.voice, isTrue);
      expect(status.audio!.url, 'https://audio.weibocdn.com/a.aac');
      expect(status.audio!.durationMs, 12500);
      expect(status.audio!.transcript, '你好');
      expect(status.audio!.signed, isFalse);
    });

    test('a podcast card becomes a sound, not a link card', () {
      final status = toStatus(_post('2', {
        'page_info': {
          'type': '44',
          'object_type': 'podcast_audio',
          'media_info': {'stream_url': 'https://podcast.video.weibocdn.com/a.mp3?ssig=x', 'duration': 61},
          'card_info': {'title': '第一期', 'author_name': '电台', 'cover': 'https://wx1.sinaimg.cn/c.jpg'},
        },
      }))!;
      expect(status.audio!.title, '第一期');
      expect(status.audio!.author, '电台');
      expect(status.audio!.durationMs, 61000);
      expect(status.audio!.signed, isTrue);
      expect(status.card, isNull);
      expect(audioClipOf(_post('2', {'page_info': {'type': '44', 'media_info': {'stream_url': 'https://a/b.mp3'}}}))!.url,
          'https://a/b.mp3');
    });

    test('m.weibo.cn’s “listen in the app” line becomes a voice clip to fetch', () {
      final status = toStatus(_post('7', {
        'text': '[语音10&quot;]请用最新版手机微博app收听原声<br />我今天睡到了11点',
      }))!;
      expect(status.text, '我今天睡到了11点');
      expect(status.audio!.voice, isTrue);
      expect(status.audio!.url, isEmpty);
      expect(status.audio!.signed, isFalse);
      expect(status.audio!.durationMs, 10000);
      expect(toStatus(_post('8', {'text': '[语音1\'05&quot;]请用最新版手机微博app收听原声'}))!.audio!.durationMs, 65000);
    });

    test('music sites read as sound links', () {
      expect(linkKindOf('https://music.163.com/song?id=1'), LinkKind.audio);
      expect(linkKindOf('https://www.xiaoyuzhoufm.com/episode/1'), LinkKind.audio);
      expect(siteNameOf('https://y.qq.com/n/ryqq/songDetail/1'), 'QQ 音乐');
    });
  });

  test('a card INF cannot show still leaves something to tap', () {
    final video = toStatus(_post('3', {
      'page_info': {'type': 'video', 'page_url': 'https://video.weibo.com/show?fid=1', 'page_pic': {'url': 'https://a/p.jpg'}},
    }))!;
    expect(video.card!.kind, LinkKind.video);
    expect(video.card!.url, 'https://video.weibo.com/show?fid=1');
    expect(video.card!.imageUrl, 'https://a/p.jpg');
    expect(toStatus(_post('4', {'page_info': {'type': 'unknown'}}))!.card, isNull);
  });

  test('a repost shows the original’s pictures', () {
    final repost = toStatus(_post('5', {
      'retweeted_status': _post('6', {
        'pics': [
          {'pid': 'a', 'url': 'https://wx1.sinaimg.cn/orj360/a.jpg', 'large': {'url': 'https://wx1.sinaimg.cn/large/a.jpg'}},
        ],
      }),
    }))!;
    expect(repost.media, isEmpty);
    expect(repost.images, hasLength(1));
  });

  group('search', () {
    test('channels come from the head cards, with 用户 put back', () {
      final channels = parseSearchChannels({
        'cardlistInfo': {
          'cardlist_head_cards': [
            {
              'channel_list': [
                {'name': '综合', 'containerid': '100103type=1&q=a'},
                {'name': '实时', 'containerid': '100103type%3D61%26q%3Da'},
                {'name': '视频', 'id': 64},
                {'name': '综合', 'containerid': '100103type=1&q=a'},
              ],
            },
          ],
        },
      })!;
      expect(channels.map((channel) => channel.type), [1, 61, 64, SearchChannel.users]);
      expect(channels.last.kind, SearchResultKind.users);
      expect(channels.first.kind, SearchResultKind.statuses);
      expect(const SearchChannel('话题', SearchChannel.topics).kind, SearchResultKind.entries);
      expect(parseSearchChannels({'cardlistInfo': {}}), isNull);
    });

    test('entries skip posts and people', () {
      final entries = parseSearchEntries({
        'cards': [
          {'card_type': 9, 'mblog': _post('1')},
          {
            'card_type': 11,
            'card_group': [
              {'card_type': 8, 'title_sub': '#话题#', 'desc1': '1万讨论', 'scheme': 'sinaweibo://searchall?q=%23话题%23'},
              {'card_type': 10, 'user': {'id': '1'}},
              {'card_type': 8, 'title_sub': '没有去处'},
            ],
          },
        ],
      });
      expect(entries, hasLength(1));
      expect(entries.single.title, '#话题#');
      expect(entries.single.subtitle, '1万讨论');
    });
  });

  group('profile', () {
    test('tabs follow weibo.com’s list in INF’s order', () {
      final tabs = parseProfileTabs({
        'tabList': [
          {'name': 'feed'},
          {'name': 'audio'},
          {'name': 'album'},
        ],
      });
      expect(tabs, [ProfileTab.posts, ProfileTab.featured, ProfileTab.photos, ProfileTab.audio]);
      expect(parseProfileTabs({}), ProfileTab.fallback);
    });

    test('extras: 转评赞 and the facts profile/detail gives', () {
      final extras = parseProfileExtras({
        'user': {
          'status_total_counter': {'total_cnt': '2,123', 'like_cnt': '1,488', 'comment_cnt': '614', 'repost_cnt': '21'},
        },
        'tabList': [
          {'name': 'feed'},
        ],
      }, {
        'ip_location': 'IP属地：广东',
        'birthday': '双鱼座',
        'created_at': '2014-07-28 12:29:31',
        'sunshine_credit': {'level': '阳光信用较好'},
        'label_desc': [
          {'name': '视频累计播放量1146'},
        ],
      });
      expect(extras.interactions, 2123);
      expect(extras.likes, 1488);
      expect(extras.comments, 614);
      expect(extras.reposts, 21);
      expect(extras.facts, ['IP属地：广东', '双鱼座', '2014-07-28 加入微博', '阳光信用较好', '视频累计播放量1146']);
      expect(extras.tabs, [ProfileTab.posts, ProfileTab.featured]);
      final bare = parseProfileExtras(null, null);
      expect(bare.likes, isNull);
      expect(bare.tabs, ProfileTab.fallback);
    });

    test('cursor lists end at 0 or -1', () {
      final page = parseCursorStatuses({'list': [_post('1')], 'next_cursor': 42});
      expect(page.items.single.id, '1');
      expect(page.nextCursor, '42');
      expect(parseCursorStatuses({'list': [_post('1')], 'next_cursor': -1}).nextCursor, isNull);
      expect(parseCursorStatuses({'list': [], 'next_cursor': 5}).nextCursor, isNull);
    });

    test('the picture wall knows each picture’s post', () {
      final page = parseImageWall({
        'list': [
          {'pid': 'abc', 'mid': 5000},
          {'mid': 1},
        ],
        'since_id': '9',
      });
      expect(page.items.single.media.url, 'https://wx1.sinaimg.cn/mw2000/abc.jpg');
      expect(page.items.single.media.previewUrl, 'https://wx1.sinaimg.cn/orj360/abc.jpg');
      expect(page.items.single.statusId, '5000');
      expect(page.nextCursor, '9');
      expect(parseImageWall({'list': [{'pid': 'a'}], 'since_id': '0'}).nextCursor, isNull);
    });

    test('the cover is full size, the stock one swapped for weibo.com’s', () {
      expect(profileCover('https://wx1.sinaimg.cn/crop.0.0.640.640.640/0033ImPzly1gs64jwa7uyj60v90v9n1r02.jpg;https://x/2.jpg'),
          'https://wx1.sinaimg.cn/mw2000/0033ImPzly1gs64jwa7uyj60v90v9n1r02.jpg');
      expect(profileCover('https://ww1.sinaimg.cn/crop.0.0.640.640.640/549d0121tw1egm1kjly3jj20hs0hsq4f.jpg'),
          'https://ww1.sinaimg.cn/mw2000/70ace9b7ly1ggzusnypoej20yi0yiaop.jpg');
      expect(profileCover(''), isNull);
      expect(profileCover(null), isNull);
    });

    test('badges: the V’s colour, the 会员 icon and gender', () {
      final extras = parseProfileExtras({
        'user': {'verified': true, 'verified_type': 3, 'verified_type_ext': 53, 'mbrank': 4, 'mbtype': 12, 'svip': 1, 'vvip': 1, 'gender': 'm'},
      }, null);
      expect(extras.verified, VerifiedBadge.red);
      expect(extras.vip?.url, 'https://h5.sinaimg.cn/upload/108/1866/2022/11/02/vvip_4.png');
      expect(extras.gender, 'm');
      expect(verifiedBadgeOf({'verified': true, 'verified_type': 0, 'verified_type_ext': 1}), VerifiedBadge.gold);
      expect(verifiedBadgeOf({'verified': true, 'verified_type': 0}), VerifiedBadge.yellow);
      expect(verifiedBadgeOf({'verified': true, 'verified_type': 2, 'verified_type_ext': -1}), VerifiedBadge.grey);
      expect(verifiedBadgeOf({'verified': true, 'verified_type': 2}), VerifiedBadge.blue);
      expect(verifiedBadgeOf({'verified': false, 'verified_type': 220}), isNull);
      expect(vipIconOf({'mbrank': 9, 'mbtype': 12, 'svip': 0})?.url, endsWith('/vip_7.png'));
      expect(vipIconOf({'mbrank': 9, 'mbtype': 12, 'svip': 1})?.url, endsWith('/svip_9.png'));
      expect(vipIconOf({'mbrank': 3, 'mbtype': 2}), isNull);
      expect(vipIconOf({'mbrank': 0, 'mbtype': 0}), isNull);
    });

    test('profile search lists posts', () {
      expect(parseStatusList({'list': [_post('7')], 'total': 1}).single.id, '7');
      expect(parseStatusList({'list': [], 'total': 0}), isEmpty);
    });
  });

  test('a default avatar gets the address its picture really has', () {
    expect(defaultAvatarFixed('https://ss1.sinaimg.cn/orj480/default_avatar_male_180&690'),
        'https://tvax1.sinaimg.cn/default/images/default_avatar_male_180.gif');
    expect(defaultAvatarFixed('https://tvax1.sinaimg.cn/default/images/default_avatar_female_50.gif'),
        'https://tvax1.sinaimg.cn/default/images/default_avatar_female_50.gif');
    expect(defaultAvatarFixed('https://tvax4.sinaimg.cn/crop.0.0.1018.1018.180/abc.jpg'),
        'https://tvax4.sinaimg.cn/crop.0.0.1018.1018.180/abc.jpg');
    expect(toUser({'id': 5087078089, 'screen_name': '平滑的脑皮质', 'profile_image_url': 'https://ss1.sinaimg.cn/orj480/default_avatar_female_180&690'})?.avatarUrl,
        'https://tvax1.sinaimg.cn/default/images/default_avatar_female_180.gif');
  });

  test('an avatar opens at its largest size', () {
    expect(avatarLarge('https://tvax4.sinaimg.cn/crop.0.0.1018.1018.180/abc.jpg?KID=imgbed,tva&Expires=1&ssig=x'),
        'https://tvax4.sinaimg.cn/crop.0.0.1018.1018.1024/abc.jpg?KID=imgbed,tva&Expires=1&ssig=x');
    expect(avatarLarge('https://wx1.sinaimg.cn/orj480/abc.jpg'), 'https://wx1.sinaimg.cn/large/abc.jpg');
    expect(avatarLarge('https://tvax1.sinaimg.cn/default/images/default_avatar_male_180.gif'),
        'https://tvax1.sinaimg.cn/default/images/default_avatar_male_180.gif');
  });

  test('saving them all says which went in as live photos', () {
    const still = Media.image('https://wx1.sinaimg.cn/large/a.jpg');
    const live = Media.image('https://wx1.sinaimg.cn/large/b.jpg', liveUrl: 'https://video.weibo.com/b.mov');
    expect(saveAllLabel([still, still]), '保存全部图片（2 张）');
    expect(saveAllLabel([still, live, live]), '保存全部（3 张，含 2 张实况）');
    expect(saveAllLabel([live]), '保存实况照片');
    expect(saveAllMessage((saved: 3, live: 2, stills: 0), 3), '已保存全部 3 张，其中 2 张实况');
    expect(saveAllMessage((saved: 2, live: 0, stills: 1), 3), '已保存 2 / 3 张，1 张实况只存了静态图');
  });

  test('saved pictures keep their real format', () {
    expect(imageTypeOfBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]).extension, '.png');
    expect(imageTypeOfBytes('GIF89a'.codeUnits).extension, '.gif');
    expect(imageTypeOfBytes([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]).extension, '.webp');
    expect(imageTypeOfBytes([0xFF, 0xD8, 0xFF]).extension, '.jpg');
  });
}
