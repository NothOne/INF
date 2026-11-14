// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_ohos/src/messages.g.dart';
import 'package:video_player_ohos/video_player_ohos.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'ohos_video_player_test.mocks.dart';

class MockPlayerBundle {
  MockPlayerBundle(this.player, this.api);

  final OhosVideoPlayer player;
  final MockOhosVideoPlayerApi api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MockPlayerBundle setUpMockPlayer() {
    final MockOhosVideoPlayerApi pluginApi = MockOhosVideoPlayerApi();
    final OhosVideoPlayer player = OhosVideoPlayer(pluginApi: pluginApi);
    return MockPlayerBundle(player, pluginApi);
  }

  test('registration', () async {
    OhosVideoPlayer.registerWith();
    expect(VideoPlayerPlatform.instance, isA<OhosVideoPlayer>());
  });

  group('OhosVideoPlayer', () {
    test('init', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      await bundle.player.init();

      expect(bundle.api.initializeCallCount, 1);
    });

    test('dispose wraps TextureMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      await bundle.player.dispose(1);

      expect(bundle.api.disposeArg, isNotNull);
      expect(bundle.api.disposeArg!.textureId, 1);
    });

    test('create with asset builds CreateMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      bundle.api.createResult = TextureMessage(textureId: 100);

      final int? textureId = await bundle.player.create(
        DataSource(
          sourceType: DataSourceType.asset,
          asset: 'asset.mp4',
          package: 'video_player_ohos',
        ),
      );

      expect(textureId, 100);
      expect(bundle.api.createArg, isNotNull);
      expect(bundle.api.createArg!.asset, 'asset.mp4');
      expect(bundle.api.createArg!.packageName, 'video_player_ohos');
      expect(bundle.api.createArg!.uri, isNull);
    });

    test('create with network maps format and headers', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      bundle.api.createResult = TextureMessage(textureId: 101);

      await bundle.player.create(
        DataSource(
          sourceType: DataSourceType.network,
          uri: 'https://example.com/video.mpd',
          formatHint: VideoFormat.dash,
          httpHeaders: <String, String>{'Authorization': 'Bearer token'},
        ),
      );

      expect(bundle.api.createArg, isNotNull);
      expect(bundle.api.createArg!.uri, 'https://example.com/video.mpd');
      expect(bundle.api.createArg!.formatHint, 'dash');
      expect(
        bundle.api.createArg!.httpHeaders,
        <String?, String?>{'Authorization': 'Bearer token'},
      );
    });

    test('create with fd file keeps fd uri', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      bundle.api.createResult = TextureMessage(textureId: 102);

      await bundle.player.create(
        DataSource(
          sourceType: DataSourceType.file,
          uri: 'fd://42',
        ),
      );

      expect(bundle.api.createArg, isNotNull);
      expect(bundle.api.createArg!.uri, 'fd://42');
    });

    test('setLooping wraps LoopingMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      await bundle.player.setLooping(1, true);

      expect(bundle.api.setLoopingArg, isNotNull);
      expect(bundle.api.setLoopingArg!.textureId, 1);
      expect(bundle.api.setLoopingArg!.isLooping, isTrue);
    });

    test('play wraps TextureMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      await bundle.player.play(1);

      expect(bundle.api.playArg, isNotNull);
      expect(bundle.api.playArg!.textureId, 1);
    });

    test('pause wraps TextureMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      await bundle.player.pause(1);

      expect(bundle.api.pauseArg, isNotNull);
      expect(bundle.api.pauseArg!.textureId, 1);
    });

    test('setMixWithOthers wraps MixWithOthersMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      await bundle.player.setMixWithOthers(true);

      expect(bundle.api.setMixWithOthersArg, isNotNull);
      expect(bundle.api.setMixWithOthersArg!.mixWithOthers, isTrue);
    });

    test('setVolume wraps VolumeMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      const double volume = 0.7;
      await bundle.player.setVolume(1, volume);

      expect(bundle.api.setVolumeArg, isNotNull);
      expect(bundle.api.setVolumeArg!.textureId, 1);
      expect(bundle.api.setVolumeArg!.volume, volume);
    });

    test('setPlaybackSpeed wraps PlaybackSpeedMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      const double speed = 1.5;
      await bundle.player.setPlaybackSpeed(1, speed);

      expect(bundle.api.setPlaybackSpeedArg, isNotNull);
      expect(bundle.api.setPlaybackSpeedArg!.textureId, 1);
      expect(bundle.api.setPlaybackSpeedArg!.speed, speed);
    });

    test('seekTo wraps PositionMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      const int positionMilliseconds = 12345;
      await bundle.player.seekTo(
        1,
        const Duration(milliseconds: positionMilliseconds),
      );

      expect(bundle.api.seekToArg, isNotNull);
      expect(bundle.api.seekToArg!.textureId, 1);
      expect(bundle.api.seekToArg!.position, positionMilliseconds);
    });

    test('getPosition unwraps PositionMessage', () async {
      final MockPlayerBundle bundle = setUpMockPlayer();
      const int positionMilliseconds = 12345;
      bundle.api.positionResult = PositionMessage(
        textureId: 1,
        position: positionMilliseconds,
      );

      final Duration position = await bundle.player.getPosition(1);
      expect(position, const Duration(milliseconds: positionMilliseconds));

      expect(bundle.api.positionArg, isNotNull);
      expect(bundle.api.positionArg!.textureId, 1);
    });

    test('buildView returns Texture', () {
      final MockPlayerBundle bundle = setUpMockPlayer();
      final Widget widget = bundle.player.buildView(7);

      expect(widget, isA<Texture>());
      expect((widget as Texture).textureId, 7);
    });
  });
}
