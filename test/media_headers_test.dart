import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/image_url.dart';

void main() {
  // Measured against the CDN: the same `f.video.weibocdn.com` address with a valid-looking
  // signature answers 403 `byte-error-code 00068` (deny code 68) with no referrer, and reaches
  // the signature check (`deny by url auth`) once any Weibo referrer is sent. The players use
  // these headers, so a missing one is a black screen with no network error to show.
  group('weiboImageHeaders', () {
    test('the video CDN gets a Weibo referrer', () {
      final headers = weiboImageHeaders(
        'https://f.video.weibocdn.com/o0/abc.mp4?label=mp4_720p&Expires=1&ssig=x&KID=unistore,video',
      );
      expect(headers['Referer'], 'https://m.weibo.cn/');
    });

    test('the podcast CDN gets it too; audio plays through the same player', () {
      final headers = weiboImageHeaders('https://podcast.video.weibocdn.com/ol/abc.mp3?Expires=1&ssig=x');
      expect(headers['Referer'], 'https://m.weibo.cn/');
    });

    test('pictures on sinaimg get it, third-party covers get none', () {
      expect(weiboImageHeaders('https://wx1.sinaimg.cn/mw690/abc.jpg')['Referer'], 'https://m.weibo.cn/');
      expect(weiboImageHeaders('https://i0.hdslb.com/bfs/archive/abc.jpg').containsKey('Referer'), isFalse);
    });
  });
}
