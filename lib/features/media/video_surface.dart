import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../core/native.dart';
import '../../core/prefs.dart';

bool get _canFallBack => defaultTargetPlatform == TargetPlatform.android && !Native.isOhos;

/// The surface a new player should draw into on this device.
VideoViewType preferredVideoView() =>
    _canFallBack && Prefs.instance.videoSurfaceView ? VideoViewType.platformView : VideoViewType.textureView;

/// Initializes [first]; if it cannot start on the texture path, builds the player again on a
/// SurfaceView with [rebuild] and returns that one instead. Huawei's OMX.hisi decoders fail to
/// allocate buffers on the texture path's ImageReader (`setBufferCount ... Invalid argument`) while
/// playing fine on a SurfaceView. [first] stays owned by the caller either way.
Future<VideoPlayerController> startVideo(
  VideoPlayerController first,
  VideoPlayerController Function(VideoViewType viewType) rebuild,
) async {
  try {
    await first.initialize();
    return first;
  } catch (error) {
    debugPrint('INF video: ${first.viewType.name} failed to start: $error');
    if (!_canFallBack || first.viewType == VideoViewType.platformView) rethrow;
  }
  final second = rebuild(VideoViewType.platformView);
  try {
    await second.initialize();
  } catch (error) {
    debugPrint('INF video: platformView failed to start: $error');
    await second.dispose();
    rethrow;
  }
  Prefs.instance.setVideoSurfaceView();
  return second;
}
