import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/prefs.dart';
import '../../core/status_store.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/mention_picker.dart';
import '../../core/widgets/smart_image.dart';

class ComposePage extends StatefulWidget {
  const ComposePage({
    super.key,
    this.type = DraftType.original,
    this.statusId,
    this.commentId,
    this.replyToName,
    this.draftId,
    this.initialText,
  });

  final DraftType type;
  final String? statusId;
  final String? commentId;
  final String? replyToName;
  final int? draftId;

  /// Prefilled text for a new post, e.g. the hashtag of the topic it was started from.
  final String? initialText;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<String> _images = [];
  Status? _target;
  int _draftId = 0;
  bool _crossPost = false;
  bool _busy = false;
  bool _loading = true;
  final EmojiKeyboard _emoji = EmojiKeyboard();
  String? _error;
  final HapticThreshold _limit = HapticThreshold();

  DraftType get _type => widget.type;
  bool get _isOriginal => _type == DraftType.original;
  bool get _isRepost => _type == DraftType.repost;
  bool get _isComment => _type == DraftType.comment || _type == DraftType.reply;
  int get _length => _text.text.characters.length;
  bool get _canSend {
    if (_loading || _busy || _length > 2000) return false;
    if (_isRepost) return true;
    return _text.text.trim().isNotEmpty || _images.isNotEmpty;
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
        _images.addAll(draft.images);
        _crossPost = draft.crossPost;
      }
    } else if (widget.initialText != null) {
      _text.text = widget.initialText!;
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
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
      if (mounted && !_isComment) _focus.requestFocus();
    });
  }

  void _insert(String value) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : _text.text.length;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    if (!_emoji.open) _focus.requestFocus();
  }

  Future<void> _pickImages() async {
    final room = 9 - _images.length;
    if (room <= 0 || !_isOriginal) return;
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 92, limit: room);
      if (picked.isEmpty) return;
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/drafts');
      if (!await folder.exists()) await folder.create(recursive: true);
      final next = <String>[];
      for (final file in picked.take(room)) {
        final target = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}-${file.name}';
        await File(file.path).copy(target);
        next.add(target);
      }
      if (mounted) setState(() => _images.addAll(next));
    } catch (error) {
      if (mounted) showMessage(context, '图片读取失败');
    }
  }

  Future<void> _pickMention() async {
    final name = await showMentionPicker(context);
    if (name != null) _insert('@$name ');
  }

  Future<void> _saveDraft() async {
    final drafts = Prefs.instance.drafts.toList();
    final text = _text.text;
    if (text.trim().isEmpty && _images.isEmpty && _draftId == 0) return;
    final id = _draftId == 0 ? Prefs.instance.nextDraftId : _draftId;
    final draft = Draft(
      id: id,
      type: _type,
      text: text,
      statusId: widget.statusId,
      commentId: widget.commentId,
      replyToName: widget.replyToName,
      images: _images.toList(),
      crossPost: _crossPost,
      state: DraftState.editing,
      updatedAt: DateTime.now(),
    );
    drafts.removeWhere((d) => d.id == id);
    drafts.add(draft);
    await Prefs.instance.saveDrafts(drafts);
  }

  Future<void> _removeDraft() async {
    if (_draftId == 0) return;
    final drafts = Prefs.instance.drafts.where((d) => d.id != _draftId).toList();
    await Prefs.instance.saveDrafts(drafts);
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isRepost) {
        await WeiboApi.instance.repost(widget.statusId ?? '', _text.text.trim(), _crossPost);
      } else if (_isComment) {
        if (_type == DraftType.reply && widget.commentId != null) {
          await WeiboApi.instance.reply(widget.statusId ?? '', widget.commentId!, _text.text.trim());
        } else {
          await WeiboApi.instance.comment(widget.statusId ?? '', _text.text.trim());
        }
      } else {
        final ids = <String>[];
        for (final path in _images) {
          ids.add(await WeiboApi.instance.uploadImage(File(path)));
        }
        await WeiboApi.instance.postStatus(_text.text.trim(), ids);
      }
      await _removeDraft();
      StatusStore.instance.bumpFeed();
      if (!mounted) return;
      Haptic.success.play();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('已发送')));
    } catch (error) {
      if (!mounted) return;
      Haptic.error.play();
      setState(() => _error = error is ApiException ? error.message : '发送失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestClose() async {
    if (_text.text.trim().isEmpty && _images.isEmpty) {
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
    if (action == 'discard') await _removeDraft();
    if (action != null && action != 'cancel' && mounted) Navigator.of(context).pop();
  }

  String get _title => switch (_type) {
        DraftType.original => '发微博',
        DraftType.repost => '转发微博',
        DraftType.comment => '发评论',
        DraftType.reply => widget.replyToName == null ? '回复评论' : '回复 ${widget.replyToName}',
      };

  String get _placeholder => switch (_type) {
        DraftType.original => '分享新鲜事…',
        DraftType.repost => '说说分享心得…',
        DraftType.comment => '写评论…',
        DraftType.reply => widget.replyToName == null ? '回复评论…' : '回复 ${widget.replyToName}…',
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
          leading: IconButton(onPressed: _requestClose, icon: const Icon(Icons.close_rounded)),
          title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _canSend ? _send : null,
                  style: FilledButton.styleFrom(minimumSize: const Size(62, 36)),
                  child: const Text('发送'),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) => SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(12, 6 + MediaQuery.paddingOf(context).top, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isRepost && _target != null) ...[
                              _TargetPreview(target: _target!),
                              const Divider(),
                            ],
                            TextField(
                              controller: _text,
                              focusNode: _focus,
                              minLines: _isOriginal ? 5 : 3,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              style: Theme.of(context).textTheme.bodyLarge,
                              decoration: InputDecoration(
                                hintText: _placeholder,
                                filled: false,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                counterText: '',
                              ),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _error!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                                ),
                              ),
                            if (_isOriginal && _images.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _ComposeImageGrid(
                                images: _images,
                                onRemove: (index) => setState(() => _images.removeAt(index)),
                              ),
                            ],
                            if (!_isOriginal && !_isComment) ...[
                              const SizedBox(height: 8),
                              _CrossPostRow(
                                checked: _crossPost,
                                label: _isRepost && _target != null
                                    ? '同时评论给 @${_target!.author.screenName}'
                                    : '同时转发到我的微博',
                                onChanged: (value) => setState(() => _crossPost = value),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  _Toolbar(
                    canAddImage: _isOriginal && _images.length < 9,
                    emojiOpen: _emoji.open,
                    count: _length,
                    over: _length > 2000,
                    inset: _emoji.heightFor(context),
                    onPickImage: _pickImages,
                    onMention: _pickMention,
                    onTopic: () => _insert('##'),
                    onEmoji: () => _emoji.toggle(context, _focus),
                    onPickEmoji: _insert,
                  ),
                ],
              ),
      ),
    );
  }
}

class _TargetPreview extends StatelessWidget {
  const _TargetPreview({required this.target});

  final Status target;

  @override
  Widget build(BuildContext context) {
    final thumb = target.media.isEmpty
        ? null
        : (target.media.first.kind == MediaKind.video ? target.media.first.previewUrl : target.media.first.previewUrl);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
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

class _CrossPostRow extends StatelessWidget {
  const _CrossPostRow({required this.checked, required this.label, required this.onChanged});

  final bool checked;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 19,
              color: checked ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: checked ? scheme.primary : scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.canAddImage,
    required this.emojiOpen,
    required this.count,
    required this.over,
    required this.inset,
    required this.onPickImage,
    required this.onMention,
    required this.onTopic,
    required this.onEmoji,
    required this.onPickEmoji,
  });

  final bool canAddImage;
  final bool emojiOpen;
  final int count;
  final bool over;
  final double inset;
  final VoidCallback onPickImage;
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          children: [
              if (canAddImage)
                IconButton(
                  onPressed: onPickImage,
                  tooltip: '添加图片',
                  icon: const Icon(Icons.image_outlined),
                ),
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
        EmojiKeyboardSlot(open: emojiOpen, height: inset, onPick: onPickEmoji),
      ],
    );
    return InfChrome.of(context).edgePanel(context, child: column);
  }
}
