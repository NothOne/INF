import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum AccentTheme {
  brand('默认蓝'),
  orange('微博橙'),
  green('青绿'),
  purple('紫');

  final String label;
  const AccentTheme(this.label);
}

/// The material the app is drawn in; independent of light/dark and the accent colour.
enum VisualStyle {
  classic('经典', '纸感卡片，干净稳定'),
  glass('毛玻璃', '半透明的栏和面板，内容从下方透出');

  final String label;
  final String description;
  const VisualStyle(this.label, this.description);
}

enum HapticLevel {
  off('关闭'),
  subtle('克制'),
  standard('标准');

  final String label;
  const HapticLevel(this.label);
}

enum ImagePreload {
  off('关闭'),
  wifi('仅 Wi‑Fi'),
  always('始终');

  final String label;
  const ImagePreload(this.label);
}

/// One store for the few settings the app has. It is a ChangeNotifier so the shell can rebuild the
/// theme when the user changes it, instead of restarting the activity like the Compose version did.
class Prefs extends ChangeNotifier {
  Prefs._();
  static final Prefs instance = Prefs._();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  ThemeMode get themeMode {
    final value = _prefs.getString('theme_mode');
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('theme_mode', mode.name);
    notifyListeners();
  }

  AccentTheme get accent {
    final value = _prefs.getString('accent');
    return AccentTheme.values.where((a) => a.name == value).firstOrNull ?? AccentTheme.brand;
  }

  Future<void> setAccent(AccentTheme accent) async {
    await _prefs.setString('accent', accent.name);
    notifyListeners();
  }

  VisualStyle get visualStyle {
    final value = _prefs.getString('visual_style');
    return VisualStyle.values.where((s) => s.name == value).firstOrNull ?? VisualStyle.classic;
  }

  Future<void> setVisualStyle(VisualStyle style) async {
    await _prefs.setString('visual_style', style.name);
    notifyListeners();
  }

  /// Glass blur strength, 0–1 (see `InfLook.blur`); null until the user changes it.
  double? get glassBlur => _prefs.getDouble('glass_blur');

  /// How see-through glass is, 0–1 (see `InfLook.clarity`); null until the user changes it.
  double? get glassClarity => _prefs.getDouble('glass_clarity');

  Future<void> setGlass({double? blur, double? clarity}) async {
    if (blur != null) await _prefs.setDouble('glass_blur', blur);
    if (clarity != null) await _prefs.setDouble('glass_clarity', clarity);
    notifyListeners();
  }

  Future<void> resetGlass() async {
    await _prefs.remove('glass_blur');
    await _prefs.remove('glass_clarity');
    notifyListeners();
  }

  double get textScale => _prefs.getDouble('text_scale') ?? 1.0;

  Future<void> setTextScale(double scale) async {
    await _prefs.setDouble('text_scale', scale);
    notifyListeners();
  }

  HapticLevel get hapticLevel {
    final value = _prefs.getString('haptic_level');
    return HapticLevel.values.where((l) => l.name == value).firstOrNull ?? HapticLevel.standard;
  }

  Future<void> setHapticLevel(HapticLevel level) async {
    await _prefs.setString('haptic_level', level.name);
    notifyListeners();
  }

  ImagePreload get imagePreload {
    final value = _prefs.getString('image_preload');
    return ImagePreload.values.where((p) => p.name == value).firstOrNull ?? ImagePreload.wifi;
  }

  Future<void> setImagePreload(ImagePreload value) async {
    await _prefs.setString('image_preload', value.name);
    notifyListeners();
  }

  /// The account the on-disk page cache belongs to, known before the session check finishes.
  /// Not a user-facing setting, so it does not notify (that would rebuild the whole app).
  String? get lastUid => _prefs.getString('last_uid');

  Future<void> setLastUid(String? uid) async {
    if (uid == null || uid.isEmpty) {
      await _prefs.remove('last_uid');
    } else if (uid != lastUid) {
      await _prefs.setString('last_uid', uid);
    }
  }

  bool get recordHistory => _prefs.getBool('record_history') ?? true;

  Future<void> setRecordHistory(bool enabled) async {
    await _prefs.setBool('record_history', enabled);
    notifyListeners();
  }

  String? get feedSourceKey => _prefs.getString('feed_source');

  Future<void> setFeedSourceKey(String key) async {
    await _prefs.setString('feed_source', key);
    notifyListeners();
  }

  List<String> get searchHistory {
    final raw = _prefs.getString('search_history');
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addSearch(String query) async {
    final entry = query.trim();
    if (entry.isEmpty) return;
    final next = [entry, ...searchHistory.where((e) => e != entry)].take(20).toList();
    await _prefs.setString('search_history', jsonEncode(next));
    notifyListeners();
  }

  Future<void> removeSearch(String query) async {
    final next = searchHistory.where((e) => e != query).toList();
    await _prefs.setString('search_history', jsonEncode(next));
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    await _prefs.remove('search_history');
    notifyListeners();
  }

  Map<String, String> get emojis {
    final raw = _prefs.getString('emojis');
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map;
      return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveEmojis(Map<String, String> emojis) async {
    await _prefs.setString('emojis', jsonEncode(emojis));
  }

  List<Draft> get drafts {
    final raw = _prefs.getString('drafts');
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Draft.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveDrafts(List<Draft> drafts) async {
    await _prefs.setString('drafts', jsonEncode(drafts.map((d) => d.toJson()).toList()));
    notifyListeners();
  }

  int get nextDraftId {
    final value = _prefs.getInt('next_draft_id') ?? 1;
    _prefs.setInt('next_draft_id', value + 1);
    return value;
  }

  List<ViewedStatus> get viewed {
    final raw = _prefs.getString('viewed');
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ViewedStatus.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveViewed(List<ViewedStatus> entries) async {
    await _prefs.setString('viewed', jsonEncode(entries.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  bool get didShowWelcome => _prefs.getBool('welcome') ?? false;

  Future<void> markWelcomeShown() async {
    await _prefs.setBool('welcome', true);
  }
}