import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// [name] → image URL, learned from every API response. Weibo only ever shows the picture in the
/// raw HTML, so this is the only way a bracketed emoji code can become an inline image.
class EmojiStore extends ChangeNotifier {
  EmojiStore._();
  static final EmojiStore instance = EmojiStore._();

  final Map<String, String> _emojis = {};

  Map<String, String> get entries => Map.unmodifiable(_emojis);
  String? urlFor(String code) => _emojis[code];

  void init() {
    _emojis.addAll(Prefs.instance.emojis);
    notifyListeners();
  }

  void learn(Map<String, String> found) {
    var changed = false;
    for (final entry in found.entries) {
      if (_emojis[entry.key] != entry.value) {
        _emojis[entry.key] = entry.value;
        changed = true;
      }
    }
    if (!changed) return;
    Prefs.instance.saveEmojis(_emojis);
    notifyListeners();
  }
}
