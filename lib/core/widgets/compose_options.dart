import 'package:flutter/material.dart';

import '../haptics.dart';
import '../models.dart';
import '../motion.dart';

/// The icon a visibility option is drawn with — in the picker and on the composer's pill, so the
/// same 仅自己可见 reads the same in both places.
IconData visibilityIcon(PostVisibility visibility) => switch (visibility) {
      PostVisibility.public => Icons.public_rounded,
      PostVisibility.fans => Icons.people_outline_rounded,
      PostVisibility.friends => Icons.group_outlined,
      PostVisibility.self => Icons.lock_outline_rounded,
    };

IconData _statementIcon(ContentStatement statement) => switch (statement) {
      ContentStatement.none => Icons.block_outlined,
      ContentStatement.original => Icons.edit_outlined,
      ContentStatement.repost => Icons.repeat_rounded,
      ContentStatement.ai => Icons.auto_awesome_outlined,
      ContentStatement.fiction => Icons.theater_comedy_outlined,
    };

/// Picks who may see the post. Weibo calls this `visible`; the sheet is solid in every style
/// because the reader is choosing a value that changes what the post is.
Future<PostVisibility?> showVisibilityPicker(BuildContext context, PostVisibility current) =>
    showActionSheet<PostVisibility>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      frosted: false,
      builder: (context) => _OptionSheet<PostVisibility>(
        title: '谁可以看',
        values: PostVisibility.values,
        current: current,
        iconOf: visibilityIcon,
        labelOf: (visibility) => visibility.label,
        detailOf: (visibility) => visibility.description,
      ),
    );

/// Picks the content declaration (`mblog_statement`) an original post carries.
Future<ContentStatement?> showContentStatementPicker(BuildContext context, ContentStatement current) =>
    showActionSheet<ContentStatement>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      frosted: false,
      builder: (context) => _OptionSheet<ContentStatement>(
        title: '内容声明',
        values: ContentStatement.values,
        current: current,
        iconOf: _statementIcon,
        labelOf: (statement) => statement.label,
        detailOf: (statement) => statement == ContentStatement.none ? '不声明' : null,
      ),
    );

/// One choice of either picker. Both lists are the same shape, so they are drawn by the same
/// widget; [detailOf] is null for the declarations that need no second line.
class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.values,
    required this.current,
    required this.iconOf,
    required this.labelOf,
    this.detailOf,
  });

  final String title;
  final List<T> values;
  final T current;
  final IconData Function(T value) iconOf;
  final String Function(T value) labelOf;
  final String? Function(T value)? detailOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final value in values)
            ListTile(
              selected: value == current,
              leading: Icon(iconOf(value), size: 22),
              title: Text(labelOf(value)),
              subtitle: detailOf?.call(value) == null ? null : Text(detailOf!(value)!),
              trailing: value == current ? Icon(Icons.check_rounded, color: scheme.primary) : null,
              onTap: () {
                Haptic.selection.play();
                Navigator.pop(context, value);
              },
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// A compact option on the composer's strip above the toolbar: the current visibility, a content
/// declaration, 同时评论. Inactive pills are a quiet grey; one that differs from the default is
/// tinted, so an unusual choice is visible without opening the picker again.
class ComposeOptionPill extends StatelessWidget {
  const ComposeOptionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(50),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: active ? scheme.primary : foreground),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
