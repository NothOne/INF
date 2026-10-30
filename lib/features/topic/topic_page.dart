import 'package:flutter/material.dart';

import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
import '../../core/widgets/paged_status_list.dart';

class TopicPage extends StatefulWidget {
  const TopicPage({
    super.key,
    required this.name,
    this.query,
    this.containerId,
    this.likedUid,
    this.title,
    this.emptyText,
  });

  final String name;
  final String? query;
  final String? containerId;
  final String? likedUid;
  final String? title;
  final String? emptyText;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class _TopicPageState extends State<TopicPage> {
  late final PagingController<Status> _pager = PagingController<Status>(
    fetch: _fetch,
    id: (status) => status.id,
  );

  @override
  void initState() {
    super.initState();
    _pager.refresh();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<PageResult<Status>> _fetch(String? cursor) {
    final liked = widget.likedUid;
    if (liked != null && liked.isNotEmpty) {
      return WeiboApi.instance.feed(FeedSource.liked, liked, cursor);
    }
    final container = widget.containerId;
    if (container != null && container.isNotEmpty) {
      return WeiboApi.instance.feed(
        FeedSource(FeedKind.card, widget.title ?? widget.name, container),
        '',
        cursor,
      );
    }
    return WeiboApi.instance.topicStatuses(widget.name, widget.query, cursor);
  }

  String get _title {
    if (widget.title != null && widget.title!.isNotEmpty) return widget.title!;
    if (widget.likedUid != null) return '赞过';
    return '#${widget.name}#';
  }

  Future<void> _search() async {
    final controller = TextEditingController();
    final keyword = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('搜索「${widget.name}」'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 1,
              decoration: const InputDecoration(hintText: '输入关键词'),
              onSubmitted: (value) => Navigator.pop(context, value.trim()),
            ),
            const SizedBox(height: 8),
            Text(
              '超话内搜索暂不可用：将按「超话名 + 关键词」在微博全站搜索。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (keyword != null && keyword.isNotEmpty && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => TopicPage(name: widget.name, query: keyword),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.containerId != null)
            IconButton(onPressed: _search, tooltip: '搜索', icon: const Icon(Icons.search_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: PagedStatusList(
        pager: _pager,
        emptyText: widget.emptyText ?? (widget.likedUid != null ? '还没有赞过微博' : '这个话题还没有微博'),
      ),
    );
  }
}
