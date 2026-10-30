import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/haptics.dart';
import '../../core/native.dart';
import '../../core/session.dart';
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

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  late final VideoPlayerController _controller = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
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

  @override
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Native.isPipAvailable().then((value) {
      if (mounted) setState(() => _pipAvailable = value);
    });
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.setLooping(false);
      _controller.play();
    }).catchError((Object error) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
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
    }
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
    await SharePlus.instance.share(ShareParams(text: widget.url));
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
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
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
        _controller.play();
      }
    });
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _controls = !_controls),
              onLongPressStart: (_) {
                if (Touches.multiTouch) return;
                Haptic.longPress.play();
                _controller.setPlaybackSpeed(2);
                setState(() {});
              },
              onLongPressEnd: (_) {
                _controller.setPlaybackSpeed(_speed);
                setState(() {});
              },
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
                      _controller.initialize().then((_) {
                        if (mounted) setState(() => _ready = true);
                        _controller.play();
                      }).catchError((Object error) {
                        if (mounted) setState(() => _error = true);
                      });
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (!_pip) ...[
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              left: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              right: 4,
              child: Row(
                children: [
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
          ],
          if (_ready && _controls && !_pip)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.only(
                  left: 8,
                  right: 12,
                  bottom: MediaQuery.paddingOf(context).bottom + 8,
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
                            onChanged: (value) {
                              _controller.seekTo(Duration(milliseconds: value.round()));
                            },
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _togglePlay,
                              icon: Icon(
                                value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
                                for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
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
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}