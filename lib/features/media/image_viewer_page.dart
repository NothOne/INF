import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/motion.dart';
import '../../core/haptics.dart';
import '../../core/image_url.dart';
import '../../core/models.dart';
import '../../core/native.dart';
import '../../core/share.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/image_grid.dart';
import '../../core/widgets/smart_image.dart';

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.heroTag,
  });

  final List<Media> images;
  final int initialIndex;
  final String? heroTag;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _saving = false;
  bool _sharing = false;
  bool _pagingLocked = false;

  /// Share and download hide on a short tap and come back on the next one.
  bool _tools = true;

  /// Pages switched to the original upload, by index.
  final Map<int, String> _originals = {};
  int? _loadingOriginal;
  double? _originalProgress;

  /// 1 at rest, falling toward 0 as the picture is dragged away; only the backdrop and chrome
  /// listen, so a drag does not rebuild the pager.
  final ValueNotifier<double> _backdrop = ValueNotifier<double>(1);

  /// Bumped by the 实况 chip; the visible live page plays its clip again.
  final ValueNotifier<int> _liveReplay = ValueNotifier<int>(0);
  final ValueNotifier<bool> _livePlaying = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // After the opening flight has its first frames, not during them.
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _precacheAround(_index);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _backdrop.dispose();
    _liveReplay.dispose();
    _livePlaying.dispose();
    super.dispose();
  }

  /// Decodes the pictures either side of [index], so a swipe lands on a sharp picture.
  void _precacheAround(int index) {
    for (final neighbour in [index + 1, index - 1]) {
      if (neighbour < 0 || neighbour >= widget.images.length) continue;
      final image = widget.images[neighbour];
      if (image.url.isEmpty) continue;
      precacheImage(weiboImageProvider(image.url), context, onError: (_, _) {});
    }
  }

  /// What page [index] is showing: the original once it has been asked for, else the API's size.
  String _urlAt(int index) => _originals[index] ?? widget.images[index].url;

  /// sinaimg's `large` is the upload itself; the API hands out at most `mw2000`.
  String? _originalOf(int index) {
    if (_originals.containsKey(index)) return null;
    final current = sanitizeImageUrl(widget.images[index].url);
    final original = sinaimgSized(current, 'large');
    return original == current ? null : original;
  }

  /// Downloads into the disk cache with visible progress, and only then swaps the page over, so
  /// the sharp picture replaces the current one in a single fade.
  Future<void> _loadOriginal(int index) async {
    final url = _originalOf(index);
    if (url == null || _loadingOriginal != null) return;
    setState(() {
      _loadingOriginal = index;
      _originalProgress = null;
    });
    try {
      final stream = DefaultCacheManager().getFileStream(url, headers: weiboImageHeaders(), withProgress: true);
      await for (final response in stream) {
        if (!mounted) return;
        if (response is FileInfo) break;
        if (response is DownloadProgress) setState(() => _originalProgress = response.progress);
      }
      if (mounted) setState(() => _originals[index] = url);
    } catch (_) {
      Haptic.error.play();
      if (mounted) showMessage(context, '原图加载失败');
    } finally {
      if (mounted) setState(() => _loadingOriginal = null);
    }
  }

  /// The picture as a file other apps can take. sinaimg refuses requests without a Weibo Referer,
  /// so a bare link is useless outside the app; this hands over the bytes, usually straight from
  /// the cache the viewer has just drawn from.
  Future<({String path, String name, String mime})> _exportFile(int index) async {
    final cached = await DefaultCacheManager().getSingleFile(
      sanitizeImageUrl(_urlAt(index)),
      headers: weiboImageHeaders(),
    );
    final type = await _typeOf(cached);
    final name = 'INF-' + DateTime.now().millisecondsSinceEpoch.toString() + type.extension;
    final path = (await getTemporaryDirectory()).path + '/' + name;
    await cached.copy(path);
    return (path: path, name: name, mime: type.mime);
  }

  /// From the file's first bytes: the URL says `.jpg` for GIFs too.
  Future<({String extension, String mime})> _typeOf(File file) async {
    final handle = await file.open();
    final head = await handle.read(12);
    await handle.close();
    bool starts(List<int> magic, [int at = 0]) {
      if (head.length < at + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (head[at + i] != magic[i]) return false;
      }
      return true;
    }

    if (starts([0x89, 0x50, 0x4E, 0x47])) return (extension: '.png', mime: 'image/png');
    if (starts([0x47, 0x49, 0x46, 0x38])) return (extension: '.gif', mime: 'image/gif');
    if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
      return (extension: '.webp', mime: 'image/webp');
    }
    return (extension: '.jpg', mime: 'image/jpeg');
  }

  Future<void> _shareImage(int index) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final file = await _exportFile(index);
      await shareFile(file.path, mime: file.mime, name: file.name);
    } catch (_) {
      Haptic.error.play();
      if (mounted) showMessage(context, '图片分享失败');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// The live photo's motion clip, from the same disk cache its playback reads.
  Future<File> _liveClip(int index) => DefaultCacheManager().getSingleFile(
        sanitizeImageUrl(widget.images[index].liveUrl!),
        headers: weiboImageHeaders(),
      );

  /// A live photo saves as a Motion Photo unless [as] asks for one half of it.
  Future<void> _saveImage(int index, {_SaveAs? as}) async {
    if (_saving) return;
    final kind = as ?? (widget.images[index].isLive ? _SaveAs.motionPhoto : _SaveAs.picture);
    setState(() => _saving = true);
    try {
      final String? saved;
      switch (kind) {
        case _SaveAs.picture:
          final file = await _exportFile(index);
          saved = await Native.saveImageToGallery(file.path, file.name, mime: file.mime);
          if (saved == null) {
            await shareFile(file.path, mime: file.mime);
            return;
          }
        case _SaveAs.motionPhoto:
          final file = await _exportFile(index);
          final clip = await _liveClip(index);
          final name = file.name.replaceFirst(RegExp(r'\.\w+$'), '.jpg');
          saved = await Native.saveMotionPhoto(file.path, clip.path, name);
        case _SaveAs.clip:
          final clip = await _liveClip(index);
          final name = 'INF-' + DateTime.now().millisecondsSinceEpoch.toString() + '.mp4';
          saved = await Native.saveVideoToGallery(clip.path, name, remux: true);
      }
      if (!mounted) return;
      if (saved == null) throw StateError('not saved');
      Haptic.success.play();
      showMessage(context, kind.done + saved);
    } catch (_) {
      Haptic.error.play();
      if (mounted) showMessage(context, kind.failed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showActions(int index) async {
    Haptic.longPress.play();
    final scheme = Theme.of(context).colorScheme;
    final original = _originalOf(index);
    final loading = _loadingOriginal == index;
    final live = widget.images[index].isLive;
    await showActionSheet<void>(
      context: context,
      backgroundColor: scheme.surface,
      builder: (sheetContext) {
        Widget save(IconData icon, String title, _SaveAs as, {String? subtitle}) => ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: subtitle == null ? null : Text(subtitle),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _saveImage(index, as: as);
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live) ...[
                save(Icons.motion_photos_on_rounded, '保存实况照片', _SaveAs.motionPhoto, subtitle: '图片与动态视频合为一张'),
                save(Icons.image_outlined, '仅保存图片', _SaveAs.picture),
                save(Icons.movie_outlined, '仅保存视频', _SaveAs.clip),
              ] else
                save(Icons.download_rounded, '保存图片', _SaveAs.picture),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('分享图片'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _shareImage(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.hd_outlined),
                title: const Text('查看原图'),
                subtitle: original != null || loading ? null : const Text('当前已是原图'),
                enabled: original != null && !loading,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _loadOriginal(index);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  String? _heroTagFor(int index) {
    final tag = widget.heroTag;
    if (tag == null) return null;
    if (tag.startsWith('link-img-')) {
      return index == widget.initialIndex ? tag : null;
    }
    final match = RegExp(r'^(.*)-(\d+)$').firstMatch(tag);
    if (match == null) return index == widget.initialIndex ? tag : null;
    return match.group(1)! + '-' + index.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    final routeAnimation = ModalRoute.of(context)?.animation ?? const AlwaysStoppedAnimation<double>(1);
    final fade = Listenable.merge([routeAnimation, _backdrop]);
    double opacity() => (routeAnimation.value * _backdrop.value).clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: fade,
              builder: (context, _) => ColoredBox(color: Colors.black.withValues(alpha: opacity())),
            ),
          ),
          PageView.builder(
            controller: _pages,
            physics: _pagingLocked ? const NeverScrollableScrollPhysics() : null,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() => _index = index);
              _livePlaying.value = false;
              _precacheAround(index);
            },
            itemBuilder: (context, index) {
              final image = widget.images[index];
              return _ZoomableImage(
                image: image,
                url: _urlAt(index),
                active: index == _index,
                liveReplay: _liveReplay,
                onLivePlaying: (playing) => _livePlaying.value = playing,
                // Only the visible page may fly home; a neighbour the pager keeps alive would
                // otherwise launch from off screen.
                heroTag: index == _index ? _heroTagFor(index) : null,
                onLongPress: () => _showActions(index),
                onToggleTools: () {
                  setState(() => _tools = !_tools);
                  Haptic.selection.play();
                },
                onDismiss: () => Navigator.of(context).maybePop(),
                onBackdrop: (value) => _backdrop.value = value,
                onLockPaging: (locked) {
                  if (locked != _pagingLocked) setState(() => _pagingLocked = locked);
                },
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              ignoring: !_tools,
              child: AnimatedOpacity(
                opacity: _tools ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AnimatedBuilder(
                  animation: fade,
                  builder: (context, child) => Opacity(opacity: opacity(), child: child),
                  child: Container(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + 4,
                      left: 4,
                      right: 4,
                      bottom: 18,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                        if (widget.images[_index].isLive)
                          _LiveChip(
                            playing: _livePlaying,
                            onTap: () {
                              Haptic.selection.play();
                              _liveReplay.value++;
                            },
                          ),
                        const Spacer(),
                        if (widget.images.length > 1)
                          Text(
                            '${_index + 1} / ${widget.images.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        const Spacer(),
                        IconButton(
                          onPressed: _sharing ? null : () => _shareImage(_index),
                          icon: _sharing
                              ? const _BusyIcon()
                              : const Icon(Icons.ios_share_rounded, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: _saving ? null : () => _saveImage(_index),
                          icon: _saving
                              ? const _BusyIcon()
                              : const Icon(Icons.download_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 28,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: fade,
                builder: (context, child) => Opacity(opacity: opacity(), child: child),
                child: _OriginalProgress(
                  visible: _loadingOriginal == _index,
                  progress: _originalProgress,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One page of the viewer. The Hero wraps exactly the picture's on-screen box and every drag or
/// zoom transform sits above it, so closing always flies from where the picture is right now.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.image,
    required this.url,
    required this.active,
    required this.liveReplay,
    required this.onLivePlaying,
    required this.heroTag,
    required this.onLongPress,
    required this.onToggleTools,
    required this.onDismiss,
    required this.onBackdrop,
    required this.onLockPaging,
  });

  final Media image;

  /// What to draw: [image]'s own URL, or its original once that has been loaded.
  final String url;

  /// The page on screen; only it plays a live clip.
  final bool active;
  final ValueListenable<int> liveReplay;
  final ValueChanged<bool> onLivePlaying;
  final String? heroTag;
  final VoidCallback onLongPress;
  final VoidCallback onToggleTools;
  final VoidCallback onDismiss;
  final ValueChanged<double> onBackdrop;
  final ValueChanged<bool> onLockPaging;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> with TickerProviderStateMixin {
  static const double _maxScale = 4;

  final TransformationController _transform = TransformationController();
  final ScrollController _scroll = ScrollController();
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<Matrix4>? _matrix;
  Animation<double>? _dragBack;
  final HapticThreshold _dismiss = HapticThreshold(release: 0.85);

  late double _ratio = widget.image.width > 0 && widget.image.height > 0
      ? widget.image.width / widget.image.height
      : 0;
  ImageStream? _ratioStream;
  ImageStreamListener? _ratioListener;

  Offset _doubleTapPosition = Offset.zero;
  bool _zoomed = false;
  double _drag = 0;
  bool _dragging = false;
  bool _dismissed = false;

  final Set<int> _pointers = {};

  /// A second finger joined the current touch. That touch then belongs to pinch zoom: no long
  /// press, no drag-to-close and no paging until every finger has lifted.
  bool _multiTouch = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_syncZoom);
    _zoom.addListener(() {
      final matrix = _matrix;
      if (matrix != null) _transform.value = matrix.value;
    });
    _settle.addListener(() {
      final back = _dragBack;
      if (back != null) _setDrag(back.value);
    });
    if (_ratio == 0) _resolveRatio();
  }

  @override
  void dispose() {
    _stopResolvingRatio();
    _zoom.dispose();
    _settle.dispose();
    _transform.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Without the size from the API the Hero box cannot match the picture, so read it from the
  /// decoded image (usually already cached by the thumbnail grid).
  void _resolveRatio() {
    if (widget.image.url.isEmpty) return;
    final stream = weiboImageProvider(widget.image.url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        final width = info.image.width;
        final height = info.image.height;
        if (mounted && width > 0 && height > 0) setState(() => _ratio = width / height);
        _stopResolvingRatio();
      },
      onError: (_, _) => _stopResolvingRatio(),
    );
    _ratioStream = stream;
    _ratioListener = listener;
    stream.addListener(listener);
  }

  void _stopResolvingRatio() {
    final listener = _ratioListener;
    if (listener != null) _ratioStream?.removeListener(listener);
    _ratioStream = null;
    _ratioListener = null;
  }

  void _syncZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    _reportLock();
  }

  void _reportLock() => widget.onLockPaging(_zoomed || _multiTouch);

  void _onPointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) _multiTouch = false;
    _pointers.add(event.pointer);
    if (_zoom.isAnimating) _zoom.stop();
    if (_pointers.length > 1 && !_multiTouch) {
      setState(() => _multiTouch = true);
      _reportLock();
    }
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty && _multiTouch) {
      setState(() => _multiTouch = false);
      _reportLock();
    }
  }

  void _onLongPress() {
    if (_multiTouch || _pointers.length > 1) return;
    widget.onLongPress();
  }

  void _animateTo(Matrix4 target) {
    _matrix = Matrix4Tween(begin: _transform.value.clone(), end: target).animate(
      CurvedAnimation(parent: _zoom, curve: Curves.easeOutCubic),
    );
    _zoom.forward(from: 0);
  }

  void _toggleZoom(Size viewport, Rect content, double scale) {
    if (_zoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    final focal = _doubleTapPosition == Offset.zero ? viewport.center(Offset.zero) : _doubleTapPosition;
    _animateTo(_zoomAt(focal, scale, content, viewport));
  }

  /// Zooms about [focal] but keeps [content] (the picture inside the viewport) covering the screen
  /// on any axis where it is large enough, and centred on any axis where it is not.
  Matrix4 _zoomAt(Offset focal, double scale, Rect content, Size viewport) {
    double axis(double focal, double start, double extent, double view) {
      final scaled = extent * scale;
      if (scaled <= view) return view / 2 - (start + extent / 2) * scale;
      return (focal - focal * scale).clamp(view - (start + extent) * scale, -start * scale);
    }

    final dx = axis(focal.dx, content.left, content.width, viewport.width);
    final dy = axis(focal.dy, content.top, content.height, viewport.height);
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(dx, dy, 0);
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final scale = _transform.value.getMaxScaleOnAxis();
    if (scale != 1 && scale < 1.01) _animateTo(Matrix4.identity());
  }

  void _setDrag(double value) {
    setState(() => _drag = value);
    final height = MediaQuery.sizeOf(context).height;
    widget.onBackdrop((1 - value.abs() / (height * 0.35)).clamp(0.0, 1.0));
  }

  void _onDragStart(DragStartDetails details) {
    _settle.stop();
    // A new touch catches a long picture still coasting from the last fling.
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
    _dragging = true;
    _dismiss.reset();
  }

  /// A long picture scrolls under the finger until it hits an edge; pulling on past the edge
  /// becomes the same drag-to-close as a short picture, and pushing back gives the scroll back.
  void _onDragUpdate(DragUpdateDetails details, double height, {required bool long}) {
    var delta = details.delta.dy;
    if (long && _scroll.hasClients) {
      final position = _scroll.position;
      final atTop = position.pixels <= position.minScrollExtent;
      final atBottom = position.pixels >= position.maxScrollExtent;
      if (_drag == 0 && !(delta > 0 && atTop) && !(delta < 0 && atBottom)) {
        position.jumpTo((position.pixels - delta).clamp(position.minScrollExtent, position.maxScrollExtent));
        return;
      }
      final next = _drag + delta;
      if (_drag != 0 && next != 0 && next.sign != _drag.sign) {
        _setDrag(0);
        position.jumpTo((position.pixels - next).clamp(position.minScrollExtent, position.maxScrollExtent));
        _dismiss.update(0);
        return;
      }
      delta = next - _drag;
    }
    _setDrag(_drag + delta);
    _dismiss.update(_drag.abs() / (height * 0.12));
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    if (_drag == 0) {
      final position = _scroll.hasClients ? _scroll.position : null;
      if (position is ScrollPositionWithSingleContext) position.goBallistic(-velocity);
      return;
    }
    if (!_dismissed && (_dismiss.armed || velocity.abs() > 700)) {
      // Leave the picture where the finger left it: the Hero flight starts from this exact box.
      _dismissed = true;
      widget.onDismiss();
    } else {
      _animateDragBack();
    }
  }

  void _animateDragBack() {
    _dragging = false;
    if (_drag == 0) return;
    _dragBack = Tween<double>(begin: _drag, end: 0).animate(
      CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic),
    );
    _settle.forward(from: 0);
  }

  /// The sharpest smaller rendition already decoded (the grid's, usually), so the picture is
  /// never blank while the full size loads; falls back to the plain thumbnail.
  late final String _preview = () {
    final image = widget.image;
    for (final candidate in [thumbnailUrl(image, single: true), image.previewUrl]) {
      if (candidate != image.url && isImageInMemory(candidate)) return candidate;
    }
    return image.previewUrl;
  }();

  bool get _upgraded => widget.url != widget.image.url;

  /// While switching to the original, the picture already on screen stays underneath.
  String get _underlay => _upgraded ? widget.image.url : _preview;

  /// Originals can be tens of megapixels; past this width the extra decode buys no visible detail
  /// even at full zoom, only memory.
  static const int _maxDecodeWidth = 4096;

  int? get _cacheWidth => _upgraded && widget.image.width > _maxDecodeWidth ? _maxDecodeWidth : null;

  Widget _picture({double? width, double? height, required BoxFit fit}) {
    Widget picture = SmartImage(
      url: widget.url,
      placeholderUrl: _underlay,
      cacheWidth: _cacheWidth,
      width: width,
      height: height,
      fit: fit,
      alignment: Alignment.topCenter,
      placeholderColor: Colors.black,
    );
    if (widget.image.isLive) {
      picture = Stack(
        fit: StackFit.passthrough,
        children: [
          picture,
          Positioned.fill(
            child: _LiveOverlay(
              url: widget.image.liveUrl!,
              active: widget.active,
              replay: widget.liveReplay,
              onPlaying: widget.onLivePlaying,
            ),
          ),
        ],
      );
    }
    return picture;
  }

  /// [fit] is what the flying copy uses: cover when the box already has the picture's shape, so
  /// it lands exactly on the cropped thumbnail; contain when the shape is still unknown.
  /// [flightAlignment] is the vertical alignment the copy starts from (the thumbnail is -1, top).
  Widget _hero(Widget child, {required BoxFit fit, double Function()? flightAlignment}) {
    final tag = widget.heroTag;
    if (tag == null) return child;
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: (context, animation, direction, fromContext, toContext) {
        final start = flightAlignment?.call() ?? -1.0;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) => ClipRRect(
            borderRadius: BorderRadius.circular(9 * (1 - animation.value)),
            child: SmartImage(
              url: widget.url,
              placeholderUrl: _underlay,
              cacheWidth: _cacheWidth,
              fit: fit,
              alignment: Alignment(0, -1 + (start + 1) * animation.value),
              placeholderColor: Colors.transparent,
            ),
          ),
        );
      },
      child: Material(type: MaterialType.transparency, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final long = _ratio > 0 && screen.width / _ratio > screen.height;
    final routeAnimation = ModalRoute.of(context)?.animation ?? const AlwaysStoppedAnimation<double>(1);

    final Widget heroed;
    final VoidCallback onDoubleTap;
    if (long) {
      final length = screen.width / _ratio;
      onDoubleTap = () => _toggleZoom(screen, Offset.zero & screen, 2);
      heroed = _hero(
        InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: _maxScale,
          panEnabled: _zoomed,
          onInteractionEnd: _onInteractionEnd,
          child: SingleChildScrollView(
            controller: _scroll,
            // Scrolling is driven by the page's own drag so it can hand over to drag-to-close;
            // the parent physics still shapes the fling.
            physics: const NeverScrollableScrollPhysics(parent: ClampingScrollPhysics()),
            child: _picture(width: screen.width, height: length, fit: BoxFit.cover),
          ),
        ),
        fit: BoxFit.cover,
        // Start the flight showing the slice that is on screen, not the top of the picture.
        flightAlignment: () {
          final travel = length - screen.height;
          if (!_scroll.hasClients || travel <= 0) return -1;
          return (_scroll.offset / travel * 2 - 1).clamp(-1.0, 1.0);
        },
      );
    } else {
      final known = _ratio > 0;
      final box = known ? Size(screen.width, screen.width / _ratio) : screen;
      final content = Rect.fromCenter(center: screen.center(Offset.zero), width: box.width, height: box.height);
      final fill = (screen.height / box.height).clamp(2.0, _maxScale);
      onDoubleTap = () => _toggleZoom(screen, content, fill);
      heroed = InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: _maxScale,
        panEnabled: _zoomed,
        onInteractionEnd: _onInteractionEnd,
        child: SizedBox.expand(
          child: Center(
            child: SizedBox.fromSize(
              size: box,
              child: _hero(
                _picture(width: box.width, height: box.height, fit: known ? BoxFit.cover : BoxFit.contain),
                fit: known ? BoxFit.cover : BoxFit.contain,
              ),
            ),
          ),
        ),
      );
    }

    final canDrag = !_zoomed && (!_multiTouch || _dragging);
    final page = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _multiTouch ? null : _onLongPress,
      onTap: _multiTouch ? null : widget.onToggleTools,
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: onDoubleTap,
      onVerticalDragStart: canDrag ? _onDragStart : null,
      onVerticalDragUpdate: canDrag ? (details) => _onDragUpdate(details, screen.height, long: long) : null,
      onVerticalDragEnd: canDrag ? _onDragEnd : null,
      onVerticalDragCancel: canDrag ? _animateDragBack : null,
      child: Transform.translate(
        offset: Offset(0, _drag),
        child: Transform.scale(
          scale: (1 - _drag.abs() / 1200).clamp(0.82, 1.0),
          child: heroed,
        ),
      ),
    );

    // Fades only when no Hero flies: during a flight the in-page copy is hidden anyway.
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: FadeTransition(opacity: routeAnimation, child: page),
    );
  }
}

class _BusyIcon extends StatelessWidget {
  const _BusyIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 19,
      height: 19,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

class _OriginalProgress extends StatelessWidget {
  const _OriginalProgress({required this.visible, required this.progress});

  final bool visible;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    return Center(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: TickerMode(
          enabled: visible,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: value,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  value == null ? '正在加载原图' : '正在加载原图 ${(value * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _SaveAs {
  picture('已保存到相册：', '图片保存失败'),
  motionPhoto('已保存实况照片：', '实况照片保存失败'),
  clip('已保存实况视频：', '实况视频保存失败');

  const _SaveAs(this.done, this.failed);

  final String done;
  final String failed;
}

/// Plays a live photo's motion clip once over the still, then fades back to it, like the
/// camera roll does. It starts when the page settles on screen and again on [replay].
class _LiveOverlay extends StatefulWidget {
  const _LiveOverlay({required this.url, required this.active, required this.replay, required this.onPlaying});

  final String url;
  final bool active;
  final ValueListenable<int> replay;
  final ValueChanged<bool> onPlaying;

  @override
  State<_LiveOverlay> createState() => _LiveOverlayState();
}

class _LiveOverlayState extends State<_LiveOverlay> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    widget.replay.addListener(_onReplay);
    if (widget.active) _playSoon();
  }

  @override
  void didUpdateWidget(_LiveOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replay != widget.replay) {
      oldWidget.replay.removeListener(_onReplay);
      widget.replay.addListener(_onReplay);
    }
    if (widget.active && !oldWidget.active) _playSoon();
    if (!widget.active && oldWidget.active) {
      _controller?.pause();
      _showing = false;
    }
  }

  @override
  void dispose() {
    widget.replay.removeListener(_onReplay);
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  /// After the opening flight or the page swipe has settled, not during it.
  void _playSoon() {
    Future<void>.delayed(const Duration(milliseconds: 360), () {
      if (mounted && widget.active) _play();
    });
  }

  void _onReplay() {
    if (widget.active) _play();
  }

  Future<void> _play() async {
    var controller = _controller;
    if (controller == null) {
      if (_loading) return;
      _loading = true;
      try {
        final file = await DefaultCacheManager().getSingleFile(
          sanitizeImageUrl(widget.url),
          headers: weiboImageHeaders(),
        );
        if (!mounted) return;
        controller = VideoPlayerController.file(file);
        await controller.initialize();
        if (!mounted) {
          controller.dispose();
          return;
        }
        await controller.setVolume(0);
        controller.addListener(_onTick);
        _controller = controller;
      } catch (_) {
        // The still stays when the clip cannot be fetched or played.
        controller?.dispose();
        return;
      } finally {
        _loading = false;
      }
    }
    if (!mounted || !widget.active) return;
    await controller.seekTo(Duration.zero);
    await controller.play();
    if (!mounted) return;
    setState(() => _showing = true);
    widget.onPlaying(true);
  }

  void _onTick() {
    final value = _controller!.value;
    if (!_showing || value.isPlaying || !value.isInitialized) return;
    if (value.position < value.duration - const Duration(milliseconds: 80)) return;
    setState(() => _showing = false);
    widget.onPlaying(false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final size = controller.value.size;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _showing ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(controller)),
        ),
      ),
    );
  }
}

/// Marks a live photo in the viewer's top bar; a tap plays the motion again.
class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.playing, required this.onTap});

  final ValueListenable<bool> playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ValueListenableBuilder<bool>(
          valueListenable: playing,
          builder: (context, playing, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: playing ? Colors.white : Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.motion_photos_on_rounded, size: 15, color: playing ? Colors.black : Colors.white),
                const SizedBox(width: 4),
                Text('实况', style: TextStyle(color: playing ? Colors.black : Colors.white, fontSize: 12, height: 1.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
