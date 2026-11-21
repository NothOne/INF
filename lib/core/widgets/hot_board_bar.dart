import 'package:flutter/material.dart';

import '../api.dart';
import '../chrome.dart';
import '../haptics.dart';
import '../hot_search_store.dart';
import '../models.dart';
import '../motion.dart';
import '../navigation.dart';
import '../prefs.dart';
import 'city_picker_sheet.dart';

/// The board shown when [current] is no longer among the user's boards.
HotBoard shownBoard(HotBoard current) {
  final boards = Prefs.instance.hotBoards;
  return boards.contains(current) ? current : boards.first;
}

/// A board's name as the bar and the editor write it: 我的热搜 / 热搜榜 / 同城榜 / 文娱榜 …
String hotBoardTitle(HotBoard board) => switch (board) {
      HotBoard.mine => '我的热搜',
      HotBoard.realtime => '热搜榜',
      HotBoard.city => '同城榜',
      _ => '${board.label}榜',
    };

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
      animation: Prefs.instance.hotBoardsNotifier,
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

/// 热门榜单's six sub-tabs (小时榜 / 昨日 / 前日 / 周榜 / 男榜 / 女榜), drawn like the boards' chips.
/// They are a fixed set, so this row is a plain scroll rather than a reorderable list.
class HotRankChips extends StatelessWidget {
  const HotRankChips({super.key, required this.current, required this.onSelect, this.floating = false});

  final HotRankTab current;
  final ValueChanged<HotRankTab> onSelect;

  /// Inside a floating capsule, where an unselected chip is only its word.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: floating ? 46 : 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(left: floating ? 5 : 12, right: floating ? 5 : 12),
        children: [
          for (final tab in HotRankTab.defaults)
            Center(
              child: Padding(
                padding: EdgeInsets.only(right: floating ? 2 : 6),
                child: _BoardChip(
                  label: tab.title,
                  selected: tab == current,
                  floating: floating,
                  onTap: () => onSelect(tab),
                ),
              ),
            ),
        ],
      ),
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

/// The city 同城微博 and 同城热搜 are drawn for, with the way to change it: the name in words and a
/// compact 切换城市 button, on one line. It sits above both lists so the reader can tell which place
/// they are reading about and move somewhere else without hunting through a menu — including when
/// the list below is empty because no city has been chosen or the fix failed.
class CityBannerBar extends StatelessWidget {
  const CityBannerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AnimatedBuilder(
      animation: Prefs.instance.cityNotifier,
      builder: (context, _) {
        final city = Prefs.instance.cityChoice;
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Row(
            children: [
              Icon(Icons.location_city_rounded, size: 17, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  city == null ? '未定位城市' : '当前城市：${city.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => CityPrompt.pick(context),
                icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                label: const Text('切换城市'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 同城 with no city to draw — no pick yet and location refused or unavailable: the way to set one,
/// in words that say what it is for. Shared by the home page and the search page.
class CityPrompt extends StatelessWidget {
  const CityPrompt({super.key});

  static Future<void> pick(BuildContext context) async {
    Haptic.selection.play();
    final picked = await showCityPickerSheet(
      context,
      current: Prefs.instance.cityChoice,
      onLocate: () => WeiboApi.instance.locateCity(),
    );
    // The sheet already writes the city a locate found; a pick is written here for the boards to
    // hear. Writing the same city again is a no-op, so a locate that answered 北京 does not reload
    // 同城 a second time.
    if (picked != null) await Prefs.instance.setCityChoice(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_city_rounded, size: 38, color: scheme.onSurfaceVariant.withValues(alpha: 0.45)),
          const SizedBox(height: 10),
          Text(
            '设置城市，发现更多同城热点',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: () => pick(context), child: const Text('选择城市')),
        ],
      ),
    );
  }
}

/// 我的热搜 without a signed-in weibo.com cookie: what the board is and how to get it, instead of the
/// parse error an answer meant for nobody used to raise.
class HotBoardLoginPrompt extends StatelessWidget {
  const HotBoardLoginPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline_rounded, size: 38, color: scheme.onSurfaceVariant.withValues(alpha: 0.45)),
          const SizedBox(height: 10),
          Text(
            HotSearchStore.mineNeedsLogin,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: () => openLogin(context), child: const Text('登录微博')),
        ],
      ),
    );
  }
}

/// Which boards show and in what order. A tap on a shown board also switches to it.
Future<void> showHotBoardEditor(BuildContext context, {HotBoard? current, ValueChanged<HotBoard>? onSelect}) {
  return showActionSheet<void>(
    context: context,
    isScrollControlled: true,
    // Solid in every style: the list is dragged in, and a frosted sheet re-renders what is under it
    // on every frame of the drag.
    frosted: false,
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
      animation: Prefs.instance.hotBoardsNotifier,
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
                          hotBoardTitle(board),
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
