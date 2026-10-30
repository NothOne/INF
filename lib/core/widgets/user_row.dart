import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/parse.dart';
import 'avatar.dart';

class UserListRow extends StatelessWidget {
  const UserListRow({
    super.key,
    required this.user,
    required this.onTap,
    this.following,
    this.busy = false,
    this.onToggleFollow,
  });

  final User user;
  final VoidCallback onTap;
  final bool? following;
  final bool busy;
  final VoidCallback? onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFollowing = following ?? user.following;
    final subtitle = user.description.isNotEmpty ? user.description : '粉丝 ${compactCount(user.followersCount)}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Avatar(url: user.avatarUrl, size: 44, verified: user.verified),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.screenName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                  ),
                ],
              ),
            ),
            if (onToggleFollow != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: isFollowing
                    ? OutlinedButton(
                        onPressed: busy ? null : onToggleFollow,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: busy
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('已关注', style: TextStyle(fontSize: 12)),
                      )
                    : FilledButton.tonal(
                        onPressed: busy ? null : onToggleFollow,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: busy
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('关注', style: TextStyle(fontSize: 12)),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
