import 'package:flutter/material.dart';

import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/parse.dart';
import '../../core/session.dart';
import '../../core/share.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/paged_status_list.dart';
import '../../core/widgets/smart_image.dart';
import '../../core/widgets/transitions.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.uid});

  final String uid;

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  UserProfile? _profile;
  PagingController<Status>? _timeline;
  bool _loading = true;
  bool _followBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timeline?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var uid = widget.uid;
      if (!RegExp(r'^\d+$').hasMatch(uid)) {
        final resolved = await WeiboApi.instance.resolveUid(uid);
        if (resolved == null) throw ApiException('找不到用户 ${widget.uid}');
        uid = resolved;
      }
      final profile = await WeiboApi.instance.userProfile(uid);
      if (profile == null) throw ApiException('找不到用户 ${widget.uid}');
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
      _timeline?.dispose();
      _timeline = PagingController<Status>(
        fetch: (cursor) => WeiboApi.instance.userTimeline(profile.user.id, cursor),
        id: (status) => status.id,
      );
      _timeline!.refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '加载失败';
      });
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || _followBusy || profile.user.id == Session.instance.uid) return;
    if (profile.following) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text('不再关注 ${profile.user.screenName}？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('不再关注')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final next = !profile.following;
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    setState(() {
      _followBusy = true;
      _profile = profile.withFollowing(next);
    });
    try {
      await WeiboApi.instance.setFollowing(profile.user.id, next);
      if (mounted) showMessage(context, next ? '已关注' : '已取消关注');
    } catch (error) {
      if (!mounted) return;
      setState(() => _profile = profile);
      Haptic.error.play();
      showMessage(context, error is ApiException ? error.message : '操作失败');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = _profile;
    final isSelf = profile != null && profile.user.id == Session.instance.uid;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: Text(profile?.user.screenName ?? widget.uid, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (profile != null)
            IconButton(
              onPressed: () => shareText(userShareText(profile.user)),
              tooltip: '分享主页',
              icon: const Icon(Icons.ios_share_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: StateSwitcher(
        child: Builder(
          key: ValueKey(profile != null && _timeline != null ? 'profile' : (_loading ? 'loading' : 'error')),
          builder: (context) {
            final timeline = _timeline;
            if (profile == null && !_loading) {
              return Center(child: ErrorRetry(message: _error, onRetry: _load));
            }
            if (profile == null || timeline == null) return const _ProfileSkeleton();
            return PagedStatusList(
              pager: timeline,
              emptyText: '还没有微博',
              header: _ProfileHeader(
                profile: profile,
                isSelf: isSelf,
                followBusy: _followBusy,
                onToggleFollow: _toggleFollow,
                onMessage: () => openChat(context, uid: profile.user.id, name: profile.user.screenName),
                onRelations: (kind) => openRelations(context, uid: profile.user.id, kind: kind),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The profile header's silhouette (cover, avatar, name, counts), so the real one fades in over
/// something of the same shape instead of replacing a spinner.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 170,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: SkeletonBox(radius: 0)),
                Positioned(
                  left: 16,
                  bottom: -30,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                    child: const SkeletonBox(width: 70, height: 70, radius: 35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 42),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 20),
                SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 12),
                SizedBox(height: 12),
                SkeletonBox(width: 200, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.isSelf,
    required this.followBusy,
    required this.onToggleFollow,
    required this.onMessage,
    required this.onRelations,
  });

  final UserProfile profile;
  final bool isSelf;
  final bool followBusy;
  final VoidCallback onToggleFollow;
  final VoidCallback onMessage;
  final ValueChanged<RelationKind> onRelations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = profile.user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 170,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: profile.coverUrl == null
                    ? Container(color: scheme.surfaceContainerHigh)
                    : SmartImage(url: profile.coverUrl, fit: BoxFit.cover),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, scheme.surface.withValues(alpha: 0.85)],
                      stops: const [0.45, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: -30,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                  child: Avatar(url: user.avatarUrl, size: 70, verified: user.verified),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 10,
                child: Row(
                  children: [
                    if (profile.followsYou && !isSelf)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: InfChrome.of(context).fill(scheme, scheme.surface, 0.82),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('关注了你', style: Theme.of(context).textTheme.labelSmall),
                      ),
                    if (!isSelf) ...[
                      SizedBox(
                        height: 34,
                        child: OutlinedButton(
                          onPressed: onMessage,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            backgroundColor: InfChrome.of(context).fill(scheme, scheme.surface, 0.72),
                          ),
                          child: const Text('私信', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 7),
                      SizedBox(
                        height: 34,
                        child: profile.following
                            ? OutlinedButton(
                                onPressed: followBusy ? null : onToggleFollow,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  backgroundColor: InfChrome.of(context).fill(scheme, scheme.surface, 0.72),
                                ),
                                child: followBusy
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('已关注', style: TextStyle(fontSize: 12)),
                              )
                            : FilledButton(
                                onPressed: followBusy ? null : onToggleFollow,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  minimumSize: const Size(0, 34),
                                ),
                                child: followBusy
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(profile.followsYou ? '回关' : '关注', style: const TextStyle(fontSize: 12)),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 38),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.screenName, style: Theme.of(context).textTheme.titleLarge),
              if (profile.verifiedReason != null && profile.verifiedReason!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  profile.verifiedReason!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.primary),
                ),
              ],
              if (user.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(user.description, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _Count(label: '关注', value: user.followingCount, onTap: () => onRelations(RelationKind.following)),
                  const SizedBox(width: 18),
                  _Count(label: '粉丝', value: user.followersCount, onTap: () => onRelations(RelationKind.followers)),
                  const SizedBox(width: 18),
                  _Count(label: '微博', value: user.statusesCount),
                ],
              ),
            ],
          ),
        ),
        Container(height: 7, color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.5)),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, this.onTap});

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          Text(
            compactCount(value),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
