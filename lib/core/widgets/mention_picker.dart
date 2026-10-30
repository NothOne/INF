import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/api.dart';
import '../../core/emoji.dart';
import '../../core/models.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/smart_image.dart';

/// Keeps the emoji panel in the keyboard's rectangle instead of stacking it above the keys.
///
/// While the panel is closed, [heightFor] is the live keyboard inset. Opening dismisses the
/// keyboard and holds that height, so the composer does not jump. Closing asks for the keyboard
/// again and keeps the gap until the inset arrives.
class EmojiKeyboard extends ChangeNotifier {
  bool open = false;
  double _keyboard = 0;
  bool _awaitingKeyboard = false;
  Timer? _timer;

  double heightFor(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (!open && inset > _keyboard) _keyboard = inset;
    if (_awaitingKeyboard && inset > 80) {
      _awaitingKeyboard = false;
      _timer?.cancel();
    }
    final panel = _keyboard > 120 ? _keyboard : 280.0;
    if (open || _awaitingKeyboard) return panel;
    return inset;
  }

  void toggle(BuildContext context, FocusNode focus) {
    if (open) {
      _awaitingKeyboard = true;
      open = false;
      focus.requestFocus();
      _armFallback();
      notifyListeners();
      return;
    }
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > _keyboard) _keyboard = inset;
    _awaitingKeyboard = false;
    _timer?.cancel();
    focus.unfocus();
    open = true;
    notifyListeners();
  }

  /// A tap in the field dismisses the panel and lets the keyboard take its place.
  void onFocusChanged(bool hasFocus) {
    if (!hasFocus || !open) return;
    open = false;
    _awaitingKeyboard = true;
    _armFallback();
    notifyListeners();
  }

  void _armFallback() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 450), () {
      if (!_awaitingKeyboard) return;
      _awaitingKeyboard = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The strip under a composer: either empty space the size of the keyboard, or the emoji panel.
class EmojiKeyboardSlot extends StatelessWidget {
  const EmojiKeyboardSlot({
    super.key,
    required this.open,
    required this.height,
    this.onPick,
  });

  final bool open;
  final double height;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: open
            ? EmojiPanel(key: const ValueKey('emoji'), height: height, onPick: onPick)
            : SizedBox(key: const ValueKey('keys'), height: height),
      ),
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
