import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/error_text.dart';
import '../../core/layout.dart';
import '../../core/link_preview.dart';
import '../../core/look.dart';
import '../../core/message_sender.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import 'chat_link_sheet.dart';
import '../../core/parse.dart';
import '../../core/session.dart';
import '../../core/temp_files.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/mention_picker.dart';
import '../../core/widgets/rich_text.dart';
import '../../core/widgets/smart_image.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.uid, this.name, this.avatar, this.group = false});

  final String uid;
  final String? name;

  /// The avatar the page was opened from, already decoded, for the other person's messages.
  final String? avatar;
  final bool group;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// The last messages seen per conversation, so reopening one paints them at once.
  /// Keyed with the signed-in account, capped by LRU, and cleared on sign-out/account switch.
  static final _recent = <String, ({List<DirectMessage> messages, String? cursor, bool hasMore})>{};
  static const _recentKept = 20;
  static bool _resetRegistered = false;

  static void _ensureResetHook() {
    if (_resetRegistered) return;
    _resetRegistered = true;
    Session.instance.registerAccountReset(_recent.clear);
  }

  final ScrollController _scroll = ScrollController();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();

  List<DirectMessage> _messages = [];
  String? _cursor;
  Object? _error;
  User? _peer;
  String? _selfId;

  /// The group's title as its message pages spell it, `群名(人数)`: where m.weibo.cn keeps the name
  /// and the member count. Null until a page has come back.
  String? _groupTitle;

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
    final recent = _recent[_key];
    if (recent != null) {
      _messages = recent.messages;
      _cursor = recent.cursor;
      _hasMore = recent.hasMore;
      _loading = false;
      _loadLatest(quiet: true);
    } else {
      _loadLatest(initial: true);
    }
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

  String get _key => '${Session.instance.cacheScope ?? ''}:${widget.group ? 'g' : 'u'}${widget.uid}';

  void _remember() {
    _ensureResetHook();
    final key = _key;
    _recent.remove(key);
    _recent[key] = (messages: _messages, cursor: _cursor, hasMore: _hasMore);
    if (_recent.length > _recentKept) _recent.remove(_recent.keys.first);
  }

  void _changed() => setState(() {});

  void _onEmoji() {
    if (mounted) setState(() {});
  }

  void _onFocus() => _emoji.onFocusChanged(_focus.hasFocus);

  /// The list is reversed: offset 0 is the newest message.
  bool get _atBottom => !_scroll.hasClients || _scroll.position.pixels <= 80;

  Future<void> _loadPeer() async {
    try {
      final user = await WeiboApi.instance.user(widget.uid);
      if (mounted) setState(() => _peer = user);
    } catch (_) {}
  }

  Future<void> _loadLatest({bool initial = false, bool quiet = false, bool scroll = true}) async {
    if (!quiet && mounted) setState(() => _loading = initial);
    try {
      if (widget.group) {
        final page = await WeiboApi.instance.groupChatPage(widget.uid, null);
        if (!mounted) return;
        setState(() {
          _messages = page.messages.items.reversed.toList();
          _cursor = page.messages.nextCursor;
          _hasMore = page.messages.nextCursor != null;
          _groupTitle = page.title ?? _groupTitle;
          _loading = false;
          _error = null;
        });
      } else {
        final page = await WeiboApi.instance.chat(widget.uid, null);
        if (!mounted) return;
        setState(() {
          _messages = page.items.reversed.toList();
          _cursor = page.nextCursor;
          _hasMore = page.nextCursor != null;
          _loading = false;
          _error = null;
        });
      }
      _remember();
      if (scroll && !initial) _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      if (quiet) return;
      setState(() {
        _loading = false;
        if (_messages.isEmpty) _error = error;
      });
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _cursor == null) return;
    setState(() => _loadingOlder = true);
    try {
      if (widget.group) {
        final page = await WeiboApi.instance.groupChatPage(widget.uid, _cursor);
        if (!mounted) return;
        final older = page.messages.items.reversed.toList();
        setState(() {
          _messages = [...older, ..._messages];
          _cursor = page.messages.nextCursor;
          _hasMore = page.messages.nextCursor != null && older.isNotEmpty;
          _groupTitle = page.title ?? _groupTitle;
        });
      } else {
        final page = await WeiboApi.instance.chat(widget.uid, _cursor);
        if (!mounted) return;
        final older = page.items.reversed.toList();
        setState(() {
          _messages = [...older, ..._messages];
          _cursor = page.nextCursor;
          _hasMore = page.nextCursor != null && older.isNotEmpty;
        });
      }
      _remember();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// One more page of history for the search page, which pages through the same cursor the list does.
  Future<List<DirectMessage>> _loadOlderForSearch() async {
    if (_loadingOlder || !_hasMore || _cursor == null) return const [];
    final before = _messages.length;
    await _loadOlder();
    return _messages.length > before ? _messages.take(_messages.length - before).toList() : const [];
  }

  Future<void> _openSearch() async {
    await openChatSearch(
      context,
      messages: List.of(_messages),
      onLoadOlder: _loadOlderForSearch,
      selfId: _selfId,
    );
    // The search page may have pulled more history in, so the list is put back on the newest message
    // it already had rather than on the messages the search brought in.
    if (mounted) _remember();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    });
  }

  Future<void> _send() async {
    final content = _text.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    _text.clear();
    final failure = await MessageSender.text(ChatTarget(widget.uid, widget.group), content);
    if (failure == null) await _loadLatest(quiet: true);
    if (!mounted) return;
    setState(() => _sending = false);
    showMessage(context, failure);
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    setState(() => _sending = true);
    final file = await TempFiles.file('chat-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(picked.path).copy(file.path);
    // The sender deletes this copy once the upload has taken it, whatever the outcome.
    final failure = await MessageSender.image(ChatTarget(widget.uid, widget.group), file);
    if (failure == null) await _loadLatest(quiet: true);
    if (!mounted) return;
    setState(() => _sending = false);
    showMessage(context, failure);
  }

  Future<void> _openGroupInfo() async {
    final left = await openGroupInfo(
      context,
      gid: widget.uid,
      name: _title,
      memberCount: _memberCount,
    );
    if (left == true && mounted) Navigator.of(context).pop();
  }

  /// The count the group's message title carries, for the header before the real answer arrives.
  int get _memberCount => _groupTitle == null ? 0 : splitGroupTitle(_groupTitle!).count;

  /// The group's name with its member count stripped off, for the top bar.
  String get _title {
    if (widget.group) {
      final title = _groupTitle;
      final name = title == null ? null : splitGroupTitle(title).name;
      return name?.isNotEmpty == true ? name! : (widget.name ?? '群聊');
    }
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
          IconButton(
            onPressed: _openSearch,
            tooltip: '查找聊天记录',
            icon: const Icon(Icons.search_rounded),
          ),
          if (!widget.group)
            IconButton(
              onPressed: () => openUser(context, widget.uid),
              tooltip: '查看主页',
              icon: const Icon(Icons.person_outline_rounded),
            )
          else
            // The ⋯ opens the group's own page, where its members, announcement and switch live.
            IconButton(
              onPressed: _openGroupInfo,
              tooltip: '群聊信息',
              icon: const Icon(Icons.more_horiz_rounded),
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
            emojiVisible: _emoji.boardVisible,
            inset: _emoji.insetFor(context),
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
    final state = _loading && _messages.isEmpty
        ? 'loading'
        : _messages.isEmpty
            ? (_error != null ? 'error' : 'empty')
            : 'list';
    // The first messages fade in over the spinner instead of replacing it in one frame.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey(state), child: _messagesBody(context)),
    );
  }

  Widget _messagesBody(BuildContext context) {
    if (_loading && _messages.isEmpty) return const LoadingFooter();
    if (_error != null && _messages.isEmpty) {
      return Center(child: ErrorView(error: _error, onRetry: () => _loadLatest(initial: true)));
    }
    if (_messages.isEmpty) {
      return const EmptyHint(text: '还没有消息', icon: Icons.chat_bubble_outline_rounded);
    }
    final scheme = Theme.of(context).colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels > notification.metrics.maxScrollExtent - 120) _loadOlder();
        return false;
      },
      // Reversed, it opens at the newest message on its first frame instead of jumping there.
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: EdgeInsets.fromLTRB(
          contentGutter(context),
          8 + MediaQuery.paddingOf(context).top,
          contentGutter(context),
          16,
        ),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final at = _messages.length - 1 - index;
          final message = _messages[at];
          final previous = at > 0 ? _messages[at - 1] : null;
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
                avatar: widget.group ? null : widget.avatar,
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
    required this.avatar,
    required this.showSenderName,
    required this.onOpenUser,
    required this.onOpenTopic,
    required this.onOpenUrl,
  });

  final DirectMessage message;
  final bool mine;
  final User? peer;
  final String? avatar;
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
                url: avatar ?? message.senderAvatar ?? peer?.avatarUrl,
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
                    linkColor: mine ? scheme.onPrimaryContainer : null,
                    onMention: onOpenUser,
                    onTopic: onOpenTopic,
                    onUrl: onOpenUrl,
                  ),
                ),
                for (final url in _linksIn(message.displayText).take(2))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _LinkPreviewCard(url: url, onTap: () => onOpenUrl(url)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _linkPattern = RegExp(r'https?://[^\s<>"，。！？、）)\]】]+', caseSensitive: false);

/// The addresses in a message worth a preview; pictures already show as pictures.
Iterable<String> _linksIn(String text) => _linkPattern
    .allMatches(text)
    .map((match) => match.group(0)!)
    .where((url) => !(Uri.tryParse(url)?.host.endsWith('sinaimg.cn') ?? true))
    .toSet();

/// What a link in a message points at, under the bubble: a post's author and text, or a page's
/// title, description and site.
class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return FutureBuilder<LinkPreview?>(
      future: LinkPreviews.instance.of(url),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        final title = preview?.title ?? (loading ? '正在读取链接…' : null);
        final site = preview?.site ?? Uri.tryParse(url)?.host ?? '';
        final picture = preview?.imageUrl;
        return Container(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Material(
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null)
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: loading ? scheme.onSurfaceVariant : scheme.onSurface,
                              ),
                            ),
                          if (preview?.description != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              preview!.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.link_rounded, size: 14, color: scheme.primary),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  site,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.labelSmall?.copyWith(color: scheme.primary),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (picture != null) ...[
                      const SizedBox(width: 10),
                      SmartImage(url: picture, width: 56, height: 56, radius: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focus,
    required this.sending,
    required this.emojiOpen,
    required this.emojiVisible,
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
  final bool emojiVisible;
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
        EmojiKeyboardSlot(visible: emojiVisible, height: inset, onPick: onPickEmoji),
      ],
    );
    return InfChrome.of(context).edgePanel(context, child: ContentColumn(child: column));
  }
}