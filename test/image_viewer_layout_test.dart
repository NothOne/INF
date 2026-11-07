import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/image_url.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/widgets/viewer_hero.dart';
import 'package:inf_flutter/features/media/image_viewer_page.dart';

void main() {
  group('viewerPictureBox', () {
    const phone = Size(434, 943);
    const tablet = Size(800, 1280);
    const landscape = Size(1280, 800);

    test('a phone keeps a long picture at full width and fits the rest to the width', () {
      expect(viewerPictureBox(phone, 0.2), (long: true, box: const Size(434, 2170)));
      expect(viewerPictureBox(phone, 0.75), (long: false, box: const Size(434, 434 / 0.75)));
    });

    test('a tablet in landscape scrolls a long picture in a column the width of the short side', () {
      expect(viewerPictureBox(landscape, 0.2), (long: true, box: const Size(800, 4000)));
      expect(viewerPictureBox(tablet, 0.2), (long: true, box: const Size(800, 4000)));
    });

    test('a tablet in landscape fits an ordinary portrait photo whole instead of scrolling it', () {
      expect(viewerPictureBox(landscape, 0.75), (long: false, box: const Size(600, 800)));
      expect(viewerPictureBox(landscape, 1.5), (long: false, box: const Size(1200, 800)));
    });

    test('an unknown shape fills the screen', () {
      expect(viewerPictureBox(tablet, 0), (long: false, box: tablet));
    });
  });

  group('viewerDecodeWidth', () {
    test('a picture within the texture limit decodes at its own size', () {
      expect(viewerDecodeWidth(width: 1216, height: 7000, original: false, maxTexture: 8192), isNull);
      expect(viewerDecodeWidth(width: 0, height: 0, original: false, maxTexture: 8192), isNull);
    });

    test('a picture taller than the limit is decoded narrower, keeping its shape', () {
      final width = viewerDecodeWidth(width: 1216, height: 14000, original: false, maxTexture: 8192)!;
      expect(width * 14000 / 1216, lessThanOrEqualTo(8192));
      expect(width * 14000 / 1216, greaterThan(7500));
      expect(viewerDecodeWidth(width: 1216, height: 14000, original: false, maxTexture: 16384), isNull);
    });

    test('an original is capped at 4096 wide', () {
      expect(viewerDecodeWidth(width: 6000, height: 4000, original: true, maxTexture: 16384), 4096);
      expect(viewerDecodeWidth(width: 6000, height: 4000, original: false, maxTexture: 16384), isNull);
    });
  });

  group('viewerHeroTags', () {
    final media = [
      const Media.image('a'),
      const Media.video('v'),
      const Media.image('b'),
    ];

    test('an indexed grid tag names every picture by its place among all the media', () {
      expect(viewerHeroTags('img-1-0', media, 0), ['img-1-0', 'img-1-2']);
    });

    test('a link tag stands for the one picture it was tapped on', () {
      expect(viewerHeroTags('link-img-comment-9-2', media, 2), [null, 'link-img-comment-9-2']);
      expect(viewerHeroTags(null, media, 0), [null, null]);
    });
  });

  test('signedUrlExpired reads the CDN Expires time', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    expect(signedUrlExpired('https://f.video.weibocdn.com/o0/x.mp4?Expires=1699999999&ssig=a', now), isTrue);
    expect(signedUrlExpired('https://f.video.weibocdn.com/o0/x.mp4?Expires=1700003600&ssig=a', now), isFalse);
    expect(signedUrlExpired('https://f.video.weibocdn.com/o0/x.mp4', now), isFalse);
  });
}
