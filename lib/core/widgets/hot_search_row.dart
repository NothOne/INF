import 'package:flutter/material.dart';

import '../models.dart';
import '../parse.dart';
import 'smart_image.dart';

const _rankColors = [Color(0xFFFF3852), Color(0xFFFF7A1A), Color(0xFFFFAE1A)];

const _labelColors = {
  '新': Color(0xFFFF3852),
  '热': Color(0xFFFF9406),
  '沸': Color(0xFFF86400),
  '爆': Color(0xFFBD0000),
  '荐': Color(0xFF00B7EE),
  '暖': Color(0xFFFFAB5A),
  '商': Color(0xFF00B7EE),
};

Color rankColor(BuildContext context, int? rank) {
  if (rank == null) return Theme.of(context).colorScheme.primary;
  if (rank >= 1 && rank <= 3) return _rankColors[rank - 1];
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

/// The small coloured 新/热/沸 badge, or the icon m.weibo.cn sends in its place.
class HotLabel extends StatelessWidget {
  const HotLabel({super.key, required this.entry, this.size = 15});

  final HotSearch entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = entry.label?.trim();
    if (label != null && label.isNotEmpty && label.characters.length <= 2) {
      final color = entry.labelColor != null ? Color(entry.labelColor!) : (_labelColors[label] ?? const Color(0xFFFF9406));
      // No alignment: inside a Wrap that would stretch the badge to the full line.
      return Container(
        height: size,
        constraints: BoxConstraints(minWidth: size),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(color: Colors.white, fontSize: size * 0.7, fontWeight: FontWeight.w700, height: 1.1),
          ),
        ),
      );
    }
    final icon = entry.iconUrl;
    if (icon != null && icon.isNotEmpty) {
      return SmartImage(url: icon, width: size * 1.8, height: size, fit: BoxFit.contain);
    }
    return const SizedBox.shrink();
  }
}

/// One line of the hot-search board. [detailed] adds the category and the time on the board.
class HotSearchRow extends StatelessWidget {
  const HotSearchRow({super.key, required this.entry, required this.onTap, this.detailed = false});

  final HotSearch entry;
  final VoidCallback onTap;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rank = entry.pinned ? null : entry.rank;
    final meta = <String>[
      if (entry.category != null && entry.category!.isNotEmpty) entry.category!,
      if (entry.onboardAt != null) '${relativeTime(entry.onboardAt!)}上榜',
    ];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: detailed ? 11 : 10),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: rank == null
                  ? Icon(Icons.vertical_align_top_rounded, size: 18, color: scheme.primary)
                  : Text(
                      '$rank',
                      style: text.bodyLarge?.copyWith(
                        color: rankColor(context, rank),
                        fontWeight: rank <= 3 ? FontWeight.w800 : FontWeight.w500,
                        fontStyle: rank <= 3 ? FontStyle.italic : FontStyle.normal,
                        fontSize: rank <= 3 ? 17 : 15,
                      ),
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.word,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(fontSize: 15.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      HotLabel(entry: entry),
                    ],
                  ),
                  if (detailed && meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta.join(' · '),
                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.heat != null && entry.heat!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                entry.heat!,
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
