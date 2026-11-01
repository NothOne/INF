import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/widgets/common.dart';

Future<List<RecommendChannel>>? _channels;

/// The list changes rarely, so one fetch serves the app's run; a failed one is tried again.
Future<List<RecommendChannel>> _loadChannels({bool retry = false}) {
  if (retry) _channels = null;
  return _channels ??= WeiboApi.instance.recommendChannels()
    ..catchError((Object _) {
      _channels = null;
      return const <RecommendChannel>[];
    });
}

/// weibo.com's 推荐 channels to pick the 推荐 page's stream from.
Future<void> showRecommendChannels(
  BuildContext context, {
  required RecommendChannel current,
  required ValueChanged<RecommendChannel> onSelect,
}) {
  return showActionSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _ChannelSheet(
      current: current,
      onSelect: (channel) {
        Navigator.pop(sheetContext);
        onSelect(channel);
      },
    ),
  );
}

class _ChannelSheet extends StatefulWidget {
  const _ChannelSheet({required this.current, required this.onSelect});

  final RecommendChannel current;
  final ValueChanged<RecommendChannel> onSelect;

  @override
  State<_ChannelSheet> createState() => _ChannelSheetState();
}

class _ChannelSheetState extends State<_ChannelSheet> {
  late Future<List<RecommendChannel>> _future = _loadChannels();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: FutureBuilder<List<RecommendChannel>>(
          future: _future,
          builder: (context, snapshot) {
            final channels = snapshot.data;
            final Widget body;
            if (snapshot.connectionState != ConnectionState.done) {
              body = const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()));
            } else if (snapshot.hasError || channels == null || channels.isEmpty) {
              body = Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: ErrorRetry(
                    message: '频道加载失败',
                    onRetry: () => setState(() => _future = _loadChannels(retry: true)),
                  ),
                ),
              );
            } else {
              Widget section(String title, Iterable<RecommendChannel> items) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Text(title, style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final channel in items)
                              ChoiceChip(
                                label: Text(channel.title),
                                selected: channel.key == widget.current.key,
                                showCheckmark: false,
                                onSelected: (_) => widget.onSelect(channel),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
              final featured = channels.where((channel) => channel.featured);
              final more = channels.where((channel) => !channel.featured);
              body = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (featured.isNotEmpty) section('常用频道', featured),
                  if (more.isNotEmpty) section('更多频道', more),
                  const SizedBox(height: 16),
                ],
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text('推荐频道', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  body,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
