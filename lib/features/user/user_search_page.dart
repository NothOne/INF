import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/paged_status_list.dart';

/// 搜他的微博: one account's posts that have the keyword.
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key, required this.uid, required this.name});

  final String uid;
  final String name;

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final _field = TextEditingController();
  PagingController<Status>? _pager;

  @override
  void dispose() {
    _field.dispose();
    _pager?.dispose();
    super.dispose();
  }

  void _search(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    final old = _pager;
    setState(() {
      _pager = PagingController<Status>(
        fetch: (cursor) => WeiboApi.instance.searchUserStatuses(widget.uid, query, cursor),
        id: (status) => status.id,
      )..refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pager = _pager;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        titleSpacing: 0,
        title: TextField(
          controller: _field,
          autofocus: true,
          maxLines: 1,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: '搜 @${widget.name} 的微博', border: InputBorder.none),
          onSubmitted: _search,
        ),
        actions: [
          IconButton(onPressed: () => _search(_field.text), tooltip: '搜索', icon: const Icon(Icons.search_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: pager == null
          ? const EmptyHint(text: '输入关键词，只在 TA 的微博里找', icon: Icons.manage_search_rounded)
          : PagedStatusList(
              key: ObjectKey(pager),
              pager: pager,
              hideBlocked: false,
              emptyText: '没有找到相关微博',
            ),
    );
  }
}
