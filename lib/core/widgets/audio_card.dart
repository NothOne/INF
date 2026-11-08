import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../chrome.dart';
import '../haptics.dart';
import '../image_url.dart';
import '../models.dart';
import '../motion.dart';
import 'smart_image.dart';

String _clock(Duration duration) {
  final seconds = duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$rest' : '$minutes:$rest';
}

/// A post's sound, played in place: a voice post's recording with what Weibo heard, or a podcast
/// card. Only one plays at a time.
class AudioCard extends StatefulWidget {
  const AudioCard({super.key, required this.audio, required this.statusId});

  final AudioClip audio;

  /// The post it belongs to, asked again for a signed address when [audio] has none.
  final String statusId;

  @override
  State<AudioCard> createState() => _AudioCardState();
}

class _AudioCardState extends State<AudioCard> {
  static _AudioCardState? _current;

  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;
  bool _transcriptOpen = false;

  /// weibo.com's copy of the sound: a signed address, and the transcript m.weibo.cn leaves out.
  AudioClip? _fetched;
  Future<AudioClip?>? _fetching;

  /// Where the bar was dragged to before anything was loaded; playback starts there.
  Duration? _pendingSeek;

  AudioClip get _audio {
    final fetched = _fetched;
    if (fetched == null) return widget.audio;
    final audio = widget.audio;
    return AudioClip(
      url: fetched.url,
      title: audio.title,
      author: audio.author ?? fetched.author,
      coverUrl: audio.coverUrl ?? fetched.coverUrl,
      durationMs: audio.durationMs > 0 ? audio.durationMs : fetched.durationMs,
      transcript: audio.transcript ?? fetched.transcript,
      voice: audio.voice,
    );
  }

  @override
  void initState() {
    super.initState();
    // A voice post from m.weibo.cn has neither a playable address nor its transcript.
    if (widget.audio.voice && widget.audio.url.isEmpty) _fetch();
  }

  Future<AudioClip?> _fetch() => _fetching ??= () async {
        try {
          final clip = await WeiboApi.instance.audioClip(widget.statusId);
          if (clip != null && clip.url.isNotEmpty && mounted) setState(() => _fetched = clip);
          return clip;
        } catch (_) {
          return null;
        } finally {
          _fetching = null;
        }
      }();

  @override
  void dispose() {
    if (_current == this) _current = null;
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _onTick() {
    final value = _controller?.value;
    if (value == null || !mounted) return;
    if (value.isCompleted && !value.isPlaying) {
      _controller!.seekTo(Duration.zero);
      _controller!.pause();
    }
    setState(() {});
  }

  /// The audio CDN refuses unsigned and expired addresses; weibo.com's copy of the post has a
  /// fresh one.
  Future<String> _address({bool fresh = false}) async {
    final audio = _audio;
    if (!fresh && audio.signed && !signedUrlExpired(audio.url, DateTime.now())) return audio.url;
    final url = (await _fetch())?.url;
    if (url == null || url.isEmpty) {
      if (audio.url.isEmpty) throw StateError('no address');
      return audio.url;
    }
    return url;
  }

  Future<VideoPlayerController> _open(String url) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(secureUrl(url)), httpHeaders: weiboImageHeaders(url));
    try {
      await controller.initialize();
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  Future<void> _toggle() async {
    Haptic.selection.play();
    final controller = _controller;
    if (controller != null) {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        _takeOver();
        await controller.play();
      }
      return;
    }
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      VideoPlayerController opened;
      try {
        opened = await _open(await _address());
      } catch (_) {
        opened = await _open(await _address(fresh: true));
      }
      if (!mounted) {
        opened.dispose();
        return;
      }
      opened.addListener(_onTick);
      _controller = opened;
      _takeOver();
      final seek = _pendingSeek;
      _pendingSeek = null;
      if (seek != null) await opened.seekTo(seek);
      await opened.play();
    } catch (_) {
      Haptic.error.play();
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _takeOver() {
    final previous = _current;
    if (previous != null && previous != this) previous._controller?.pause();
    _current = this;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final audio = _audio;
    final value = _controller?.value;
    final playing = value?.isPlaying ?? false;
    final total = (value?.duration ?? Duration.zero) > Duration.zero
        ? value!.duration
        : Duration(milliseconds: audio.durationMs);
    final position = value?.position ?? _pendingSeek ?? Duration.zero;
    final details = [
      if (audio.author != null && audio.author!.isNotEmpty) audio.author!,
      if (_failed) '播放失败，点按重试' else if (total > Duration.zero) '${_clock(position)} / ${_clock(total)}',
    ].join(' · ');
    final transcript = audio.transcript;
    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.65),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Cover(url: audio.coverUrl, voice: audio.voice, playing: playing, loading: _loading),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          audio.title.isEmpty ? '音频' : audio.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          details.isEmpty ? (audio.voice ? '语音' : '音频') : details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(color: _failed ? scheme.error : scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                    size: 34,
                    color: scheme.primary,
                  ),
                ],
              ),
              if (total > Duration.zero)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: SizedBox(
                    height: 22,
                    child: Slider(
                      value: (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0),
                      onChanged: (fraction) {
                        final to = Duration(milliseconds: (total.inMilliseconds * fraction).round());
                        final controller = _controller;
                        if (controller != null) {
                          controller.seekTo(to);
                        } else {
                          setState(() => _pendingSeek = to);
                        }
                      },
                      onChangeEnd: (_) {
                        if (_controller == null) _toggle();
                      },
                    ),
                  ),
                ),
              if (transcript != null && transcript.isNotEmpty) ...[
                const SizedBox(height: 7),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _transcriptOpen = !_transcriptOpen),
                  child: AnimatedSize(
                    duration: InfMotion.content,
                    curve: InfMotion.emphasized,
                    alignment: Alignment.topLeft,
                    child: Text(
                      transcript,
                      maxLines: _transcriptOpen ? null : 2,
                      overflow: _transcriptOpen ? null : TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.voice, required this.playing, required this.loading});

  final String? url;
  final bool voice;
  final bool playing;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null)
              SmartImage(url: url, fit: BoxFit.cover)
            else
              ColoredBox(
                color: scheme.primaryContainer,
                child: Icon(
                  voice ? Icons.mic_rounded : Icons.headphones_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            if (loading)
              const ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                ),
              )
            else if (playing)
              const ColoredBox(
                color: Colors.black26,
                child: Icon(Icons.graphic_eq_rounded, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}
