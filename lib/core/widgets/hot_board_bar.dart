import 'package:flutter/material.dart';

import '../chrome.dart';
import '../haptics.dart';
import '../models.dart';
import '../motion.dart';
import '../prefs.dart';

/// The board shown when [current] is no longer among the user's boards.
HotBoard shownBoard(HotBoard current) {
  final boards = Prefs.instance.hotBoards;
  return boards.contains(current) ? current : boards.first;
}

/// The user's boards as a row of chips: a long press drags one to a new place, the + at the end
/// opens [showHotBoardEditor].
class HotBoardChips extends StatelessWidget {
  const HotBoardChips({super.key, required this.current, required this.onSelect, this.floating = false});

  final HotBoard current;
  final ValueChanged<HotBoard> onSelect;

  /// Inside a floating capsule, where an unselected chip is only its word.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs.instance,
      builder: (context, _) {
        final boards = Prefs.instance.hotBoards;
        return SizedBox(
          height: floating ? 46 : 44,
          child: Row(
            children: [
              Expanded(
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.only(left: floating ? 5 : 12),
                  itemCount: boards.length,
                  proxyDecorator: (child, index, animation) => Material(color: Colors.transparent, child: child),
                  onReorderStart: (_) => Haptic.longPress.play(),
                  onReorderItem: (from, to) {
                    final next = [...boards];
                    next.insert(to, next.removeAt(from));
                    Prefs.instance.setHotBoards(next);
                  },
                  itemBuilder: (context, index) {
                    final board = boards[index];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(board),
                      index: index,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(right: floating ? 2 : 6),
                          child: _BoardChip(
                            label: board.label,
                            selected: board == current,
                            floating: floating,
                            onTap: () => onSelect(board),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                onPressed: () => showHotBoardEditor(context, current: current, onSelect: onSelect),
                icon: const Icon(Icons.add_rounded),
                tooltip: '管理榜单',
                visualDensity: VisualDensity.compact,
              ),
              SizedBox(width: floating ? 4 : 6),
            ],
          ),
        );
      },
    );
  }
}

class _BoardChip extends StatelessWidget {
  const _BoardChip({required this.label, required this.selected, required this.onTap, this.floating = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final idle = floating ? Colors.transparent : chrome.fill(scheme, scheme.surfaceContainerHigh, 0.6);
    return Material(
      color: selected ? chrome.fill(scheme, scheme.primaryContainer, floating ? 0.85 : 1) : idle,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedDefaultTextStyle(
          duration: InfMotion.feedback,
          style: Theme.of(context).textTheme.labelLarge!.copyWith(
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// Which boards show and in what order. A tap on a shown board also switches to it.
Future<void> showHotBoardEditor(BuildContext context, {HotBoard? current, ValueChanged<HotBoard>? onSelect}) {
  return showActionSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _HotBoardEditor(
      current: current,
      onSelect: onSelect == null
          ? null
          : (board) {
              Navigator.pop(sheetContext);
              onSelect(board);
            },
    ),
  );
}

class _HotBoardEditor extends StatelessWidget {
  const _HotBoardEditor({this.current, this.onSelect});

  final HotBoard? current;
  final ValueChanged<HotBoard>? onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: Prefs.instance,
      builder: (context, _) {
        final shown = Prefs.instance.hotBoards;
        final hidden = HotBoard.values.where((board) => !shown.contains(board)).toList();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                    child: Text('热搜榜单', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Text(
                      '按住右侧把手拖动排序；在榜单栏上长按也能拖动',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: shown.length,
                    onReorderStart: (_) => Haptic.longPress.play(),
                    onReorderItem: (from, to) {
                      final next = [...shown];
                      next.insert(to, next.removeAt(from));
                      Prefs.instance.setHotBoards(next);
                    },
                    itemBuilder: (context, index) {
                      final board = shown[index];
                      return ListTile(
                        key: ValueKey(board),
                        contentPadding: const EdgeInsets.only(left: 8, right: 12),
                        leading: IconButton(
                          onPressed: shown.length <= 1
                              ? null
                              : () => Prefs.instance.setHotBoards([...shown]..remove(board)),
                          icon: Icon(Icons.remove_circle_outline_rounded,
                              color: shown.length <= 1 ? null : scheme.error),
                          tooltip: '移除',
                        ),
                        title: Text(
                          board == HotBoard.realtime ? '热搜榜' : '${board.label}榜',
                          style: TextStyle(fontWeight: board == current ? FontWeight.w700 : null),
                        ),
                        selected: board == current,
                        onTap: onSelect == null ? null : () => onSelect!(board),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      );
                    },
                  ),
                  if (hidden.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text('可添加', style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final board in hidden)
                            ActionChip(
                              avatar: const Icon(Icons.add_rounded, size: 16),
                              label: Text(board.label),
                              onPressed: () {
                                Haptic.selection.play();
                                Prefs.instance.setHotBoards([...shown, board]);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
