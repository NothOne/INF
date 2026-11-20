import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassButton, GlassQuality, GlassSegment, GlassSegmentedControl, LiquidOval, LiquidRoundedSuperellipse;

import '../../core/layout.dart';
import '../../core/liquid_glass.dart' show GlassMerge, glassIsPremium, glassQualityOf;
import '../../core/look.dart';
import '../../core/motion.dart';
import '../../core/parse.dart';

/// 转发 / 评论 on the detail page: two tabs with their counts, the style's own material.
///
/// It is here rather than in the page because it is two controls in one — a glass segmented control
/// and an underline pair — and the page should not be the place that decides which.
class DiscussionSwitch extends StatelessWidget {
  const DiscussionSwitch({
    super.key,
    required this.reposts,
    required this.comments,
    required this.showingReposts,
    required this.onShowReposts,
    required this.onShowComments,
  });

  final int reposts;
  final int comments;
  final bool showingReposts;
  final VoidCallback onShowReposts;
  final VoidCallback onShowComments;

  @override
  Widget build(BuildContext context) {
    if (InfLook.of(context).liquid) {
      final scheme = Theme.of(context).colorScheme;
      final label = Theme.of(context).textTheme.titleSmall ?? const TextStyle();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: GlassSegmentedControl(
          useOwnLayer: true,
          quality: glassQualityOf(InfLook.of(context)),
          height: 38,
          segments: [
            GlassSegment(label: _caption('转发', reposts)),
            GlassSegment(label: _caption('评论', comments)),
          ],
          selectedIndex: showingReposts ? 0 : 1,
          onSegmentSelected: (index) => index == 0 ? onShowReposts() : onShowComments(),
          selectedTextStyle: label.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
          unselectedTextStyle: label.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Row(
        children: [
          _tab(context, '转发', reposts, showingReposts, onShowReposts),
          _tab(context, '评论', comments, !showingReposts, onShowComments),
        ],
      ),
    );
  }

  static String _caption(String label, int count) => count > 0 ? '$label ${compactCount(count)}' : label;

  Widget _tab(BuildContext context, String label, int count, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final caption = _caption(label, count);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Column(
            children: [
              AnimatedDefaultTextStyle(
                duration: InfMotion.feedback,
                style: (Theme.of(context).textTheme.titleSmall ?? const TextStyle()).copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(caption),
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: InfMotion.feedback,
                curve: Curves.easeOutCubic,
                height: 2.5,
                width: selected ? 26 : 0,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按热度 / 按时间, under the two tabs and only while the comments are the list on screen.
class CommentSortBar extends StatelessWidget {
  const CommentSortBar({super.key, required this.byTime, required this.onSort});

  final bool byTime;
  final ValueChanged<bool> onSort;

  int get _index => byTime ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    // One segment per label, and the whole capsule scales with the reader's text size.
    final segment = MediaQuery.textScalerOf(context).scale(62);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: InfLook.of(context).liquid
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  // Narrow windows or a large text size clamp the capsule rather than spill it.
                  child: SizedBox(width: segment * 2, child: _segmented(context)),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _chip(context, '按热度', false),
                const SizedBox(width: 4),
                _chip(context, '按时间', true),
              ],
            ),
    );
  }

  Widget _segmented(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelSmall ?? const TextStyle();
    return GlassSegmentedControl(
      useOwnLayer: true,
      quality: glassQualityOf(InfLook.of(context)),
      height: 30,
      segments: const [GlassSegment(label: '按热度'), GlassSegment(label: '按时间')],
      selectedIndex: _index,
      onSegmentSelected: (index) => onSort(index == 1),
      selectedTextStyle: label.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
      unselectedTextStyle: label.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
    );
  }

  Widget _chip(BuildContext context, String label, bool value) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final selected = byTime == value;
    return Material(
      color: selected
          ? chrome.fill(scheme, scheme.primaryContainer, 0.85)
          : chrome.fill(scheme, scheme.surfaceContainerHigh, 0.6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSort(value),
        child: AnimatedDefaultTextStyle(
          duration: InfMotion.feedback,
          style: (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// The bar at the foot of the detail page: 写评论, 转发 and 赞.
///
/// The three glass parts are one surface on the ultra tier and three separate panes below it; that
/// is the only thing that changes between them, so the layout is written once.
class DetailBottomBar extends StatelessWidget {
  const DetailBottomBar({
    super.key,
    required this.liked,
    required this.enabled,
    required this.onComment,
    required this.onRepost,
    required this.onLike,
  });

  final bool liked;
  final bool enabled;
  final void Function(BuildContext anchor) onComment;
  final VoidCallback onRepost;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    if (InfLook.of(context).liquid) return _liquid(context);
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final bar = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Builder(
                // The field's own context, so the reply panel grows out of the bar rather than the
                // whole page.
                builder: (fieldContext) => InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: enabled ? () => onComment(fieldContext) : null,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: chrome.fill(scheme, scheme.surfaceContainerHigh, 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '写评论…',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: enabled ? onRepost : null,
              tooltip: '转发',
              icon: const Icon(Icons.repeat_rounded),
            ),
            _PopLikeButton(liked: liked, enabled: enabled, onLike: onLike),
          ],
        ),
      ),
    );
    return chrome.edgePanel(context, child: ContentColumn(child: bar));
  }

  /// No panel along the edge: a glass capsule and two glass discs float over the comments, which
  /// scroll on beneath them. On ultra they are one surface — press any of them and its neighbour
  /// grows a neck toward it — and on standard they are three separate panes.
  Widget _liquid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final merged = glassIsPremium(context);
    final quality = merged ? GlassQuality.premium : GlassQuality.standard;
    final row = Row(
      children: [
        Expanded(
          child: Builder(
            builder: (fieldContext) => GlassButton.custom(
              useOwnLayer: !merged,
              quality: quality,
              height: 46,
              shape: const LiquidRoundedSuperellipse(borderRadius: 23),
              enabled: enabled,
              onTap: () => onComment(fieldContext),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      '写评论…',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: '转发',
          child: _glassRound(
            enabled: enabled,
            onTap: onRepost,
            child: Icon(Icons.repeat_rounded, color: scheme.onSurfaceVariant),
            quality: quality,
            ownLayer: !merged,
          ),
        ),
        const SizedBox(width: 10),
        _PopLikeButton(liked: liked, enabled: enabled, onLike: onLike, merged: merged),
      ],
    );
    final bar = SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: merged ? GlassMerge(child: row) : row,
      ),
    );
    return ContentColumn(child: bar);
  }
}

Widget _glassRound({
  required bool enabled,
  required VoidCallback onTap,
  required Widget child,
  required GlassQuality quality,
  required bool ownLayer,
}) =>
    GlassButton.custom(
      useOwnLayer: ownLayer,
      quality: quality,
      width: 46,
      height: 46,
      shape: const LiquidOval(),
      enabled: enabled,
      onTap: onTap,
      child: child,
    );

/// The same short pop the card's like button uses, so the two controls feel like one.
class _PopLikeButton extends StatefulWidget {
  const _PopLikeButton({
    required this.liked,
    required this.enabled,
    required this.onLike,
    this.merged = false,
  });

  final bool liked;
  final bool enabled;
  final VoidCallback onLike;

  /// Whether this button's glass is a member of the surrounding [GlassMerge], which owns the layer
  /// it draws into.
  final bool merged;

  @override
  State<_PopLikeButton> createState() => _PopLikeButtonState();
}

class _PopLikeButtonState extends State<_PopLikeButton> {
  bool _popped = false;

  void _tap() {
    setState(() => _popped = true);
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _popped = false);
    });
    widget.onLike();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.liked ? scheme.primary : scheme.onSurfaceVariant;
    final icon = AnimatedScale(
      scale: _popped ? 1.28 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: const Duration(milliseconds: 160),
        builder: (context, value, _) => Icon(
          widget.liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
          color: value,
        ),
      ),
    );
    if (InfLook.of(context).liquid) {
      return Tooltip(
        message: '赞',
        child: _glassRound(
          enabled: widget.enabled,
          onTap: _tap,
          child: icon,
          quality: widget.merged ? GlassQuality.premium : glassQualityOf(InfLook.of(context)),
          ownLayer: !widget.merged,
        ),
      );
    }
    return IconButton(onPressed: widget.enabled ? _tap : null, tooltip: '赞', icon: icon);
  }
}
