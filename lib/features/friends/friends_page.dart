import 'package:flutter/material.dart';

import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets/people_pager_list.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, this.initialTab = FriendsTab.following});

  final FriendsTab initialTab;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: FriendsTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: const Text('我的好友'),
        bottom: TabBar(
          controller: _tabs,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: [
            for (final tab in FriendsTab.values) Tab(height: 46, child: Text(tab.label)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final tab in FriendsTab.values)
            PeoplePagerList(
              key: ValueKey(tab),
              emptyText: '这里还没有人',
              fetch: (cursor) => WeiboApi.instance.relationUsers(
                tab.container,
                int.tryParse(cursor ?? '') ?? 1,
              ),
            ),
        ],
      ),
    );
  }
}
