import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import 'mention_picker.dart';

/// A comment is a panel of the page it answers, not a destination. The post stays visible behind
/// the sheet, exactly like the original client's in-page comment panel.
Future<bool?> showCommentSheet(
  BuildContext context, {
  required String statusId,
  String? commentId,
  String? replyToName,
  String? replyToText,
  Status? target,
}) {
  return showInfSheet<bool>(
    context: context,
    builder: (sheetContext) => CommentSheet(
      statusId: statusId,
      commentId: commentId,
      replyToName: replyToName,
      replyToText: replyToText,
      target: target,
      onSent: () => Navigator.of(sheetContext).pop(true),
    ),
  );
}

class CommentSheet extends StatefulWidget {
  const CommentSheet({
    super.key,
    required this.statusId,
    required this.onSent,
    this.commentId,
    this.replyToName,
    this.replyToText,
    this.target,
  });

  final String statusId;
  final String? commentId;
  final String? replyToName;
  final String? replyToText;
  final Status? target;
  final VoidCallback onSent;

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _crossPost = false;
  bool _sending = false;
  final EmojiKeyboard _emoji = EmojiKeyboard();
  String? _error;
  final HapticThreshold _limit = HapticThreshold();

  bool get _isReply => widget.commentId != null;
  int get _length => _text.text.characters.length;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _emoji.addListener(_onEmoji);
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
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
    _limit.update(_length > 140 ? 1 : 0);
    setState(() {});
  }

  void _insert(String value) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : _text.text.length;
    final next = _text.text.replaceRange(start, end, value);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    if (!_emoji.open) _focus.requestFocus();
  }

  Future<void> _send() async {
    final content = _text.text.trim();
    if (content.isEmpty || _sending || _length > 140) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (_isReply) {
        await WeiboApi.instance.reply(widget.statusId, widget.commentId!, content);
      } else {
        await WeiboApi.instance.comment(widget.statusId, content);
      }
      if (!mounted) return;
      Haptic.success.play();
      final messenger = ScaffoldMessenger.of(context);
      widget.onSent();
      messenger.showSnackBar(SnackBar(content: Text(_isReply ? '回复成功' : '评论成功')));
    } catch (error) {
      if (!mounted) return;
      Haptic.error.play();
      setState(() => _error = error is ApiException ? error.message : '发送失败');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickMention() async {
    final name = await showMentionPicker(context);
    if (name != null) _insert('@$name ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quoted = _quotedLine();
    final over = _length > 140;
    final slot = _emoji.heightFor(context);
    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          top: false,
          bottom: slot == 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 9, 10, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isReply
                            ? (widget.replyToName == null ? '回复评论' : '回复 ${widget.replyToName}')
                            : '发评论',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Text(
                      '$_length/140',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: over ? scheme.error : scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(width: 8),
                    if (_sending)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      FilledButton(
                        onPressed: _text.text.trim().isEmpty || over ? null : _send,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(58, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Text('发送'),
                      ),
                  ],
                ),
              ),
              if (quoted != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          quoted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _text,
                focusNode: _focus,
                minLines: 1,
                maxLines: 4,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: _isReply ? '回复评论…' : '写评论…',
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  counterText: '',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _pickMention,
                      iconSize: 20,
                      tooltip: '提及',
                      icon: const Icon(Icons.alternate_email_rounded),
                    ),
                    IconButton(
                      onPressed: () {
                        _insert('##');
                        _text.selection = TextSelection.collapsed(offset: _text.text.length - 1);
                      },
                      iconSize: 20,
                      tooltip: '话题',
                      icon: const Icon(Icons.tag_rounded),
                    ),
                    IconButton(
                      onPressed: () => _emoji.toggle(context, _focus),
                      iconSize: 20,
                      tooltip: '表情',
                      icon: Icon(_emoji.open ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined),
                    ),
                    const SizedBox(width: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _crossPost = !_crossPost),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                        child: Row(
                          children: [
                            Icon(
                              _crossPost ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              size: 16,
                              color: _crossPost ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '同时转发',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: _crossPost ? scheme.primary : scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      iconSize: 22,
                      tooltip: '收起',
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        EmojiKeyboardSlot(open: _emoji.open, height: slot, onPick: _insert),
      ],
    );
    return InfChrome.of(context).typingSheet(
      context,
      radius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: panel,
    );
  }

  String? _quotedLine() {
    if (_isReply) {
      final name = widget.replyToName;
      final text = widget.replyToText;
      if (text == null || text.isEmpty) return name == null ? null : '@${name}';
      return (name == null ? text : '${name}：${text}').replaceAll('\n', ' ');
    }
    final target = widget.target;
    if (target == null) return null;
    return '@${target.author.screenName}：${target.text}'.replaceAll('\n', ' ');
  }
}
