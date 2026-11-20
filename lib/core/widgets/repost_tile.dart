import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/parse.dart';
import 'avatar.dart';
import 'rich_text.dart';

/// One repost in the 转发 list: who reposted, when, and what they said.
///
/// It is deliberately not a [StatusCard]: a repost's own pictures and cards are already on the post
/// above, and the list is here to show what people said about it.
class RepostTile extends StatelessWidget {
  const RepostTile({super.key, required this.status});

  final Status status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = status.text.trim().isEmpty ? '转发微博' : status.text;
    return InkWell(
      onTap: () => openStatus(context, statusId: status.id, seed: status),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => openUser(context, status.author.id),
              child: Avatar(url: status.author.avatarUrl, size: 40, verified: status.author.verified),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: () => openUser(context, status.author.id),
                          child: Text(
                            status.author.screenName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        relativeTime(status.createdAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  RichStatusText(
                    text: text,
                    links: status.links,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14.5),
                    onMention: (uid) => openUser(context, uid),
                    onTopic: (name) => openTopic(context, name),
                    onUrl: (url) => openLink(context, url),
                    inlineImages: false,
                    onOpenImages: (images, index, tag) => openImage(
                      context,
                      media: images,
                      index: index,
                      heroTag: tag,
                      moreImages: images.length == 1
                          ? WeiboApi.instance.resolveInlineImages(status.id, images.first.url)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
