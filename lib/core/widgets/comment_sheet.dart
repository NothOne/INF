import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/comment_store.dart';
import '../../core/haptics.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/temp_files.dart';
import 'common.dart';
import 'mention_picker.dart';
import 'surface_card_route.dart';

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
Future<bool?> showCommentSheet(
  BuildContext context, {
  required BuildContext anchor,
  required Status status,
  String? commentId,
  String? rootId,
  String? replyToName,
  String? replyToText,
  bool countOnPost = true,
}) {
  return showSurfaceCard<bool>(
    context,
    anchor: anchor,
    builder: (sheetContext) => CommentSheet(
      status: status,
      commentId: commentId,
      rootId: rootId,
      replyToName: replyToName,
      replyToText: replyToText,
      countOnPost: countOnPost,
      onSent: () => Navigator.of(sheetContext).pop(true),
    ),
  );
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
  final EmojiKeyboard _emoji = EmojiKeyboard();
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
    // Nothing was sent, so the copy in the scratch folder is nobody's.
    if (_picture != null) TempFiles.delete(_picture!);
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
    final picture = _picture;
    if (!_canSend || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    // The picture goes up as the comment is sent, not when it is picked: a picture the reader
    // thought better of never reaches the service, and no id is left behind for a comment that was
    // not made. That, and the two ids a reply needs, live in [CommentStore.send].
    final crossPost = _crossPost && widget.commentId == null && picture == null;
    final failure = await CommentStore.instance.send(
      status: widget.status,
      text: _text.text,
      rootId: widget.commentId == null ? null : (widget.rootId ?? widget.commentId),
      replyToId: widget.commentId,
      replyToName: widget.replyToName,
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
    final bar = infSnackBar(context, Text(_isReply ? '回复成功' : (crossPost ? '已评论并转发' : '评论成功')));
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
    setState(() {
      _picture = file.path;
      // Repost endpoint cannot carry a picture, so attaching one turns off 同时转发 immediately.
      _crossPost = false;
    });
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
    if (name != null) _insert('@$name ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quoted = _quotedLine();
    final over = _length > 140;
    final slot = _emoji.boardHeight(context);
    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          top: false,
          bottom: slot == 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No drag handle: this is a panel that grew out of the button that opened it, not a
              // sheet that slides up from the edge, so there is nothing to drag — the handle only
              // suggested a gesture that does not exist. It is dismissed by tapping outside, or by
              // the 收起 button below.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 2),
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
                        onPressed: _canSend ? _send : null,
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
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant,
                              ),
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
                        final selection = _text.selection;
                        final start = selection.isValid ? selection.start : _text.text.length;
                        _insert('##');
                        _text.selection = TextSelection.collapsed(offset: start + 1);
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
                    IconButton(
                      onPressed: _sending ? null : (_picture == null ? _pickPicture : _removePicture),
                      iconSize: 20,
                      tooltip: _picture == null ? '图片' : '取消图片',
                      icon: Icon(_picture == null ? Icons.image_outlined : Icons.image_rounded),
                      color: _picture == null ? null : scheme.primary,
                    ),
                    const SizedBox(width: 2),
                    // 同时转发 is only offered where it can be honoured: the repost endpoint is the
                    // one that takes both, and it takes no picture, so a picture attached to the
                    // comment turns the switch off rather than sending a comment that quietly did
                    // not repost (which is what the ticked box used to do: nothing at all).
                    if (!_isReply && _picture == null)
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
        // The board only takes height when it is open. While the keyboard is up the panel has
        // already been placed above it (see `surface_card_route.dart`), so holding the keyboard's
        // height here as well left a slab of empty panel between the field and the keys.
        if (slot > 0) EmojiKeyboardSlot(visible: _emoji.boardVisible, height: slot, onPick: _insert),
      ],
    );
    // Rounded on every corner: the panel no longer stands on the bottom edge of the screen, it
    // floats, so a square foot would read as a sheet that had not finished arriving.
    return InfChrome.of(context).typingSheet(
      context,
      radius: const BorderRadius.all(Radius.circular(24)),
      child: panel,
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
