import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/haptics.dart';
import '../../core/image_url.dart';
import '../../core/layout.dart';
import '../../core/native.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';
import '../../core/share.dart';
import '../../core/touches.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/smart_image.dart';
import 'cast_sheet.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.url, this.coverUrl});

  final String url;
  final String? coverUrl;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

/// What a drag on the picture is doing, decided by where it starts and which way it first moves.
enum _Drag { none, seek, brightness, volume, dismiss }

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  late final VideoPlayerController _controller = VideoPlayerController.networkUrl(
    Uri.parse(secureUrl(widget.url)),
    httpHeaders: {
      'Referer': 'https://m.weibo.cn/',
      'User-Agent': Session.instance.userAgent,
    },
  );
  bool _ready = false;
  bool _error = false;
  bool _controls = true;
  bool _pip = false;
  bool _pipAvailable = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  double _speed = 1;
  bool _boosting = false;

  /// Entered with the button; a phone turned sideways is shown the same way without it.
  bool _fullscreen = false;
  bool? _immersive;
  bool _orientationLocked = false;

  Timer? _hideTimer;
  Timer? _saveTimer;
  bool _wasPlaying = false;

  _Drag _drag = _Drag.none;
  double _dragDistance = 0;
  Duration _seekFrom = Duration.zero;
  Duration? _seekTarget;
  double _level = 0;
  double _levelFrom = 0;
  double? _brightness;
  double? _volume;
  bool _brightnessChanged = false;
  double _dismissDy = 0;

  Offset _doubleTapAt = Offset.zero;
  int _skipSeconds = 0;
  Timer? _skipTimer;

  Duration? _resumedFrom;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Native.isPipAvailable().then((value) {
      if (mounted) setState(() => _pipAvailable = value);
    });
    Native.brightness().then((value) => _brightness = value);
    Native.volume().then((value) => _volume = value);
    _controller.addListener(_onTick);
    _initialize(resume: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _savePosition();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _skipTimer?.cancel();
    _resumeTimer?.cancel();
    _controller.removeListener(_onTick);
    _controller.dispose();
    Native.keepScreenOn(false);
    if (_brightnessChanged) Native.setBrightness(-1);
    if (_immersive == true) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_orientationLocked) SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  void _initialize({bool resume = false}) {
    _controller.initialize().then((_) async {
      if (!mounted) return;
      final saved = resume ? Prefs.instance.videoPosition(widget.url) : null;
      final duration = _controller.value.duration;
      if (saved != null && saved > const Duration(seconds: 3) && saved < duration - const Duration(seconds: 3)) {
        await _controller.seekTo(saved);
        if (!mounted) return;
        _resumedFrom = saved;
        _resumeTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _resumedFrom = null);
        });
      }
      setState(() => _ready = true);
      _controller.setLooping(false);
      _controller.play();
      _scheduleHide();
    }).catchError((Object error) {
      if (mounted) setState(() => _error = true);
    });
  }

  void _onTick() {
    final playing = _controller.value.isPlaying;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    Native.keepScreenOn(playing);
    _saveTimer?.cancel();
    if (playing) {
      _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
      _scheduleHide();
    } else {
      _savePosition();
      _hideTimer?.cancel();
      if (mounted && !_controls) setState(() => _controls = true);
    }
  }

  /// Short clips and ones watched to the end are forgotten rather than resumed.
  void _savePosition() {
    if (!_ready) return;
    final value = _controller.value;
    final duration = value.duration;
    if (duration < const Duration(seconds: 15)) return;
    final position = value.position;
    final finished = value.isCompleted || duration - position < const Duration(seconds: 3);
    Prefs.instance.setVideoPosition(
      widget.url,
      finished || position < const Duration(seconds: 3) ? null : position,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pip) {
        setState(() {
          _pip = false;
          _controls = true;
        });
      }
    } else if (_pip) {
      _controller.play();
    } else if (state == AppLifecycleState.paused) {
      _savePosition();
    }
  }

  void _showControls() {
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_controller.value.isPlaying) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying && _drag == _Drag.none) setState(() => _controls = false);
    });
  }

  void _syncImmersive(bool immersive) {
    if (_immersive == immersive) return;
    final first = _immersive == null;
    _immersive = immersive;
    if (first && !immersive) return;
    SystemChrome.setEnabledSystemUIMode(immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  Future<void> _setFullscreen(bool on) async {
    final landscape = _ready && _controller.value.aspectRatio > 1.05;
    if (on) {
      if (landscape) {
        _orientationLocked = true;
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } else if (MediaQuery.sizeOf(context).shortestSide >= WindowClass.mediumWidth) {
      // A tablet is read either way up; leaving full screen hands rotation back to the user.
      if (_orientationLocked) await SystemChrome.setPreferredOrientations(const []);
      _orientationLocked = false;
    } else if (_orientationLocked || MediaQuery.orientationOf(context) == Orientation.landscape) {
      _orientationLocked = true;
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    }
    if (mounted) setState(() => _fullscreen = on);
    _scheduleHide();
  }

  Future<void> _enterPip() async {
    if (!_ready) return;
    final ok = await Native.enterPip(aspectRatio: _controller.value.aspectRatio.clamp(0.42, 2.39));
    if (!mounted) return;
    if (ok) {
      setState(() => _pip = true);
      _controller.play();
    } else {
      showMessage(context, '当前设备不支持小窗播放');
    }
  }

  Future<void> _share() async {
    await shareText(widget.url);
  }

  Future<void> _download() async {
    if (_downloading) return;
    if (widget.url.contains('.m3u8')) {
      showMessage(context, '流媒体地址暂不支持直接下载');
      return;
    }
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });
    try {
      final dir = await getTemporaryDirectory();
      final name = 'INF-video-${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = File('${dir.path}/$name');
      final headers = <String, String>{
        'Referer': 'https://m.weibo.cn/',
        'User-Agent': Session.instance.userAgent,
      };
      if (Session.instance.cookieHeader.isNotEmpty) {
        headers['Cookie'] = Session.instance.cookieHeader;
      }
      await Dio().download(
        widget.url,
        file.path,
        options: Options(headers: headers, followRedirects: true),
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );
      final saved = await Native.saveVideoToGallery(file.path, name);
      if (!mounted) return;
      if (saved != null) {
        Haptic.success.play();
        showMessage(context, '已保存到相册：$saved');
      } else {
        await shareFile(file.path, mime: 'video/mp4');
      }
    } catch (_) {
      Haptic.error.play();
      if (mounted) showMessage(context, '下载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        if (_controller.value.isCompleted) _controller.seekTo(Duration.zero);
        _controller.play();
      }
    });
  }

  void _restart() {
    _resumeTimer?.cancel();
    setState(() => _resumedFrom = null);
    _controller.seekTo(Duration.zero);
    _controller.play();
  }

  void _onDoubleTap(Offset position, double width) {
    if (!_ready) return;
    final third = position.dx / width;
    if (third > 1 / 3 && third < 2 / 3) {
      _togglePlay();
      return;
    }
    final step = third <= 1 / 3 ? -10 : 10;
    if (_skipSeconds.sign != step.sign) _skipSeconds = 0;
    _skipSeconds += step;
    final value = _controller.value;
    final target = value.position + Duration(seconds: step);
    _controller.seekTo(target < Duration.zero ? Duration.zero : (target > value.duration ? value.duration : target));
    Haptic.toggleOn.play();
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skipSeconds = 0);
    });
    setState(() {});
  }

  void _onHorizontalStart(DragStartDetails details) {
    if (!_ready || Touches.multiTouch) return;
    _drag = _Drag.seek;
    _dragDistance = 0;
    _seekFrom = _controller.value.position;
    _seekTarget = _seekFrom;
    _hideTimer?.cancel();
    setState(() {});
  }

  /// A full swipe across the screen covers the whole clip, up to two minutes of a long one.
  void _onHorizontalUpdate(DragUpdateDetails details, double width) {
    if (_drag != _Drag.seek) return;
    _dragDistance += details.delta.dx;
    final duration = _controller.value.duration;
    final span = duration < const Duration(minutes: 2) ? duration : const Duration(minutes: 2);
    var target = _seekFrom + span * (_dragDistance / width);
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    setState(() => _seekTarget = target);
  }

  void _onHorizontalEnd() {
    if (_drag != _Drag.seek) return;
    final target = _seekTarget;
    if (target != null && target != _seekFrom) {
      _controller.seekTo(target);
      if (!_controller.value.isPlaying && !_controller.value.isCompleted) _controller.play();
    }
    setState(() {
      _drag = _Drag.none;
      _seekTarget = null;
    });
    _scheduleHide();
  }

  void _onVerticalStart(DragStartDetails details, Size size) {
    if (Touches.multiTouch) return;
    final x = details.localPosition.dx / size.width;
    final immersive = _immersive ?? false;
    if (x < 1 / 3) {
      _drag = _Drag.brightness;
      _levelFrom = _brightness ?? 0.5;
    } else if (x > 2 / 3) {
      _drag = _Drag.volume;
      _levelFrom = _volume ?? 0.5;
      Native.volume().then((value) {
        if (value != null && _drag == _Drag.volume && _dragDistance == 0) _levelFrom = _level = value;
      });
    } else {
      _drag = immersive ? _Drag.none : _Drag.dismiss;
    }
    _level = _levelFrom;
    _dragDistance = 0;
    _hideTimer?.cancel();
    setState(() {});
  }

  void _onVerticalUpdate(DragUpdateDetails details, double height) {
    switch (_drag) {
      case _Drag.brightness || _Drag.volume:
        _dragDistance -= details.delta.dy;
        final level = (_levelFrom + _dragDistance / (height * 0.6)).clamp(0.0, 1.0);
        if (level == _level) return;
        setState(() => _level = level);
        if (_drag == _Drag.brightness) {
          _brightness = level;
          _brightnessChanged = true;
          Native.setBrightness(level);
        } else {
          _volume = level;
          Native.setVolume(level);
        }
      case _Drag.dismiss:
        setState(() => _dismissDy = (_dismissDy + details.delta.dy).clamp(0.0, double.infinity));
      default:
        break;
    }
  }

  void _onVerticalEnd(DragEndDetails details) {
    if (_drag == _Drag.dismiss && (_dismissDy > 140 || (details.primaryVelocity ?? 0) > 900)) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _drag = _Drag.none;
      _dismissDy = 0;
    });
    _scheduleHide();
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget? _hud() {
    if (_pip) return null;
    if (_drag == _Drag.seek && _seekTarget != null) {
      final delta = (_seekTarget! - _seekFrom).inSeconds;
      return _Hud(
        icon: delta < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
        label: '${_format(_seekTarget!)} / ${_format(_controller.value.duration)}',
        detail: '${delta < 0 ? '−' : '+'}${delta.abs()} 秒',
      );
    }
    if (_drag == _Drag.brightness) {
      return _Hud(icon: Icons.brightness_6_rounded, label: '亮度', level: _level);
    }
    if (_drag == _Drag.volume) {
      return _Hud(
        icon: _level == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        label: '音量',
        level: _level,
      );
    }
    if (_skipSeconds != 0) {
      return _Hud(
        icon: _skipSeconds < 0 ? Icons.replay_10_rounded : Icons.forward_10_rounded,
        label: '${_skipSeconds < 0 ? '−' : '+'}${_skipSeconds.abs()} 秒',
      );
    }
    if (_boosting) return const _Hud(icon: Icons.fast_forward_rounded, label: '2× 倍速播放中');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final immersive = !_pip && (_fullscreen || media.orientation == Orientation.landscape);
    _syncImmersive(immersive);
    final padding = media.padding;
    final barsVisible = !immersive || _controls;
    final dismiss = (_dismissDy / 600).clamp(0.0, 1.0);
    final hud = _hud();

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _setFullscreen(false);
      },
      child: Material(
        color: Colors.black.withValues(alpha: 1 - dismiss),
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_controls) {
                        _hideTimer?.cancel();
                        setState(() => _controls = false);
                      } else {
                        _showControls();
                      }
                    },
                    onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
                    onDoubleTap: () => _onDoubleTap(_doubleTapAt, size.width),
                    onLongPressStart: (_) {
                      if (Touches.multiTouch || !_ready) return;
                      Haptic.longPress.play();
                      _controller.setPlaybackSpeed(2);
                      setState(() => _boosting = true);
                    },
                    onLongPressEnd: (_) {
                      if (!_boosting) return;
                      _controller.setPlaybackSpeed(_speed);
                      setState(() => _boosting = false);
                    },
                    onHorizontalDragStart: _onHorizontalStart,
                    onHorizontalDragUpdate: (details) => _onHorizontalUpdate(details, size.width),
                    onHorizontalDragEnd: (_) => _onHorizontalEnd(),
                    onHorizontalDragCancel: _onHorizontalEnd,
                    onVerticalDragStart: (details) => _onVerticalStart(details, size),
                    onVerticalDragUpdate: (details) => _onVerticalUpdate(details, size.height),
                    onVerticalDragEnd: _onVerticalEnd,
                    child: Transform.translate(
                      offset: Offset(0, _dismissDy),
                      child: Transform.scale(
                        scale: 1 - dismiss * 0.4,
                        child: Center(
                          child: _ready
                              ? AspectRatio(
                                  aspectRatio: _controller.value.aspectRatio,
                                  child: VideoPlayer(_controller),
                                )
                              : (widget.coverUrl != null && widget.coverUrl!.isNotEmpty
                                  ? SmartImage(url: widget.coverUrl, fit: BoxFit.contain, placeholderColor: Colors.black)
                                  : const SizedBox.shrink()),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_ready && !_pip && _dismissDy == 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) => value.isBuffering && value.isPlaying && hud == null
                        ? const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.4))
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            if (hud != null) Positioned.fill(child: IgnorePointer(child: Center(child: hud))),
            if (!_ready && !_error && !_pip)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_error && !_pip)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('视频加载失败', style: TextStyle(color: Colors.white)),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _error = false;
                          _ready = false;
                        });
                        _initialize();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            if (!_pip && _dismissDy == 0)
              Positioned(
                top: padding.top + 4,
                left: padding.left + 4,
                right: padding.right + 4,
                child: _Fade(
                  visible: barsVisible,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => _fullscreen ? _setFullscreen(false) : Navigator.of(context).maybePop(),
                        icon: Icon(
                          _fullscreen ? Icons.arrow_back_rounded : Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => showCastSheet(context, widget.url),
                        icon: const Icon(Icons.cast_rounded, color: Colors.white),
                        tooltip: '投屏',
                      ),
                      IconButton(
                        onPressed: _downloading ? null : _download,
                        icon: _downloading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  value: _downloadProgress > 0 ? _downloadProgress : null,
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded, color: Colors.white),
                        tooltip: '下载',
                      ),
                      if (_pipAvailable)
                        IconButton(
                          onPressed: _enterPip,
                          icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white),
                          tooltip: '小窗播放',
                        ),
                      IconButton(
                        onPressed: _share,
                        icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
                        tooltip: '分享',
                      ),
                    ],
                  ),
                ),
              ),
            if (_resumedFrom != null && !_pip && _dismissDy == 0)
              Positioned(
                left: padding.left + 16,
                bottom: padding.bottom + (_controls ? 92 : 24),
                child: _ResumePill(position: _format(_resumedFrom!), onRestart: _restart),
              ),
            if (_ready && !_pip && _dismissDy == 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Fade(
                  visible: _controls,
                  child: Container(
                    padding: EdgeInsets.only(
                      left: padding.left + 8,
                      right: padding.right + 12,
                      bottom: padding.bottom + 8,
                      top: 20,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.62)],
                      ),
                    ),
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller,
                      builder: (context, value, child) {
                        final duration = value.duration.inMilliseconds.toDouble();
                        final position = value.position.inMilliseconds.toDouble().clamp(0.0, duration).toDouble();
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.5,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              ),
                              child: Slider(
                                value: duration <= 0 ? 0.0 : position,
                                max: duration <= 0 ? 1.0 : duration,
                                onChangeStart: (_) => _hideTimer?.cancel(),
                                onChanged: (value) {
                                  _controller.seekTo(Duration(milliseconds: value.round()));
                                },
                                onChangeEnd: (_) => _scheduleHide(),
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _togglePlay,
                                  icon: Icon(
                                    value.isCompleted
                                        ? Icons.replay_rounded
                                        : (value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                    color: Colors.white,
                                    size: 27,
                                  ),
                                ),
                                Text(
                                  '${_format(value.position)} / ${_format(value.duration)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                const Spacer(),
                                PopupMenuButton<double>(
                                  initialValue: _speed,
                                  onSelected: (speed) {
                                    setState(() => _speed = speed);
                                    _controller.setPlaybackSpeed(speed);
                                  },
                                  color: const Color(0xFF24242C),
                                  itemBuilder: (context) => [
                                    for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0])
                                      PopupMenuItem(
                                        value: speed,
                                        child: Text(
                                          '${speed}×',
                                          style: TextStyle(color: speed == _speed ? Colors.amber : Colors.white),
                                        ),
                                      ),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    child: Text('${_speed}×', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _setFullscreen(!immersive),
                                  icon: Icon(
                                    immersive ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                  tooltip: immersive ? '退出全屏' : '全屏',
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: child,
      ),
    );
  }
}

/// The feedback for a gesture on the picture: what it changes and to what.
class _Hud extends StatelessWidget {
  const _Hud({required this.icon, required this.label, this.detail, this.level});

  final IconData icon;
  final String label;
  final String? detail;
  final double? level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          if (level != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: level,
                  minHeight: 4,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResumePill extends StatelessWidget {
  const _ResumePill({required this.position, required this.onRestart});

  final String position;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('已从 $position 继续播放', style: const TextStyle(color: Colors.white, fontSize: 13)),
          TextButton(
            onPressed: onRestart,
            style: TextButton.styleFrom(foregroundColor: Colors.amber, visualDensity: VisualDensity.compact),
            child: const Text('从头播放'),
          ),
        ],
      ),
    );
  }
}
