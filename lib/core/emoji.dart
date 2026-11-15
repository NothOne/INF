import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// [name] → image URL, learned from every API response. Weibo only ever shows the picture in the
/// raw HTML, so this is the only way a bracketed emoji code can become an inline image.
class EmojiStore extends ChangeNotifier {
  EmojiStore._();
  static final EmojiStore instance = EmojiStore._();

  final Map<String, String> _emojis = {};
  final Set<String> _urls = {};

  Map<String, String> get entries => Map.unmodifiable(_emojis);
  String? urlFor(String code) => _emojis[code];

  /// Every picture URL the learned emoji use. Read by `InfImageCache` so the byte budget never
  /// trims them: they are a small fixed set the app is useless without, and they live in the same
  /// disk cache as the post pictures.
  Set<String> get urls => _urls;

  void init() {
    // Replace rather than add: this is "read what is on disk", so a second call (a test, a reload)
    // must not leave the map holding whatever the previous one had.
    _emojis
      ..clear()
      ..addAll(Prefs.instance.emojis);
    _urls
      ..clear()
      ..addAll(_emojis.values);
    notifyListeners();
  }

  void learn(Map<String, String> found) {
    var changed = false;
    for (final entry in found.entries) {
      if (_emojis[entry.key] != entry.value) {
        _emojis[entry.key] = entry.value;
        _urls.add(entry.value);
        changed = true;
      }
    }
    if (!changed) return;
    Prefs.instance.saveEmojis(_emojis);
    notifyListeners();
  }
}
