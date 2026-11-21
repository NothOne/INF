import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/endpoints.dart';
import '../../core/error_text.dart';
import '../../core/haptics.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/prefs.dart';
import '../../core/status_store.dart';
import '../../core/temp_files.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/compose_options.dart';
import '../../core/widgets/mention_picker.dart';
import '../../core/widgets/smart_image.dart';
import '../../core/widgets/topic_picker.dart';

class ComposePage extends StatefulWidget {
  const ComposePage({
    super.key,
    this.type = DraftType.original,
    this.statusId,
    this.draftId,
    this.initialText,
  });

  final DraftType type;
  final String? statusId;
  final int? draftId;

  /// Prefilled text for a new post, e.g. the hashtag of the topic it was started from.
  final String? initialText;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _videoTitle = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<String> _images = [];
  Status? _target;
  int _draftId = 0;
  bool _crossPost = false;
  PostVisibility _visibility = PostVisibility.public;
  ContentStatement _statement = ContentStatement.none;
  String? _videoPath;
  int _videoSize = 0;
  bool _busy = false;
  bool _loading = true;
  final EmojiKeyboard _emoji = EmojiKeyboard();
  String? _error;

  /// What the publish is doing right now, shown above the toolbar. `_uploadProgress` is the video's
  /// byte progress; null makes the bar indeterminate, which is what 「正在发布…」 is.
  double? _uploadProgress;
  String? _uploadStage;
  final HapticThreshold _limit = HapticThreshold();

  DraftType get _type => widget.type;
  bool get _isOriginal => _type == DraftType.original;
  bool get _isRepost => _type == DraftType.repost;

  /// Whether the request this page is about to send can be answered with a captcha.
  ///
  /// Read from `endpoints.dart` rather than decided here: whether Weibo can ask for a captcha is a
  /// property of the endpoint, and this page is the one place the reader is about to lose a draft
  /// to one, so it says so up front.
  bool get _mayNeedCaptcha =>
      (_isRepost ? Endpoint.repost : Endpoint.postStatus).captchaRisk;
  int get _length => _text.text.characters.length;
  bool get _hasContent => _text.text.trim().isNotEmpty || _images.isNotEmpty || _videoPath != null;
  bool get _canSend {
    if (_loading || _busy || _length > 2000) return false;
    // A repost goes out with no words at all — Weibo fills in 转发微博 itself — so the button stays
    // live there and this is only the original post's rule.
    if (_isRepost) return true;
    return _hasContent;
  }

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _emoji.addListener(_onEmoji);
    _focus.addListener(_onFocus);
    _load();
  }

  @override
  void dispose() {
    _text.removeListener(_changed);
    _emoji.removeListener(_onEmoji);
    _focus.removeListener(_onFocus);
    _emoji.dispose();
    _text.dispose();
    _videoTitle.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onEmoji() {
    if (mounted) setState(() {});
  }

  void _onFocus() => _emoji.onFocusChanged(_focus.hasFocus);

  void _changed() {
    if (!_loading) _limit.update(_length > 2000 ? 1 : 0);
    setState(() {});
  }

  Future<void> _load() async {
    if (widget.draftId != null) {
      final draft = Prefs.instance.drafts.where((d) => d.id == widget.draftId).firstOrNull;
      if (draft != null) {
        _draftId = draft.id;
        _text.text = draft.text;
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
        _images.addAll(draft.images);
        _crossPost = draft.crossPost;
        _visibility = draft.visibility;
        _statement = draft.statement;
        _videoPath = draft.videoPath;
        if (_videoPath != null) _videoSize = await _sizeOf(_videoPath!);
      }
    } else if (widget.initialText != null) {
      _text.text = widget.initialText!;
      // A repost that comes with a forwarding chain puts the caret before the `//@…` it quotes: the
      // thing the reader came to write is their own words, and typing at the end appends to the
      // chain instead.
      final chainFirst = _isRepost && _text.text.startsWith('//@');
      _text.selection = TextSelection.collapsed(offset: chainFirst ? 0 : _text.text.length);
    }
    final statusId = widget.statusId;
    if (statusId != null) {
      try {
        final status = await WeiboApi.instance.status(statusId);
        if (mounted) setState(() => _target = status);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<int> _sizeOf(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }

  /// Puts [value] where the caret is, with the caret [caret] characters into it. A topic typed by
  /// hand wants it between the two `#`s, not after them.
  void _insert(String value, {int? caret}) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : _text.text.length;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + (caret ?? value.length)),
    );
    if (!_emoji.open) _focus.requestFocus();
  }

  Future<void> _pickImages() async {
    final room = 9 - _images.length;
    if (room <= 0) return;
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 92, limit: room);
      if (picked.isEmpty) return;
      final next = <String>[];
      for (final file in picked.take(room)) {
        next.add(await DraftFiles.add(File(file.path)));
      }
      if (mounted) setState(() => _images.addAll(next));
    } catch (error) {
      if (mounted) showMessage(context, '图片读取失败');
    }
  }

  /// The image button stays on screen while a video is attached, and says why it will not work:
  /// a disabled-looking button that does nothing reads as a bug, and swapping one attachment for
  /// another without being asked would throw away what the reader picked.
  void _onPickImage() {
    if (_videoPath != null) {
      Haptic.error.play();
      showMessage(context, '图片和视频不能同时发布');
      return;
    }
    if (_images.length >= 9) {
      Haptic.error.play();
      showMessage(context, '最多只能添加 9 张图片');
      return;
    }
    _pickImages();
  }

  Future<void> _pickVideo() async {
    if (_images.isNotEmpty) {
      Haptic.error.play();
      showMessage(context, '图片和视频不能同时发布');
      return;
    }
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      final size = await _sizeOf(picked.path);
      if (!mounted) return;
      setState(() {
        _videoPath = picked.path;
        _videoSize = size;
      });
    } catch (error) {
      if (mounted) showMessage(context, '视频读取失败');
    }
  }

  /// Takes the video out of the post without touching the file: the path points into the reader's
  /// own gallery, so only the draft's copy of the path may go.
  void _removeVideo() {
    setState(() {
      _videoPath = null;
      _videoSize = 0;
      _videoTitle.clear();
    });
  }

  Future<void> _pickMention() async {
    final name = await showMentionPicker(context);
    if (name != null) _insert('@$name ');
  }

  Future<void> _pickTopic() async {
    final topic = await showTopicPicker(context);
    if (topic == null) return;
    // '' is the picker's 「自己输入」: an empty pair with the caret between them.
    if (topic.isEmpty) {
      _insert('##', caret: 1);
    } else {
      _insert('#$topic# ');
    }
  }

  Future<void> _pickVisibility() async {
    final picked = await showVisibilityPicker(context, _visibility);
    if (picked != null) setState(() => _visibility = picked);
  }

  Future<void> _pickStatement() async {
    final picked = await showContentStatementPicker(context, _statement);
    if (picked != null) setState(() => _statement = picked);
  }

  Future<void> _saveDraft() async {
    final drafts = Prefs.instance.drafts.toList();
    final text = _text.text;
    if (!_hasContent && _draftId == 0) return;
    final id = _draftId == 0 ? Prefs.instance.nextDraftId : _draftId;
    final draft = Draft(
      id: id,
      type: _type,
      text: text,
      statusId: widget.statusId,
      images: _images.toList(),
      videoPath: _videoPath,
      crossPost: _crossPost,
      visibility: _visibility,
      statement: _statement,
      state: DraftState.editing,
      updatedAt: DateTime.now(),
    );
    drafts.removeWhere((d) => d.id == id);
    drafts.add(draft);
    await Prefs.instance.saveDrafts(drafts);
    // A picture the reader took back out of the post is in no draft any more.
    await DraftFiles.sweep();
  }

  Future<void> _removeDraft() async {
    if (_draftId == 0) return;
    final draft = Prefs.instance.drafts.where((d) => d.id == _draftId).firstOrNull;
    final drafts = Prefs.instance.drafts.where((d) => d.id != _draftId).toList();
    await Prefs.instance.saveDrafts(drafts);
    // The pictures came with the draft; nothing else refers to them now.
    if (draft != null) await DraftFiles.delete(draft.images);
  }

  void _stage(String stage, double? progress) {
    if (!mounted) return;
    setState(() {
      _uploadStage = stage;
      _uploadProgress = progress;
    });
  }

  Future<List<String>> _uploadImages() async {
    final ids = <String>[];
    for (var i = 0; i < _images.length; i++) {
      _stage('上传图片 ${i + 1}/${_images.length}', i / _images.length);
      ids.add(await WeiboApi.instance.uploadImage(File(_images[i])));
    }
    return ids;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _busy = true;
      _error = null;
      _uploadStage = _videoPath != null
          ? '上传视频 0%'
          : _images.isEmpty
              ? '正在发布…'
              : '上传图片 1/${_images.length}';
      _uploadProgress = null;
    });
    try {
      if (_isRepost) {
        // A repost with pictures goes through weibo.com's own composer, which is the only one of
        // the two that accepts them.
        final ids = await _uploadImages();
        _stage('正在发布…', null);
        await WeiboApi.instance.repost(
          widget.statusId ?? '',
          _text.text.trim(),
          _crossPost,
          picIds: ids,
          visibility: _visibility,
        );
        final target = _target;
        if (target != null) StatusStore.instance.addRepost(target);
      } else {
        VideoUploadResult? video;
        if (_videoPath != null) {
          video = await WeiboApi.instance.uploadVideo(
            File(_videoPath!),
            onProgress: (progress) => _stage('上传视频 ${(progress * 100).round()}%', progress),
          );
        }
        // Weibo takes pictures or a video, never both; the buttons above already keep the two
        // apart, so only one of these lists is ever filled.
        final ids = video == null ? await _uploadImages() : const <String>[];
        _stage('正在发布…', null);
        await WeiboApi.instance.postStatus(
          _text.text.trim(),
          ids,
          visibility: _visibility,
          statement: _statement,
          video: video,
          videoTitle: _videoTitle.text.trim(),
        );
      }
      await _removeDraft();
      StatusStore.instance.bumpFeed();
      if (!mounted) return;
      Haptic.success.play();
      final bar = infSnackBar(context, const Text('已发送'));
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(bar);
    } catch (error) {
      if (!mounted) return;
      Haptic.error.play();
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadStage = null;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _requestClose() async {
    if (!_hasContent) {
      await _removeDraft();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存为草稿？'),
        content: const Text('离开后这条内容还在草稿箱里。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('不保存')),
          TextButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('保存')),
        ],
      ),
    );
    if (action == 'save') await _saveDraft();
    if (action == 'discard') {
      await _removeDraft();
      // Whoever leaves without saving leaves their pictures behind otherwise: they were copied in
      // for this post alone, and no draft refers to them now.
      await DraftFiles.sweep();
    }
    if (action != null && action != 'cancel' && mounted) Navigator.of(context).pop();
  }

  String get _title => switch (_type) {
        DraftType.original => '发微博',
        DraftType.repost => '转发微博',
      };

  String get _placeholder => switch (_type) {
        DraftType.original => '分享新鲜事…',
        DraftType.repost => _target == null ? '说说分享心得…' : '说点什么…（可以不写）',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
        appBar: AppBar(
          flexibleSpace: lookBarBackground(context),
          leadingWidth: 76,
          leading: TextButton(
            onPressed: _requestClose,
            style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
            child: const Text('取消'),
          ),
          centerTitle: true,
          title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: FilledButton(
                  onPressed: _canSend ? _send : null,
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 36)),
                  child: const Text('发布'),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            // Builder reads Scaffold's MediaQuery (status bar + AppBar when extendBodyBehindAppBar
            // is true) rather than the outer context, which only has the status bar and let the
            // AppBar cover the repost preview card.
            : Builder(
                builder: (bodyContext) => Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(16, 10 + MediaQuery.paddingOf(bodyContext).top, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isRepost && _target != null) ...[
                            _TargetPreview(target: _target!),
                            const SizedBox(height: 10),
                          ],
                          TextField(
                            controller: _text,
                            focusNode: _focus,
                            minLines: _isOriginal ? 6 : 4,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.45),
                            decoration: InputDecoration(
                              hintText: _placeholder,
                              filled: false,
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 6),
                              counterText: '',
                            ),
                          ),
                          if (_videoPath != null) ...[
                            const SizedBox(height: 14),
                            _VideoPreviewCard(
                              path: _videoPath!,
                              size: _videoSize,
                              title: _videoTitle,
                              onRemove: _removeVideo,
                            ),
                          ],
                          if (_images.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _ComposeImageGrid(
                              images: _images,
                              onRemove: (index) => setState(() => _images.removeAt(index)),
                            ),
                          ],
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                _error!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                              ),
                            ),
                          // 发微博 and 转发 are the writes `Endpoint.captchaRisk` marks: Weibo may
                          // answer them with a captcha instead of posting. Saying so while the
                          // reader still has the words on screen is the point — finding out
                          // afterwards means having written something that did not go out.
                          if (_canSend && _mayNeedCaptcha)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.verified_user_outlined, size: 14, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      '微博有时会要求先完成一次安全验证，完成后会自动继续发送',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_uploadStage != null)
                    _PublishProgress(value: _uploadProgress, stage: _uploadStage!),
                  _optionStrip(context),
                  _Toolbar(
                    showVideo: _isOriginal,
                    emojiOpen: _emoji.open,
                    emojiVisible: _emoji.boardVisible,
                    count: _length,
                    over: _length > 2000,
                    inset: _emoji.insetFor(context),
                    onPickImage: _onPickImage,
                    onPickVideo: _pickVideo,
                    onMention: _pickMention,
                    onTopic: _pickTopic,
                    onEmoji: () => _emoji.toggle(context, _focus),
                    onPickEmoji: _insert,
                  ),
                ],
              ),
            ),
      ),
    );
  }

  /// The row of choices directly above the toolbar: what the post is, and who may see it.
  Widget _optionStrip(BuildContext context) {
    Widget gap() => const SizedBox(width: 8);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
      child: Row(
        children: [
          if (_isOriginal) ...[
            ComposeOptionPill(
              icon: _statement == ContentStatement.none
                  ? Icons.fact_check_outlined
                  : Icons.fact_check_rounded,
              label: _statement == ContentStatement.none ? '内容声明' : _statement.shortLabel,
              active: _statement != ContentStatement.none,
              onTap: _pickStatement,
            ),
            gap(),
          ] else ...[
            ComposeOptionPill(
              icon: _crossPost ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              label: '同时评论',
              active: _crossPost,
              onTap: () {
                (_crossPost ? Haptic.toggleOff : Haptic.toggleOn).play();
                setState(() => _crossPost = !_crossPost);
              },
            ),
            gap(),
          ],
          ComposeOptionPill(
            icon: visibilityIcon(_visibility),
            label: _visibility.label,
            active: _visibility != PostVisibility.public,
            onTap: _pickVisibility,
          ),
        ],
      ),
    );
  }
}

/// The publish's progress, drawn between the editor and the option strip so the words stay where
/// they are while the bytes go out.
class _PublishProgress extends StatelessWidget {
  const _PublishProgress({required this.value, required this.stage});

  final double? value;
  final String stage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            stage,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: value, minHeight: 3),
          ),
        ],
      ),
    );
  }
}

class _TargetPreview extends StatelessWidget {
  const _TargetPreview({required this.target});

  final Status target;

  @override
  Widget build(BuildContext context) {
    final thumb = target.media.isEmpty ? null : target.media.first.previewUrl;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.6),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          if (thumb != null && thumb.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SmartImage(url: thumb, width: 54, height: 54),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${target.author.screenName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary),
                ),
                const SizedBox(height: 2),
                Text(
                  target.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The video attached to the post: what it is, how big, an optional title, and a way to take it
/// back out.
class _VideoPreviewCard extends StatelessWidget {
  const _VideoPreviewCard({
    required this.path,
    required this.size,
    required this.title,
    required this.onRemove,
  });

  final String path;
  final int size;
  final TextEditingController title;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = path.split(Platform.pathSeparator).last;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.videocam_rounded, color: scheme.onPrimaryContainer, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      size > 0 ? formatBytes(size) : '视频',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: '移除视频',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: title,
            textInputAction: TextInputAction.done,
            style: Theme.of(context).textTheme.bodySmall,
            decoration: InputDecoration(
              hintText: '给视频加个标题（可选）',
              isDense: true,
              filled: true,
              fillColor: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHighest, 0.7),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposeImageGrid extends StatelessWidget {
  const _ComposeImageGrid({required this.images, required this.onRemove});

  final List<String> images;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 5.0;
        final cell = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < images.length; i++)
              SizedBox(
                width: cell,
                height: cell,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(images[i]), fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 3,
                      right: 3,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.showVideo,
    required this.emojiOpen,
    required this.emojiVisible,
    required this.count,
    required this.over,
    required this.inset,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onMention,
    required this.onTopic,
    required this.onEmoji,
    required this.onPickEmoji,
  });

  final bool showVideo;
  final bool emojiOpen;
  final bool emojiVisible;
  final int count;
  final bool over;
  final double inset;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback onMention;
  final VoidCallback onTopic;
  final VoidCallback onEmoji;
  final ValueChanged<String> onPickEmoji;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = SafeArea(
      top: false,
      bottom: inset == 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(onPressed: onPickImage, tooltip: '添加图片', icon: const Icon(Icons.image_outlined)),
            if (showVideo)
              IconButton(onPressed: onPickVideo, tooltip: '添加视频', icon: const Icon(Icons.videocam_outlined)),
            IconButton(onPressed: onMention, tooltip: '提及', icon: const Icon(Icons.alternate_email_rounded)),
            IconButton(onPressed: onTopic, tooltip: '话题', icon: const Icon(Icons.tag_rounded)),
            IconButton(
              onPressed: onEmoji,
              tooltip: '表情',
              icon: Icon(emojiOpen ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined),
            ),
            const Spacer(),
            Text(
              '$count/2000',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: over ? scheme.error : scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        EmojiKeyboardSlot(visible: emojiVisible, height: inset, onPick: onPickEmoji),
      ],
    );
    return InfChrome.of(context).edgePanel(context, child: column);
  }
}
