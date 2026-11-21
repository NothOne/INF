import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/api.dart';
import '../../core/emoji.dart';
import '../../core/models.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/smart_image.dart';

/// The keys and the emoji board, and the handover between them.
///
/// The board is exactly as tall as the space the keys are *not* using, frame by frame: nothing while
/// they are up, and what they give up as they leave. That is the whole of what keeps a composer
/// still. The keys take a couple of hundred milliseconds to go, and on every frame of that the board
/// grows by the height they just lost, so the row above it — the field, the buttons — keeps its line
/// from the first frame to the last. Measuring the board once and holding it at the keyboard's height
/// instead made the field jump by the whole keyboard and slide back down.
///
/// Both shapes of composer get that from here: a panel that the router has already raised above the
/// keys asks for [boardHeight], and a bar pinned to the foot of the screen asks for [insetFor], which
/// is the same number plus the keys the panel was already clear of.
class EmojiKeyboard extends ChangeNotifier {
  /// Whether the board is showing.
  bool open = false;

  /// The tallest the keys have been seen, which is how tall the board ends up.
  double _keys = 0;

  /// The last inset read, so a keyboard still on its way is told apart from one that has arrived.
  double _inset = 0;

  /// Set while the board is handing its space back to the keys, which are on their way up. The board
  /// stays, shrinking, until they are back at the height it is giving up.
  double? _handingBack;

  Timer? _handover;

  /// The board's full height. A keyboard under 120 is a hardware keyboard or a phone that has not
  /// shown one yet, so the board falls back to a sensible size of its own.
  double get _keysHeight => _keys > 120 ? _keys : 280;

  void _note(double inset) {
    if (inset > _keys) _keys = inset;
    if (inset == _inset) return;
    _inset = inset;
    // The keys are still moving; the handover is over only when they stop.
    if (_handingBack != null) _arm();
  }

  /// The height the board needs right now: what the keys have given up. Zero while the keys are up
  /// and the board is shut, so a panel that is already above the keys holds nothing for a board that
  /// is not there.
  double boardHeight(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    _note(inset);
    // The keys are back at the height the board was holding for them: the swap is done. Nothing to
    // notify about — this very build is already answering with the post-handover number.
    if (_handingBack != null && inset >= _handingBack! - 1) _settled();
    if (!open && _handingBack == null) return 0;
    return math.max(0, _keysHeight - inset);
  }

  /// What a bar pinned to the foot of the screen leaves under itself: the keys while they are there,
  /// the board while it is. Handing one to the other does not change this number, which is what keeps
  /// the bar still through the swap.
  double insetFor(BuildContext context) => MediaQuery.viewInsetsOf(context).bottom + boardHeight(context);

  void toggle(BuildContext context, FocusNode focus) {
    _note(MediaQuery.viewInsetsOf(context).bottom);
    open = !open;
    if (open) {
      // The keys go away as the board arrives, so the board takes their place rather than stacking
      // on top of them.
      _settled();
      focus.unfocus();
    } else {
      _takeKeysBack();
      focus.requestFocus();
    }
    notifyListeners();
  }

  /// Whether the board should be drawn: while it is open, and while it is handing its space back to
  /// the keys. Hiding it the instant the keyboard was asked for left a blank strip shrinking under
  /// the composer until the keys arrived.
  bool get boardVisible => open || _handingBack != null;

  /// A tap in the field dismisses the board and lets the keyboard take its place.
  void onFocusChanged(bool hasFocus) {
    if (!hasFocus || !open) return;
    open = false;
    _takeKeysBack();
    notifyListeners();
  }

  /// The board gives its space back to the keys, which are on their way up.
  ///
  /// The board is held at its full height until the first frame the keys are seen, so the composer
  /// does not drop the keyboard's height and jump back up as they arrive.
  void _takeKeysBack() {
    _handingBack = _keysHeight;
    _arm();
  }

  /// Ends the handover once the keys have not moved for longer than a keyboard takes to arrive.
  ///
  /// A keyboard that never comes — no soft keyboard, a field that refuses the focus — would
  /// otherwise leave the composer standing above an empty strip for good, and a keyboard shorter
  /// than the one being handed over would leave a gap the size of the difference.
  void _arm() {
    _handover?.cancel();
    _handover = Timer(const Duration(milliseconds: 350), () {
      if (_handingBack == null) return;
      _settled();
      notifyListeners();
    });
  }

  void _settled() {
    _handingBack = null;
    _handover?.cancel();
    _handover = null;
  }

  @override
  void dispose() {
    _handover?.cancel();
    super.dispose();
  }
}

/// The strip under a composer: the emoji panel, in the space the keys would take.
///
/// The height is always held, even when there is nothing to draw in it: a bar pinned to the foot of
/// the screen is lifted clear of the keys by this strip, so it has to keep its size while the keys
/// are up. [visible] outlives [open] by the handover back to the keys, so the board stays drawn while
/// it shrinks and the keys rise over it, instead of the strip going blank halfway through.
class EmojiKeyboardSlot extends StatelessWidget {
  const EmojiKeyboardSlot({
    super.key,
    required this.visible,
    required this.height,
    this.onPick,
  });

  final bool visible;
  final double height;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();
    if (!visible) return SizedBox(height: height);
    return SizedBox(
      height: height,
      child: EmojiPanel(key: const ValueKey('emoji'), height: height, onPick: onPick),
    );
  }
}

class EmojiPanel extends StatelessWidget {
  const EmojiPanel({super.key, required this.height, this.onPick});

  final double height;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final entries = EmojiStore.instance.entries.entries.toList();
    final scheme = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '浏览微博时见到的表情会出现在这里',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.viewPaddingOf(context).bottom),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 52,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPick == null ? null : () => onPick!(entry.key),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SmartImage(url: entry.value, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}

Future<String?> showMentionPicker(BuildContext context) {
  return showActionSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    frosted: false,
    builder: (context) => const MentionPicker(),
  );
}

class MentionPicker extends StatefulWidget {
  const MentionPicker({super.key});

  @override
  State<MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<MentionPicker> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<User> _users = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () => _search(value));
  }

  Future<void> _search(String value) async {
    setState(() => _loading = true);
    try {
      final users = await WeiboApi.instance.searchUsers(value.trim());
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: TextField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                onChanged: _changed,
                decoration: const InputDecoration(hintText: '搜索用户'),
              ),
            ),
            if (_query.text.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.alternate_email_rounded),
                title: Text('@${_query.text.trim()}'),
                onTap: () => Navigator.pop(context, _query.text.trim()),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return ListTile(
                          leading: Avatar(url: user.avatarUrl, size: 38, verified: user.verified),
                          title: Text(user.screenName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: user.description.isEmpty
                              ? null
                              : Text(user.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(context, user.screenName),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
