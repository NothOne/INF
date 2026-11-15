import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

/// Finding a message in a group chat.
///
/// m.weibo.cn has no search over a group's history, so the search runs over the messages the chat
/// page has already paged in — the ones that would be on screen if the reader scrolled back. The page
/// says what it searched instead of pretending the group was searched, and offers to load more when
/// the answer is not in what it had.
class ChatSearchPage extends StatefulWidget {
  const ChatSearchPage({super.key, required this.messages, this.onLoadOlder, this.selfId});

  /// Oldest first, the order the chat page keeps them in.
  final List<DirectMessage> messages;

  /// Asks the chat page for another page of history; returns the messages it added, if any.
  final Future<List<DirectMessage>> Function()? onLoadOlder;

  final String? selfId;

  @override
  State<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends State<ChatSearchPage> {
  final TextEditingController _query = TextEditingController();
  final List<DirectMessage> _messages = [];
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.messages);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<DirectMessage> get _matches {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    // Newest first: a search is nearly always for something recent.
    return _messages.reversed.where((message) => message.text.toLowerCase().contains(query)).toList();
  }

  Future<void> _loadOlder() async {
    final load = widget.onLoadOlder;
    if (load == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final added = await load();
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = added.isNotEmpty;
        final seen = {for (final message in _messages) message.id};
        _messages.insertAll(0, added.where((message) => seen.add(message.id)));
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final gutter = contentGutter(context);
    final matches = _matches;
    final query = _query.text.trim();
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: chrome.extendsBehindBars,
      appBar: AppBar(flexibleSpace: lookBarBackground(context), title: const Text('查找聊天记录')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              (chrome.extendsBehindBars ? MediaQuery.paddingOf(context).top + kToolbarHeight : 0) + 8,
              gutter,
              8,
            ),
            child: ContentColumn(
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索聊天内容',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: '清除',
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                          },
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          if (query.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(gutter + 4, 0, gutter + 4, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '在已加载的 ${_messages.length} 条消息里找到 ${matches.length} 条',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          Expanded(child: _body(context, query, matches)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, String query, List<DirectMessage> matches) {
    if (query.isEmpty) {
      return const EmptyHint(text: '输入关键词，在已加载的聊天记录里查找');
    }
    if (matches.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EmptyHint(text: '已加载的记录里没有匹配的消息'),
          if (_hasMore && widget.onLoadOlder != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: _loadingMore ? null : _loadOlder,
                child: Text(_loadingMore ? '正在加载…' : '继续往前找'),
              ),
            ),
        ],
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final message = matches[index];
        final mine = message.senderId == widget.selfId;
        final scheme = Theme.of(context).colorScheme;
        return ListTile(
          leading: mine ? null : Avatar(url: message.senderAvatar, size: 36),
          title: Text(
            mine ? '我' : (message.senderName ?? message.senderId),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          subtitle: RichText(
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            text: _highlighted(context, message.displayText, query),
          ),
          trailing: Text(
            '${message.createdAt.month}/${message.createdAt.day}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        );
      },
    );
  }

  /// The message with every occurrence of [query] picked out, so a hit reads as a hit.
  TextSpan _highlighted(BuildContext context, String text, String query) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodyMedium;
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final found = lower.indexOf(needle, start);
      if (found < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (found > start) spans.add(TextSpan(text: text.substring(start, found)));
      spans.add(TextSpan(
        text: text.substring(found, found + needle.length),
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      ));
      start = found + needle.length;
    }
    return TextSpan(style: base, children: spans);
  }
}
