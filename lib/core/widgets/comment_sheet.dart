import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/comment_store.dart';
import '../../core/haptics.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/temp_files.dart';
import 'common.dart';
import 'mention_picker.dart';
import 'surface_card_route.dart';
import 'topic_picker.dart';

/// A comment is a panel of the page it answers, not a destination. It grows out of the control that
/// opened it and goes back into it, the way a post's menu does — see [showSurfaceCard] — so the page
/// behind stays visible around it and the reader can see where it came from.
///
/// [rootId] is the comment whose thread this reply belongs to; [commentId] is the comment being
/// answered. For a reply to a top-level comment the two are the same, and only [commentId] is
/// passed. They are only different when a reply to a reply is answered.
///
/// [countOnPost] is passed through to [CommentStore.send]: off where the caller only knows the
/// post's id, so a count is not invented from a zero.
///
/// Without [anchor] there is nothing for the panel to grow out of, so it rises from the bottom edge
/// instead — still square at the foot, still solid.
Future<bool?> showCommentSheet(
  BuildContext context, {
  BuildContext? anchor,
  required Status status,
  String? commentId,
  String? rootId,
  String? replyToName,
  String? replyToText,
  bool countOnPost = true,
}) {
  Widget sheet(BuildContext sheetContext) => CommentSheet(
        status: status,
        commentId: commentId,
        rootId: rootId,
        replyToName: replyToName,
        replyToText: replyToText,
        countOnPost: countOnPost,
        onSent: () => Navigator.of(sheetContext).pop(true),
      );
  final origin = anchor;
  if (origin == null) {
    // A modal sheet draws no surface of its own, so the style draws the panel's material here.
    // Under `showSurfaceCard` the route does it, around the panel it grows out of.
    return showInfSheet<bool>(
      context: context,
      builder: (sheetContext) => InfChrome.of(sheetContext).typingSheet(
        sheetContext,
        radius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: sheet(sheetContext),
      ),
    );
  }
  return showSurfaceCard<bool>(context, anchor: origin, builder: sheet);
}

class CommentSheet extends StatefulWidget {
  const CommentSheet({
    super.key,
    required this.status,
    required this.onSent,
    this.commentId,
    this.rootId,
    this.replyToName,
    this.replyToText,
    this.countOnPost = true,
  });

  /// The post being commented on. Its id addresses the request, and its author and text are what
  /// the panel quotes.
  final Status status;

  /// The comment being answered; null for a new comment on the post.
  final String? commentId;

  /// The comment the thread hangs off, when this answers a reply rather than the top-level comment.
  final String? rootId;

  final String? replyToName;
  final String? replyToText;

  /// Whether the post's comment count can be raised from what the caller knows. Off for a page that
  /// has the post's id but not its counts.
  final bool countOnPost;

  final VoidCallback onSent;

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  bool _crossPost = false;
  bool _sending = false;
  final EmojiKeyboard _keyboard = EmojiKeyboard();
  String? _error;
  final HapticThreshold _limit = HapticThreshold();

  /// The picture to go with the comment, copied into the scratch folder until it is sent.
  ///
  /// One, not nine. Weibo's own comment box allows a single picture, and the comment endpoints take
  /// one `picId`, so a second slot would only promise what the request cannot carry.
  ///
  /// Whether an account may send one at all is Weibo's call, not the app's: the permission is granted
  /// to some accounts and not others. Nothing here hides the button from the accounts that lack it —
  /// the app cannot know which they are — so a refusal arrives as an upload error and is explained
  /// in [_failure].
  String? _picture;

  bool get _isReply => widget.commentId != null;
  int get _length => _text.text.characters.length;

  /// Whether there is anything to send: words within the limit. A picture does not stand on its own —
  /// the endpoints take one, but a comment without words is not what either client offers.
  bool get _canSend => _text.text.trim().isNotEmpty && _length <= 140;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _keyboard.addListener(_onKeyboard);
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _text.removeListener(_changed);
    _keyboard.removeListener(_onKeyboard);
    _focus.removeListener(_onFocus);
    _keyboard.dispose();
    _text.dispose();
    _focus.dispose();
    // Nothing was sent, so the copy in the scratch folder is nobody's.
    if (_picture != null) TempFiles.delete(_picture!);
    super.dispose();
  }

  void _onKeyboard() {
    if (mounted) setState(() {});
  }

  void _onFocus() => _keyboard.onFocusChanged(_focus.hasFocus);

  void _changed() {
    _limit.update(_length > 140 ? 1 : 0);
    setState(() {});
  }

  /// Puts [value] where the cursor is, leaving the caret [caretBack] characters before its end —
  /// which is how `##` ends up with the caret between the hashes, ready to be typed into.
  void _insert(String value, {int caretBack = 0}) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : _text.text.length;
    final next = _text.text.replaceRange(start, end, value);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length - caretBack),
    );
    if (!_keyboard.open) _focus.requestFocus();
  }

  Future<void> _send() async {
    final picture = _picture;
    if (!_canSend || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    // The picture goes up as the comment is sent, not when it is picked: a picture the reader
    // thought better of never reaches the service, and no id is left behind for a comment that was
    // not made. That, and the two ids a reply needs, live in [CommentStore.send].
    final crossPost = _crossPost;
    final failure = await CommentStore.instance.send(
      status: widget.status,
      text: _text.text,
      rootId: widget.commentId == null ? null : (widget.rootId ?? widget.commentId),
      replyToId: widget.commentId,
      replyToName: widget.replyToName,
      replyToText: widget.replyToText,
      picturePath: picture,
      crossPost: crossPost,
      countOnPost: widget.countOnPost,
    );
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _sending = false;
        _error = failure;
      });
      return;
    }
    Haptic.success.play();
    final doneText = _isReply
        ? (crossPost ? '已回复并转发' : '回复成功')
        : (crossPost ? '已评论并转发' : '评论成功');
    final bar = infSnackBar(context, Text(doneText));
    final messenger = ScaffoldMessenger.of(context);
    widget.onSent();
    messenger.showSnackBar(bar);
  }

  /// Picks the picture for this comment, replacing any already attached.
  Future<void> _pickPicture() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (picked == null) return;
    final file = await TempFiles.file('comment-${DateTime.now().microsecondsSinceEpoch}.jpg');
    await File(picked.path).copy(file.path);
    // The panel can be dismissed while the picker is in front of it. The copy was made for a comment
    // that no longer exists, so it goes rather than waiting for the sweep.
    if (!mounted) {
      await TempFiles.delete(file.path);
      return;
    }
    final previous = _picture;
    setState(() => _picture = file.path);
    if (previous != null) await TempFiles.delete(previous);
  }

  Future<void> _removePicture() async {
    final picture = _picture;
    if (picture == null) return;
    setState(() => _picture = null);
    await TempFiles.delete(picture);
  }

  Future<void> _pickMention() async {
    final name = await showMentionPicker(context);
    if (!mounted || name == null) return;
    _insert('@$name ');
  }

  Future<void> _pickTopic() async {
    final topic = await showTopicPicker(context);
    if (!mounted || topic == null) return;
    // An empty answer is 「自己输入」: the pair goes in and the caret lands between it.
    if (topic.isEmpty) {
      _insert('##', caretBack: 1);
    } else {
      _insert('#$topic# ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = _length > 140;
    final slot = _keyboard.boardHeight(context);
    // Nothing is held for the safe area while the keys or the emoji board cover the foot of the
    // screen: the board pads its own foot, and the keys are below the panel entirely. That is what
    // keeps the field on the same line while one gives way to the other — the number never changes.
    final bottomSafe = slot > 0 || MediaQuery.viewInsetsOf(context).bottom > 0
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;
    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: bottomSafe),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Only a reply quotes what it answers: a new comment has nothing to quote that the
              // post's own card above the panel is not already showing.
              if (_isReply) _Quote(text: _quotedLine() ?? ''),
              Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                decoration: BoxDecoration(
                  color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 3,
                      maxLines: 5,
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: _hint,
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        counterText: '',
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        '$_length/140',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: over ? scheme.error : scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ),
              // The picture sits above the field's controls, where what has been attached to the
              // comment is looked for, and takes its usual 56 dp square — a comment carries one.
              if (_picture != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _AttachedPicture(path: _picture!, onRemove: _sending ? null : _removePicture),
                  ),
                ),
              _toolbar(context, scheme),
            ],
          ),
        ),
        // The board only takes height when it is open. While the keyboard is up the panel has
        // already been placed above it (see `surface_card_route.dart`), so holding the keyboard's
        // height here as well left a slab of empty panel between the field and the keys.
        if (slot > 0) EmojiKeyboardSlot(visible: _keyboard.boardVisible, height: slot, onPick: _insert),
      ],
    );
    // Square at the foot: the panel rests on the keyboard, or on the bottom edge of the screen, so
    // a rounded foot would read as a sheet that had not finished arriving. The surface itself is
    // drawn by whoever opened the panel — `showCommentSheet` — because it is also the one that
    // draws the panel out of the control it came from.
    return panel;
  }

  String get _hint {
    if (!_isReply) return '写评论…';
    final name = widget.replyToName;
    return name == null ? '回复评论…' : '回复 @$name…';
  }

  /// Everything beside and under the field, on one row: what the comment is, then what goes in it,
  /// then the button that sends it.
  Widget _toolbar(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 10, 6),
      child: Row(
        children: [
          _CrossPostToggle(value: _crossPost, onTap: () => setState(() => _crossPost = !_crossPost)),
          const SizedBox(width: 4),
          _tool(
            icon: Icons.alternate_email_rounded,
            tooltip: '提及',
            onPressed: _pickMention,
          ),
          const SizedBox(width: 2),
          _tool(
            icon: Icons.tag_rounded,
            tooltip: '话题',
            onPressed: _pickTopic,
          ),
          const SizedBox(width: 2),
          _tool(
            icon: _keyboard.open ? Icons.keyboard_outlined : Icons.sentiment_satisfied_outlined,
            tooltip: '表情',
            onPressed: () => _keyboard.toggle(context, _focus),
          ),
          const SizedBox(width: 2),
          _tool(
            icon: _picture == null ? Icons.image_outlined : Icons.image_rounded,
            tooltip: _picture == null ? '图片' : '取消图片',
            color: _picture == null ? null : scheme.primary,
            onPressed: _sending ? null : (_picture == null ? _pickPicture : _removePicture),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _canSend && !_sending ? _send : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(54, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('发送'),
          ),
        ],
      ),
    );
  }

  /// One icon in the toolbar. Sized at 38 dp with a 23 dp glyph so taps feel uncramped while the
  /// full row still fits on a 320 dp phone alongside 同时转发 and 发送.
  Widget _tool({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 23,
      color: color,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }

  String? _quotedLine() {
    if (_isReply) {
      final name = widget.replyToName;
      final text = widget.replyToText;
      if (text == null || text.isEmpty) return name == null ? null : '@$name';
      return (name == null ? text : '$name：$text').replaceAll('\n', ' ');
    }
    final target = widget.status;
    return '@${target.author.screenName}：${target.text}'.replaceAll('\n', ' ');
  }
}

/// The comment being answered, on one line above the field: enough to know what the reply is
/// against, without the header bar that used to sit above it.
class _Quote extends StatelessWidget {
  const _Quote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// 同时转发: a small tick with its label, offered only where it can be honoured.
class _CrossPostToggle extends StatelessWidget {
  const _CrossPostToggle({required this.value, required this.onTap});

  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = value ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      key: const ValueKey('comment-crosspost'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 4),
            Text('同时转发', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// The picture attached to the comment: a small square with its own remove button, the same size as
/// the one the composer shows.
class _AttachedPicture extends StatelessWidget {
  const _AttachedPicture({required this.path, this.onRemove});

  final String path;

  /// Null while the comment is going out, when taking the picture back no longer means anything.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(path), fit: BoxFit.cover),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 3,
              right: 3,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
