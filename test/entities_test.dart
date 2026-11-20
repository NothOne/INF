import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/entities.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/status_store.dart';

/// The posts the app keeps, and what a merge is allowed to do to them.
///
/// The bug this layer exists for is "the same thing in two places, disagreeing": the feed holds the
/// copy its list parsed, the detail page holds another, and only *changes this device made* used to
/// travel between them. A long post's whole text, or a count a fresh answer corrected, stayed on the
/// screen that fetched it. These tests pin the merge that fixes it, and the two rules that keep it
/// honest: an answer that carries less must not erase what is stored, and nothing is kept forever.
Status post({
  String id = 'p1',
  String text = '正文',
  int comments = 0,
  int likes = 0,
  int reposts = 0,
  bool liked = false,
  bool long = false,
  List<Media> media = const [],
  String? region,
  Map<String, WeiboLink> links = const {},
  Status? repostOf,
}) =>
    Status(
      id: id,
      author: const User(id: 'u1', screenName: '某人'),
      text: text,
      createdAt: DateTime(2026),
      commentsCount: comments,
      likesCount: likes,
      repostsCount: reposts,
      liked: liked,
      isLongText: long,
      media: media,
      region: region,
      links: links,
      repostOf: repostOf,
    );

void main() {
  // Two singletons, no reset: Entities is cleared per test, but StatusStore's records of what this
  // device changed are not, so every test uses its own post id.
  setUp(Entities.instance.clear);
  var minted = 0;
  String nextId() => 'post-${minted++}';

  group('a post goes in once and comes back out', () {
    test('the copy stored is the copy read', () {
      final stored = Entities.instance.put(post(id: 'a', text: '你好', likes: 3));
      expect(Entities.instance.status('a'), same(stored));
      expect(Entities.instance.status('a')!.likesCount, 3);
    });

    test('a post never seen reads as missing', () {
      expect(Entities.instance.status('nothing-here'), isNull);
    });

    test('the same answer again is the same object, so a caller can skip a rebuild', () {
      final first = Entities.instance.put(post(id: 'a', likes: 5));
      final again = Entities.instance.put(post(id: 'a', likes: 5));
      expect(identical(again, first), isTrue);
    });
  });

  group('put is a merge, not a replace', () {
    test('a poorer answer cannot take the whole text away', () {
      // The feed parses a long post truncated; the detail page fetches the rest. A later list page
      // carrying the truncated copy again must not undo that.
      Entities.instance.put(post(id: 'a', text: '很长的正文，后面还有', long: true));
      Entities.instance.put(post(id: 'a', text: '很长的正文，后面还有，这是全文', long: false));

      final after = Entities.instance.put(post(id: 'a', text: '很长的正文，后面还有', long: true));
      expect(after.text, contains('这是全文'), reason: 'the shorter copy must not replace the longer one');
      expect(after.isLongText, isTrue, reason: 'the flag that offers 全文 is kept while either copy has it');
    });

    test('an answer that carries no pictures does not erase the ones stored', () {
      const picture = Media.image('https://example.com/a.jpg');
      Entities.instance.put(post(id: 'a', media: const [picture]));

      final after = Entities.instance.put(post(id: 'a'));
      expect(after.media, hasLength(1));
    });

    test('an answer that carries pictures replaces the old ones', () {
      Entities.instance.put(post(id: 'a', media: const [Media.image('https://example.com/old.jpg')]));
      final after = Entities.instance.put(
        post(id: 'a', media: const [Media.image('https://example.com/new.jpg')]),
      );
      expect(after.media.single.url, 'https://example.com/new.jpg');
    });

    test('counts always come from the newest answer', () {
      // Unlike text, a count is not "poorer" for being smaller: three comments is the truth even
      // though one comment was also the truth a minute ago.
      Entities.instance.put(post(id: 'a', comments: 9, likes: 4, reposts: 2));
      final after = Entities.instance.put(post(id: 'a', comments: 3, likes: 0, reposts: 1));

      expect(after.commentsCount, 3);
      expect(after.likesCount, 0);
      expect(after.repostsCount, 1);
    });

    test('a field the answer leaves out keeps what was stored', () {
      Entities.instance.put(post(
        id: 'a',
        region: '发布于 北京',
        links: const {'https://weibo.com/1': WeiboLink(url: 'https://weibo.com/1', label: '微博')},
      ));

      final after = Entities.instance.put(post(id: 'a'));
      expect(after.region, '发布于 北京');
      expect(after.links, hasLength(1));
    });

    test('a repost of a post is not lost when a copy without it arrives', () {
      final original = post(id: 'original', text: '原博');
      Entities.instance.put(post(id: 'a', repostOf: original));

      final after = Entities.instance.put(post(id: 'a', text: '转发时说的话'));
      expect(after.repostOf, isNotNull);
      expect(after.repostOf!.text, '原博');
      expect(after.text, '转发时说的话');
    });

    test('merging links preserves links discovered by the fuller copy', () {
      Entities.instance.put(post(
        id: 'a',
        links: const {
          'https://weibo.com/1': WeiboLink(url: 'https://weibo.com/1', label: '全文链接'),
        },
      ));
      final after = Entities.instance.put(post(
        id: 'a',
        links: const {
          'https://weibo.com/2': WeiboLink(url: 'https://weibo.com/2', label: '卡片链接'),
        },
      ));
      expect(after.links.keys, containsAll(['https://weibo.com/1', 'https://weibo.com/2']));
    });

    test('putIfAbsent does not overwrite fresher counts with an older copy', () {
      Entities.instance.put(post(id: 'a', likes: 15, comments: 8));
      final kept = Entities.instance.putIfAbsent(post(id: 'a', likes: 10, comments: 3));
      expect(kept.likesCount, 15);
      expect(kept.commentsCount, 8);
    });

    test('a poorer feed copy does not erase mixed media or multi-picture link bundles', () {
      const url = 'https://wx2.sinaimg.cn/large/p1.jpg';
      Entities.instance.put(post(
        id: 'rich',
        media: [
          Media.image('https://wx3.sinaimg.cn/large/p1.jpg'),
          Media.video('https://f.video.weibocdn.com/v1.mp4'),
        ],
        links: {
          url: WeiboLink(
            url: url,
            label: '查看2张图片',
            images: [
              Media.image('https://wx2.sinaimg.cn/large/p1.jpg'),
              Media.image('https://wx1.sinaimg.cn/large/p2.jpg'),
            ],
          ),
        },
      ));

      final after = Entities.instance.put(post(
        id: 'rich',
        media: [Media.image('https://wx3.sinaimg.cn/large/p1.jpg')],
        links: const {url: WeiboLink(url: url, label: '查看图片')},
      ));

      expect(after.media, hasLength(2));
      expect(after.media[1].kind, MediaKind.video);
      expect(after.links[url]?.images, hasLength(2));
      expect(after.links[url]?.label, '查看2张图片');
    });
  });

  group('the map cannot grow without limit', () {
    test('the oldest posts fall out once the cap is reached', () {
      // A session scrolls through far more posts than are worth holding; the cap is what keeps
      // this from becoming a leak that only shows up as memory pressure days later.
      for (var index = 0; index < Entities.instance.kept + 10; index++) {
        Entities.instance.put(post(id: 'post-$index'));
      }
      expect(Entities.instance.length, Entities.instance.kept);
      expect(Entities.instance.status('post-0'), isNull, reason: 'the oldest went first');
      expect(Entities.instance.status('post-${Entities.instance.kept + 9}'), isNotNull);
    });

    test('putting a post again moves it to the front, so reading a post keeps it', () {
      for (var index = 0; index < Entities.instance.kept; index++) {
        Entities.instance.put(post(id: 'post-$index'));
      }
      // Read the oldest one again, then push a new one in: the re-read one survives.
      Entities.instance.put(post(id: 'post-0'));
      Entities.instance.put(post(id: 'newest'));

      expect(Entities.instance.status('post-0'), isNotNull);
      expect(Entities.instance.status('post-1'), isNull, reason: 'the second oldest is out now');
    });
  });

  group('the store reads through Entities', () {
    test('a row draws the copy the app knows, not the one its list parsed', () {
      // This is the whole point: the feed's row holds a truncated copy, the detail page filed the
      // whole text, and the row still draws the whole text without the list re-parsing anything.
      final id = nextId();
      final fromFeed = post(id: id, text: '截断的正文…', long: true);
      Entities.instance.put(post(id: id, text: '截断的正文…后面是全文', long: false));

      final drawn = StatusStore.instance.apply(fromFeed);
      expect(drawn.text, '截断的正文…后面是全文');
    });

    test('this device\'s comment count still wins over what was stored', () {
      final id = nextId();
      final status = post(id: id, comments: 10);
      Entities.instance.put(status);
      StatusStore.instance.seed(status);

      StatusStore.instance.addComment(status);
      final drawn = StatusStore.instance.apply(post(id: id, comments: 10));
      expect(drawn.commentsCount, 11, reason: 'the store overlays its change on the stored copy');
    });

    test('a post the app has never seen is returned as it was', () {
      final status = post(id: nextId(), likes: 7);
      expect(identical(StatusStore.instance.apply(status), status), isTrue);
    });

    test('remember files a post and seed keeps its like baseline', () {
      final id = nextId();
      final status = post(id: id, liked: true, likes: 4);
      StatusStore.instance.seed(status);

      expect(Entities.instance.status(id), isNotNull);
      expect(StatusStore.instance.apply(status).liked, isTrue);
      expect(StatusStore.instance.apply(status).likesCount, 4);
    });
  });
}
