import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class FeedPosition {
  final String id;
  final double dy;
  final String? head;
  final DateTime? headAt;
  const FeedPosition({required this.id, required this.dy, this.head, this.headAt});
}

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
  glass('毛玻璃', '半透明的栏和面板，内容从下方透出'),
  liquid('液态玻璃', '像一块透镜：边缘折射下方内容，高光沿边流动，控件按下会回弹');

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

/// Which layout the shell uses; [auto] goes by the width of the window (see `WindowClass`).
enum DeviceLayout {
  auto('自动', '窗口够宽时（平板、横屏、折叠屏展开）换成侧边导航和居中的内容列'),
  phone('手机', '始终用底部导航，内容铺满屏幕'),
  tablet('平板', '始终用侧边导航，内容居中，不随窗口宽度切换');

  final String label;
  final String description;
  const DeviceLayout(this.label, this.description);
}

/// How every page opens over the one it was opened from, and closes back into it.
enum PageMotion {
  expand('展开', '页面从点按的地方放大展开，返回时缩回原处'),
  slide('推入', '页面从右侧推入，返回时向右滑出');

  final String label;
  final String description;
  const PageMotion(this.label, this.description);
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

  /// How far liquid glass bends what is behind its edges, 0–1 (see `InfLook.refraction`).
  double? get liquidRefraction => _prefs.getDouble('liquid_refraction');

  /// How see-through liquid glass is, 0–1 (see `InfLook.liquidClarity`).
  double? get liquidClarity => _prefs.getDouble('liquid_clarity');

  Future<void> setLiquid({double? refraction, double? clarity}) async {
    if (refraction != null) await _prefs.setDouble('liquid_refraction', refraction);
    if (clarity != null) await _prefs.setDouble('liquid_clarity', clarity);
    notifyListeners();
  }

  Future<void> resetLiquid() async {
    await _prefs.remove('liquid_refraction');
    await _prefs.remove('liquid_clarity');
    notifyListeners();
  }

  DeviceLayout get deviceLayout {
    final value = _prefs.getString('device_layout');
    return DeviceLayout.values.where((l) => l.name == value).firstOrNull ?? DeviceLayout.auto;
  }

  Future<void> setDeviceLayout(DeviceLayout layout) async {
    await _prefs.setString('device_layout', layout.name);
    notifyListeners();
  }

  PageMotion get pageMotion {
    final value = _prefs.getString('page_motion');
    return PageMotion.values.where((m) => m.name == value).firstOrNull ?? PageMotion.slide;
  }

  Future<void> setPageMotion(PageMotion motion) async {
    await _prefs.setString('page_motion', motion.name);
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

  /// The boards shown under 热搜, in the user's order; never empty.
  List<HotBoard> get hotBoards {
    final names = _prefs.getStringList('hot_boards');
    if (names == null) return HotBoard.values;
    final boards = names.map(HotBoard.named).whereType<HotBoard>().toSet().toList();
    return boards.isEmpty ? HotBoard.values : boards;
  }

  Future<void> setHotBoards(List<HotBoard> boards) async {
    if (boards.isEmpty) return;
    await _prefs.setStringList('hot_boards', [for (final board in boards) board.name]);
    notifyListeners();
  }

  /// People whose posts lists leave out. Weibo's web API has no block call, so this stays on the
  /// device; their own page still shows everything.
  List<User> get blockedUsers {
    try {
      final raw = jsonDecode(_prefs.getString('blocked_users') ?? '[]');
      return [
        for (final item in raw is List ? raw : const [])
          if (item is Map && item['id'] is String)
            User(id: item['id'] as String, screenName: '${item['name'] ?? ''}', avatarUrl: item['avatar'] as String?),
      ];
    } catch (_) {
      return const [];
    }
  }

  late Set<String> _blockedIds = {for (final user in blockedUsers) user.id};

  bool isBlocked(String uid) => _blockedIds.contains(uid);

  Future<void> setBlocked(User user, bool blocked) async {
    final next = [
      if (blocked) user,
      ...blockedUsers.where((other) => other.id != user.id),
    ];
    await _prefs.setString(
      'blocked_users',
      jsonEncode([for (final u in next) {'id': u.id, 'name': u.screenName, 'avatar': u.avatarUrl}]),
    );
    _blockedIds = {for (final u in next) u.id};
    notifyListeners();
  }

  RecommendChannel get recommendChannel {
    try {
      final json = jsonDecode(_prefs.getString('recommend_channel') ?? 'null');
      return RecommendChannel.fromJson(json is Map<String, dynamic> ? json : null) ?? RecommendChannel.hot;
    } catch (_) {
      return RecommendChannel.hot;
    }
  }

  Future<void> setRecommendChannel(RecommendChannel channel) async {
    await _prefs.setString('recommend_channel', jsonEncode(channel.toJson()));
    notifyListeners();
  }

  Map<String, dynamic> get _feedPositions {
    try {
      return Map<String, dynamic>.from(jsonDecode(_prefs.getString('feed_positions') ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  /// Where the feed [source] was being read: the post at the top and how far its top sat above
  /// the bar's edge, and the newest post loaded then, so the next visit can tell what is new.
  /// Saved quietly, so it does not rebuild anything listening for settings.
  FeedPosition? feedPosition(String source) {
    final entry = _feedPositions[source];
    if (entry is! Map || entry['id'] is! String) return null;
    final headAt = (entry['headAt'] as num?)?.toInt();
    return FeedPosition(
      id: entry['id'] as String,
      dy: (entry['dy'] as num?)?.toDouble() ?? 0,
      head: entry['head'] as String?,
      headAt: headAt == null ? null : DateTime.fromMillisecondsSinceEpoch(headAt),
    );
  }

  Future<void> setFeedPosition(String source, FeedPosition position) async {
    final positions = _feedPositions
      ..[source] = {
        'id': position.id,
        'dy': position.dy.roundToDouble(),
        if (position.head != null) 'head': position.head,
        if (position.headAt != null) 'headAt': position.headAt!.millisecondsSinceEpoch,
      };
    await _prefs.setString('feed_positions', jsonEncode(positions));
  }

  Map<String, dynamic> get _videoPositions {
    try {
      return Map<String, dynamic>.from(jsonDecode(_prefs.getString('video_positions') ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  /// Signed CDN links change their query string on every load, so a video is known by its path.
  static String videoKey(String url) {
    final uri = Uri.tryParse(url);
    return uri == null || uri.path.isEmpty ? url : uri.path;
  }

  /// Where the video at [url] was left off, if it was stopped partway through.
  Duration? videoPosition(String url) {
    final entry = _videoPositions[videoKey(url)];
    final ms = entry is Map ? (entry['p'] as num?)?.toInt() : null;
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// A null [position] forgets the video. Only the most recent 200 are kept.
  Future<void> setVideoPosition(String url, Duration? position) async {
    final positions = _videoPositions..remove(videoKey(url));
    if (position != null) {
      positions[videoKey(url)] = {'p': position.inMilliseconds, 't': DateTime.now().millisecondsSinceEpoch};
      if (positions.length > 200) {
        final oldest = positions.entries.toList()
          ..sort((a, b) => (((a.value as Map?)?['t'] as num?) ?? 0).compareTo(((b.value as Map?)?['t'] as num?) ?? 0));
        for (final entry in oldest.take(positions.length - 200)) {
          positions.remove(entry.key);
        }
      }
    }
    await _prefs.setString('video_positions', jsonEncode(positions));
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