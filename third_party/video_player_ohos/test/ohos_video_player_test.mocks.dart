import 'package:video_player_ohos/src/messages.g.dart';

class MockOhosVideoPlayerApi implements OhosVideoPlayerApi {
  int initializeCallCount = 0;
  CreateMessage? createArg;
  TextureMessage createResult = TextureMessage(textureId: 0);
  TextureMessage? disposeArg;
  LoopingMessage? setLoopingArg;
  VolumeMessage? setVolumeArg;
  PlaybackSpeedMessage? setPlaybackSpeedArg;
  TextureMessage? playArg;
  PositionMessage positionResult = PositionMessage(textureId: 0, position: 0);
  TextureMessage? positionArg;
  PositionMessage? seekToArg;
  TextureMessage? pauseArg;
  MixWithOthersMessage? setMixWithOthersArg;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  @override
  Future<TextureMessage> create(CreateMessage msg) async {
    createArg = msg;
    return createResult;
  }

  @override
  Future<void> dispose(TextureMessage argMsg) async {
    disposeArg = argMsg;
  }

  @override
  Future<void> setLooping(LoopingMessage argMsg) async {
    setLoopingArg = argMsg;
  }

  @override
  Future<void> setVolume(VolumeMessage argMsg) async {
    setVolumeArg = argMsg;
  }

  @override
  Future<void> setPlaybackSpeed(PlaybackSpeedMessage argMsg) async {
    setPlaybackSpeedArg = argMsg;
  }

  @override
  Future<void> play(TextureMessage argMsg) async {
    playArg = argMsg;
  }

  @override
  Future<PositionMessage> position(TextureMessage argMsg) async {
    positionArg = argMsg;
    return positionResult;
  }

  @override
  Future<void> seekTo(PositionMessage argMsg) async {
    seekToArg = argMsg;
  }

  @override
  Future<void> pause(TextureMessage argMsg) async {
    pauseArg = argMsg;
  }

  @override
  Future<void> setMixWithOthers(MixWithOthersMessage argMsg) async {
    setMixWithOthersArg = argMsg;
  }
}
