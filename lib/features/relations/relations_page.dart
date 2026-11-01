import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/widgets/people_pager_list.dart';

class RelationsPage extends StatefulWidget {
  const RelationsPage({super.key, required this.uid, this.initialKind = RelationKind.following});

  final String uid;
  final RelationKind initialKind;

  @override
  State<RelationsPage> createState() => _RelationsPageState();
}

class _RelationsPageState extends State<RelationsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialKind == RelationKind.following ? 0 : 1,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final self = Session.instance.uid == widget.uid;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: Text(widget.initialKind == RelationKind.following ? '关注' : '粉丝'),
        bottom: ContentBar(
          child: TabBar(
            controller: _tabs,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(height: 46, child: Text('关注')),
              Tab(height: 46, child: Text('粉丝')),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          PeoplePagerList(
            key: const ValueKey('following'),
            emptyText: '还没有关注的人',
            fetch: (cursor) => WeiboApi.instance.relationUsers(
              relationContainer(RelationKind.following, widget.uid, self: self),
              int.tryParse(cursor ?? '') ?? 1,
            ),
          ),
          PeoplePagerList(
            key: const ValueKey('followers'),
            emptyText: '还没有粉丝',
            fetch: (cursor) => WeiboApi.instance.relationUsers(
              relationContainer(RelationKind.followers, widget.uid, self: self),
              int.tryParse(cursor ?? '') ?? 1,
            ),
          ),
        ],
      ),
    );
  }
}
