import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/haptics.dart';
import '../../core/look.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? _cacheBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _measureCache();
  }

  Future<void> _measureCache() async {
    try {
      final dir = await getTemporaryDirectory();
      var total = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      if (mounted) setState(() => _cacheBytes = total);
    } catch (_) {
      if (mounted) setState(() => _cacheBytes = 0);
    }
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      await DefaultCacheManager().emptyCache();
      final dir = await getTemporaryDirectory();
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('libCachedImageData') || name.startsWith('cache')) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
      await _measureCache();
      if (mounted) showMessage(context, '图片缓存已清除');
    } catch (_) {
      if (mounted) showMessage(context, '清除失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs.instance,
      builder: (context, _) {
        final prefs = Prefs.instance;
        final scheme = Theme.of(context).colorScheme;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          backgroundColor: scheme.surface,
          extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
          appBar: AppBar(title: const Text('设置'), flexibleSpace: lookBarBackground(context)),
          body: Builder(
            builder: (context) => ListView(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top,
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                const _SectionTitle('外观'),
                _ChoiceRow<VisualStyle>(
                  title: '风格',
                  options: [for (final value in VisualStyle.values) (value, value.label)],
                  selected: prefs.visualStyle,
                  onSelect: prefs.setVisualStyle,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previous, ?current],
                    ),
                    child: Text(
                      prefs.visualStyle.description,
                      key: ValueKey(prefs.visualStyle),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: prefs.visualStyle == VisualStyle.glass
                      ? const _GlassTuner()
                      : const SizedBox(width: double.infinity),
                ),
                _ChoiceRow<ThemeMode>(
                  title: '深浅色',
                  options: const [
                    (ThemeMode.system, '跟随系统'),
                    (ThemeMode.light, '浅色'),
                    (ThemeMode.dark, '深色'),
                  ],
                  selected: prefs.themeMode,
                  onSelect: prefs.setThemeMode,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('主题色', style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          for (final accent in AccentTheme.values) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 15),
                              child: GestureDetector(
                                onTap: () {
                                  if (accent != prefs.accent) Haptic.selection.play();
                                  prefs.setAccent(accent);
                                },
                                child: Container(
                                  width: 37,
                                  height: 37,
                                  decoration: BoxDecoration(
                                    color: accentColor(accent, Theme.of(context).brightness),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: accent == prefs.accent ? scheme.onSurface : scheme.outlineVariant,
                                      width: accent == prefs.accent ? 2.6 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        prefs.accent.label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _ChoiceRow<double>(
                  title: '文字大小',
                  options: const [
                    (0.9, '小'),
                    (1.0, '标准'),
                    (1.1, '大'),
                    (1.2, '特大'),
                  ],
                  selected: prefs.textScale,
                  onSelect: prefs.setTextScale,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  child: Text(
                    '这是一条示例微博，文字大小会跟着变化。',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const Divider(),
                const _SectionTitle('操作'),
                _ChoiceRow<HapticLevel>(
                  title: '触感反馈',
                  options: [for (final level in HapticLevel.values) (level, level.label)],
                  selected: prefs.hapticLevel,
                  feedback: false,
                  onSelect: (level) {
                    switch (level) {
                      case HapticLevel.standard:
                        Haptic.selection.playAt(level);
                      case HapticLevel.subtle:
                        Haptic.toggleOn.playAt(level);
                      case HapticLevel.off:
                        break;
                    }
                    prefs.setHapticLevel(level);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                  child: Text(
                    switch (prefs.hapticLevel) {
                      HapticLevel.standard => '点赞、长按、下拉到位、发送结果时震动，切换标签时轻点一下',
                      HapticLevel.subtle => '只在点赞、长按、下拉到位和发送结果这些关键时刻震动',
                      HapticLevel.off => '完全不震动',
                    },
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const Divider(),
                const _SectionTitle('隐私'),
                SwitchListTile(
                  value: prefs.recordHistory,
                  onChanged: (enabled) {
                    (enabled ? Haptic.toggleOn : Haptic.toggleOff).play();
                    prefs.setRecordHistory(enabled);
                  },
                  title: const Text('记录浏览历史'),
                  subtitle: const Text('关掉后不再记录新打开过的微博；已记录的不受影响'),
                ),
                const Divider(),
                const _SectionTitle('存储'),
                _ChoiceRow<ImagePreload>(
                  title: '预加载大图',
                  options: [for (final value in ImagePreload.values) (value, value.label)],
                  selected: prefs.imagePreload,
                  onSelect: prefs.setImagePreload,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                  child: Text(
                    '浏览时在后台下载正在看的微博的原图，点开时直接显示清晰大图',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  title: const Text('图片缓存'),
                  subtitle: Text(_cacheBytes == null ? '计算中…' : formatBytes(_cacheBytes!)),
                  trailing: TextButton(
                    onPressed: _clearing ? null : _clearCache,
                    child: Text(_clearing ? '清除中…' : '清除'),
                  ),
                ),
                const Divider(),
                const _SectionTitle('关于'),
                const ListTile(
                  title: Text('INF 1.2.0'),
                  subtitle: Text('个人学习用的微博第三方客户端，通过网页版接口访问你自己的账号，与新浪微博官方无关。'),
                ),
                ListTile(
                  title: const Text('深色模式'),
                  subtitle: Text(dark ? '当前为深色' : '当前为浅色'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Blur and clarity of the glass, with a pane over sample content that follows the sliders
/// live; the app itself takes the values when a slider is let go (each change rebuilds it).
class _GlassTuner extends StatefulWidget {
  const _GlassTuner();

  @override
  State<_GlassTuner> createState() => _GlassTunerState();
}

class _GlassTunerState extends State<_GlassTuner> {
  late double _blur = Prefs.instance.glassBlur ?? InfLook.defaultBlur;
  late double _clarity = Prefs.instance.glassClarity ?? InfLook.defaultClarity;

  bool get _isDefault => _blur == InfLook.defaultBlur && _clarity == InfLook.defaultClarity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = InfLook.of(context).copyWith(style: VisualStyle.glass, blur: _blur, clarity: _clarity);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Theme(
            data: theme.copyWith(extensions: [look]),
            child: const _GlassPreview(),
          ),
          const SizedBox(height: 6),
          _TunerSlider(
            title: '模糊程度',
            low: '清晰',
            high: '朦胧',
            value: _blur,
            onChanged: (v) => setState(() => _blur = v),
            onChangeEnd: (v) => Prefs.instance.setGlass(blur: v),
          ),
          _TunerSlider(
            title: '通透度',
            low: '厚实',
            high: '通透',
            value: _clarity,
            onChanged: (v) => setState(() => _clarity = v),
            onChangeEnd: (v) => Prefs.instance.setGlass(clarity: v),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isDefault
                  ? null
                  : () {
                      setState(() {
                        _blur = InfLook.defaultBlur;
                        _clarity = InfLook.defaultClarity;
                      });
                      Prefs.instance.resetGlass();
                    },
              child: const Text('恢复默认'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bar of glass over a strip of colourful sample content, like a top bar with a post
/// scrolled under it.
class _GlassPreview extends StatelessWidget {
  const _GlassPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tile(Color color) => Expanded(
          child: Container(
            height: 44,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [tile(scheme.primary), tile(scheme.secondary), tile(scheme.tertiary)]),
                  const SizedBox(height: 8),
                  Text(
                    '滑到栏下的微博正文会被磨砂，栏越通透，透出的内容越多；模糊越强，越看不清下面的字。',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 84,
              child: GlassSurface(
                rimSides: Border(
                  bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.07), width: 0.6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('首页', style: theme.appBarTheme.titleTextStyle),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TunerSlider extends StatelessWidget {
  const _TunerSlider({
    required this.title,
    required this.low,
    required this.high,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final String low;
  final String high;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(title, style: theme.textTheme.bodyMedium)),
          Text(low, style: hint),
          Expanded(
            child: Slider(value: value, onChanged: onChanged, onChangeEnd: onChangeEnd),
          ),
          Text(high, style: hint),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.feedback = true,
  });

  final String title;
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelect;

  /// Off for rows whose [onSelect] plays its own haptic.
  final bool feedback;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final (value, label) in options)
                ButtonSegment<T>(value: value, label: Text(label, style: const TextStyle(fontSize: 12))),
            ],
            selected: {selected},
            onSelectionChanged: (values) {
              if (values.isEmpty) return;
              if (feedback) Haptic.selection.play();
              onSelect(values.first);
            },
          ),
        ],
      ),
    );
  }
}