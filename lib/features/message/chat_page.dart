import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import 'chat_link_sheet.dart';
import '../../core/parse.dart';
import '../../core/session.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/mention_picker.dart';
import '../../core/widgets/rich_text.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.uid, this.name, this.group = false});

  final String uid;
  final String? name;
  final bool group;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();

  List<DirectMessage> _messages = [];
  String? _cursor;
  String? _error;
  User? _peer;
  String? _selfId;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  bool _sending = false;
  final EmojiKeyboard _emoji = EmojiKeyboard();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _selfId = Session.instance.uid;
    _text.addListener(_changed);
    _emoji.addListener(_onEmoji);
    _focus.addListener(_onFocus);
    _loadLatest(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_scroll.hasClients && _atBottom && !_loading) _loadLatest(quiet: true, scroll: false);
    });
    if (!widget.group && (widget.name == null || widget.name!.isEmpty)) _loadPeer();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.removeListener(_changed);
    _emoji.removeListener(_onEmoji);
    _focus.removeListener(_onFocus);
    _emoji.dispose();
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _onEmoji() {
    if (mounted) setState(() {});
  }

  void _onFocus() => _emoji.onFocusChanged(_focus.hasFocus);

  bool get _atBottom => !_scroll.hasClients
      ? true
      : _scroll.position.pixels >= _scroll.position.maxScrollExtent - 80;

  Future<void> _loadPeer() async {
    try {
      final user = await WeiboApi.instance.user(widget.uid);
      if (mounted) setState(() => _peer = user);
    } catch (_) {}
  }

  Future<void> _loadLatest({bool initial = false, bool quiet = false, bool scroll = true}) async {
    if (!quiet && mounted) setState(() => _loading = initial);
    try {
      final page = widget.group
          ? await WeiboApi.instance.groupChat(widget.uid, null)
          : await WeiboApi.instance.chat(widget.uid, null);
      if (!mounted) return;
      setState(() {
        _messages = page.items.reversed.toList();
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
        _loading = false;
        _error = null;
      });
      if (scroll) _scrollToBottom(animated: !initial);
    } catch (error) {
      if (!mounted) return;
      if (quiet) return;
      setState(() {
        _loading = false;
        if (_messages.isEmpty) _error = error is ApiException ? error.message : '加载失败';
      });
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _cursor == null) return;
    setState(() => _loadingOlder = true);
    final previousMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    try {
      final page = widget.group
          ? await WeiboApi.instance.groupChat(widget.uid, _cursor)
          : await WeiboApi.instance.chat(widget.uid, _cursor);
      if (!mounted) return;
      final older = page.items.reversed.toList();
      setState(() {
        _messages = [...older, ..._messages];
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null && older.isNotEmpty;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final next = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(_scroll.position.pixels + (next - previousMax));
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  Future<void> _send() async {
    final content = _text.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    _text.clear();
    try {
      if (widget.group) {
        await WeiboApi.instance.sendGroupMessage(widget.uid, content);
      } else {
        await WeiboApi.instance.sendMessage(widget.uid, content);
      }
      await _loadLatest(quiet: true);
      Haptic.success.play();
    } catch (error) {
      Haptic.error.play();
      if (mounted) showMessage(context, error is ApiException ? error.message : '发送失败');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    setState(() => _sending = true);
    try {
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/chat-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(picked.path).copy(file.path);
      final target = ChatTarget(widget.uid, widget.group);
      final fids = await WeiboApi.instance.uploadChatImage(file, target);
      await WeiboApi.instance.sendChatImage(target, fids);
      await _loadLatest(quiet: true);
      Haptic.success.play();
    } catch (error) {
      Haptic.error.play();
      if (mounted) showMessage(context, error is ApiException ? error.message : '图片发送失败');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('退出后不再接收这个群的消息，确定退出？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await WeiboApi.instance.leaveGroup(widget.uid);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showMessage(context, error is ApiException ? error.message : '退出失败');
    }
  }

  String get _title {
    if (widget.group) return widget.name ?? '群聊';
    return _peer?.screenName ?? widget.name ?? '私信';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!widget.group)
            IconButton(
              onPressed: () => openUser(context, widget.uid),
              tooltip: '查看主页',
              icon: const Icon(Icons.person_outline_rounded),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'leave') _leaveGroup();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'leave', child: Text('退出群聊')),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: Builder(builder: _buildMessages)),
          _InputBar(
            controller: _text,
            focus: _focus,
            sending: _sending,
            emojiOpen: _emoji.open,
            inset: _emoji.heightFor(context),
            onEmoji: () => _emoji.toggle(context, _focus),
            onPickImage: _sendImage,
            onSend: _send,
            onPickEmoji: (code) {
              _text.text += code;
              _text.selection = TextSelection.collapsed(offset: _text.text.length);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(BuildContext context) {
    if (_loading && _messages.isEmpty) return const LoadingFooter();
    if (_error != null && _messages.isEmpty) {
      return Center(child: ErrorRetry(message: _error, onRetry: () => _loadLatest(initial: true)));
    }
    if (_messages.isEmpty) {
      return const EmptyHint(text: '还没有消息', icon: Icons.chat_bubble_outline_rounded);
    }
    final scheme = Theme.of(context).colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels < 120) _loadOlder();
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          contentGutter(context),
          8 + MediaQuery.paddingOf(context).top,
          contentGutter(context),
          16,
        ),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          final previous = index > 0 ? _messages[index - 1] : null;
          final showTime = previous == null ||
              message.createdAt.difference(previous.createdAt) > const Duration(minutes: 5);
          return Column(
            children: [
              if (showTime)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Text(
                    relativeTime(message.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              _Bubble(
                message: message,
                mine: message.senderId == _selfId,
                peer: _peer,
                showSenderName: widget.group,
                onOpenUser: (uid) => openUser(context, uid),
                onOpenTopic: (name) => openTopic(context, name),
                onOpenUrl: (url) => openChatLink(context, url),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.peer,
    required this.showSenderName,
    required this.onOpenUser,
    required this.onOpenTopic,
    required this.onOpenUrl,
  });

  final DirectMessage message;
  final bool mine;
  final User? peer;
  final bool showSenderName;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<String> onOpenTopic;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            GestureDetector(
              onTap: () => onOpenUser(message.senderId),
              child: Avatar(
                url: message.senderAvatar ?? peer?.avatarUrl,
                size: 36,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!mine && showSenderName && (message.senderName?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.senderName!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 290),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(mine ? 14 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 14),
                    ),
                  ),
                  child: RichStatusText(
                    text: message.displayText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: mine ? scheme.onPrimaryContainer : scheme.onSurface,
                        ),
                    onMention: onOpenUser,
                    onTopic: onOpenTopic,
                    onUrl: onOpenUrl,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focus,
    required this.sending,
    required this.emojiOpen,
    required this.inset,
    required this.onEmoji,
    required this.onPickImage,
    required this.onSend,
    required this.onPickEmoji,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool sending;
  final bool emojiOpen;
  final double inset;
  final VoidCallback onEmoji;
  final VoidCallback onPickImage;
  final VoidCallback onSend;
  final ValueChanged<String> onPickEmoji;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          top: false,
          bottom: inset == 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 5, 8, 5),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: onEmoji,
                    iconSize: 21,
                    icon: Icon(emojiOpen ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined),
                  ),
                  IconButton(
                    onPressed: sending ? null : onPickImage,
                    iconSize: 21,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '发私信',
                        contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  if (sending)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    IconButton.filled(
                      onPressed: controller.text.trim().isEmpty ? null : onSend,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(38, 38),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 19),
                    ),
                ],
              ),
            ),
          ),
        EmojiKeyboardSlot(open: emojiOpen, height: inset, onPick: onPickEmoji),
      ],
    );
    return InfChrome.of(context).edgePanel(context, child: ContentColumn(child: column));
  }
}