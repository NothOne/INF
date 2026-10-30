import 'package:flutter/material.dart';

import '../../core/look.dart';
import '../../core/navigation.dart';
import '../../core/parse.dart';
import '../../core/prefs.dart';
import '../../core/status_store.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

class ViewedPage extends StatelessWidget {
  const ViewedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Prefs.instance,
      builder: (context, _) {
        final entries = Prefs.instance.viewed;
        return Scaffold(
          backgroundColor: scheme.surface,
          extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
          appBar: AppBar(
            flexibleSpace: lookBarBackground(context),
            title: const Text('浏览记录'),
            actions: [
              if (entries.isNotEmpty)
                TextButton(
                  onPressed: () => StatusStore.instance.clearViewed(),
                  child: const Text('清空'),
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: entries.isEmpty
              ? const EmptyHint(text: '还没有浏览记录', icon: Icons.history_rounded)
              : Builder(
                  builder: (context) => ListView.separated(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top,
                      bottom: 24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => const Divider(indent: 64),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return InkWell(
                        onTap: () => openStatus(context, statusId: entry.statusId),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Avatar(url: entry.avatarUrl, size: 36),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            entry.authorName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14),
                                          ),
                                        ),
                                        Text(
                                          relativeTime(entry.viewedAt),
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      entry.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}
