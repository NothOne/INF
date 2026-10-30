import 'package:flutter/material.dart';

import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/smart_image.dart';

class SuperTopicsPage extends StatefulWidget {
  const SuperTopicsPage({super.key});

  @override
  State<SuperTopicsPage> createState() => _SuperTopicsPageState();
}

class _SuperTopicsPageState extends State<SuperTopicsPage> {
  late final PagingController<SuperTopic> _pager = PagingController<SuperTopic>(
    fetch: (cursor) => WeiboApi.instance.superTopics(cursor),
    id: (topic) => topic.containerId ?? topic.name,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(title: const Text('超话'), flexibleSpace: lookBarBackground(context)),
      body: AnimatedBuilder(
        animation: _pager,
        builder: (context, _) {
          if (_pager.loading && _pager.items.isEmpty) return const LoadingFooter();
          if (_pager.error != null && _pager.items.isEmpty) {
            return Center(child: ErrorRetry(message: _pager.error.toString(), onRetry: _pager.refresh));
          }
          if (_pager.items.isEmpty) return const EmptyHint(text: '还没有超话', icon: Icons.tag_rounded);
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _pager.onScroll(notification);
              return false;
            },
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(12, 12 + MediaQuery.paddingOf(context).top, 12, 24 + MediaQuery.paddingOf(context).bottom),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 156,
              ),
              itemCount: _pager.items.length + (_pager.loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _pager.items.length) return const LoadingFooter();
                final topic = _pager.items[index];
                return _SuperTopicCard(
                  topic: topic,
                  onTap: () {
                    final container = topic.containerId;
                    if (container != null && container.isNotEmpty) {
                      openTopicFeed(context, containerId: container, name: topic.name);
                    } else {
                      openTopic(context, topic.name);
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SuperTopicCard extends StatelessWidget {
  const _SuperTopicCard({required this.topic, required this.onTap});

  final SuperTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SmartImage(
                  url: topic.iconUrl,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  placeholderColor: scheme.surfaceContainerHigh,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                topic.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (topic.followersLabel != null) ...[
                const SizedBox(height: 3),
                Text(
                  topic.followersLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
