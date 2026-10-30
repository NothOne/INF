import 'package:flutter/material.dart';

import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/parse.dart';
import '../../core/session.dart';
import '../../core/shell_tabs.dart';
import '../../core/unread_monitor.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with ShellTabAware {
  User? _user = WeiboApi.instance.cachedSelfProfile()?.user;
  bool _loading = false;
  DateTime? _loadedAt;

  @override
  int get shellTab => 3;

  @override
  void initState() {
    super.initState();
    Session.instance.addListener(_sessionChanged);
    if (Session.instance.state == SessionState.loggedIn) _loadUser();
  }

  @override
  void dispose() {
    Session.instance.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  void onTabShown({required bool first}) {
    final last = _loadedAt;
    if (last == null || DateTime.now().difference(last) > const Duration(minutes: 2)) _loadUser();
  }

  void _sessionChanged() {
    final session = Session.instance;
    if (session.state == SessionState.loggedIn) {
      if (_user != null && _user!.id != session.uid) setState(() => _user = null);
      if (_loadedAt == null) _loadUser();
    } else if (session.state == SessionState.loggedOut) {
      setState(() {
        _user = null;
        _loading = false;
        _loadedAt = null;
      });
    }
  }

  Future<void> _loadUser() async {
    final uid = Session.instance.uid;
    if (uid == null || _loading) return;
    setState(() => _loading = true);
    try {
      final user = await WeiboApi.instance.user(uid);
      if (mounted && user != null) {
        setState(() {
          _user = user;
          _loadedAt = DateTime.now();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新登录微博，确定退出吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed == true) {
      await Session.instance.logout();
      await UnreadMonitor.instance.refresh(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Session.instance,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final session = Session.instance;
        // While the session check runs, the account from last time is the best guess.
        final signedIn = session.state == SessionState.loggedIn ||
            (session.state == SessionState.checking && _user != null);
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
          appBar: AppBar(title: const Text('我'), flexibleSpace: lookBarBackground(context)),
          // The padding has to be read below the Scaffold, which adds the bar's height to it.
          body: Builder(
            builder: (context) => ListView(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top,
              bottom: 130 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              AnimatedSize(
                duration: InfMotion.content,
                curve: InfMotion.enter,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: InfMotion.content,
                  child: signedIn || session.state == SessionState.checking
                      ? _Header(
                          key: const ValueKey('header'),
                          user: _user,
                          onRelations: (kind) {
                            final uid = _user?.id ?? session.uid;
                            if (uid != null) openRelations(context, uid: uid, kind: kind);
                          },
                        )
                      : _LoggedOut(key: const ValueKey('login'), onLogin: () => openLogin(context)),
                ),
              ),
              Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              _MenuTile(
                icon: Icons.edit_note_rounded,
                title: '草稿箱',
                onTap: () => openDrafts(context),
              ),
              if (signedIn) ...[
                _MenuTile(
                  icon: Icons.history_rounded,
                  title: '浏览记录',
                  onTap: () => openViewed(context),
                ),
                _MenuTile(
                  icon: Icons.thumb_up_alt_outlined,
                  title: '赞过',
                  onTap: () => openLiked(context, _user?.id ?? session.uid ?? ''),
                ),
                _MenuTile(
                  icon: Icons.people_outline_rounded,
                  title: '我的好友',
                  onTap: () => openFriends(context),
                ),
                _MenuTile(
                  icon: Icons.tag_rounded,
                  title: '超话',
                  onTap: () => openSuperTopics(context),
                ),
              ],
              _MenuTile(
                icon: Icons.settings_outlined,
                title: '设置',
                onTap: () => openSettings(context),
              ),
              if (session.state == SessionState.loggedIn) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                    ),
                    child: const Text('退出登录'),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  'INF 1.2.0 · 个人学习用的微博第三方客户端，通过网页版接口访问你自己的账号，与新浪微博官方无关。',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}

/// Keeps one layout whether or not the user has arrived yet: the name and counts start as
/// placeholder bars of the same size and cross-fade into text, so nothing below them moves.
class _Header extends StatelessWidget {
  const _Header({super.key, required this.user, required this.onRelations});

  final User? user;
  final ValueChanged<RelationKind> onRelations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = user;
    final countStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final Widget name = current == null
        ? const SkeletonPulse(key: ValueKey('name-skeleton'), child: SkeletonBox(width: 130, height: 20))
        : Text(
            current.screenName,
            key: const ValueKey('name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22),
          );
    final Widget counts = current == null
        ? const SkeletonPulse(key: ValueKey('counts-skeleton'), child: SkeletonBox(width: 180, height: 12))
        : Wrap(
            key: const ValueKey('counts'),
            spacing: 15,
            runSpacing: 3,
            children: [
              GestureDetector(
                onTap: () => onRelations(RelationKind.following),
                child: _Count(text: '关注 ${compactCount(current.followingCount)}', style: countStyle),
              ),
              GestureDetector(
                onTap: () => onRelations(RelationKind.followers),
                child: _Count(text: '粉丝 ${compactCount(current.followersCount)}', style: countStyle),
              ),
              _Count(text: '微博 ${compactCount(current.statusesCount)}', style: countStyle),
            ],
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Avatar(url: current?.avatarUrl, size: 66, verified: current?.verified == true),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 30,
                  child: AnimatedSwitcher(
                    duration: InfMotion.content,
                    layoutBuilder: _startAligned,
                    child: name,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 18,
                  child: AnimatedSwitcher(
                    duration: InfMotion.content,
                    layoutBuilder: _startAligned,
                    child: counts,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _startAligned(Widget? current, List<Widget> previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, if (current != null) current],
      );
}

/// A number that rolls over to its new value instead of being replaced in place.
class _Count extends StatelessWidget {
  const _Count({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: InfMotion.content,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: Text(text, key: ValueKey(text), style: style),
    );
  }
}

class _LoggedOut extends StatelessWidget {
  const _LoggedOut({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      child: Column(
        children: [
          Text(
            '登录后，首页会显示你关注的人的微博',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: onLogin, child: const Text('登录微博')),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }
}