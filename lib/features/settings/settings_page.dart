import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassButton, GlassContainer, LiquidRoundedSuperellipse;

import '../../core/haptics.dart';
import '../../core/image_cache.dart';
import '../../core/layout.dart';
import '../../core/liquid_glass.dart';
import '../../core/look.dart';
import '../../core/prefs.dart';
import '../../core/relation_store.dart';
import '../../core/motion.dart';
import '../../core/temp_files.dart';
import '../../core/theme.dart';
import '../../core/version.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _clearing = false;

  /// What the picture cache takes now, shown next to its budget.
  int? _imageBytes;

  /// What sharing, saving, downloading and drafts have put in the scratch folders.
  int? _tempBytes;

  @override
  void initState() {
    super.initState();
    _measureCache();
  }

  /// Everything the picture cache holds — it is one folder now, so this is the exact figure rather
  /// than the whole cache directory. See `InfImageCache`.
  Future<void> _measureCache() async {
    try {
      final image = await InfImageCache.instance.size();
      final temp = await TempFiles.size();
      if (!mounted) return;
      setState(() {
        _imageBytes = image;
        _tempBytes = temp;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imageBytes = 0;
        _tempBytes = 0;
      });
    }
  }

  void _showBlocked(BuildContext context) {
    showActionSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: Prefs.instance,
        builder: (sheetContext, _) {
          final users = Prefs.instance.blockedUsers;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('已屏蔽的用户', style: TextStyle(fontWeight: FontWeight.w700))),
                  if (users.isEmpty)
                    const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 28), child: Text('没有屏蔽任何人'))
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final user in users)
                            ListTile(
                              leading: Avatar(url: user.avatarUrl, size: 36),
                              title: Text(user.screenName.isEmpty ? user.id : user.screenName),
                              trailing: TextButton(
                                onPressed: () => RelationStore.instance.setBlocked(user, false),
                                child: const Text('解除'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The budget as a list rather than a segmented row: five labels do not fit across a phone, and
  /// each one needs room for what it means for this reader.
  void _showCacheLimit(BuildContext context) {
    showActionSheet<void>(
      context: context,
      builder: (sheetContext) => AnimatedBuilder(
        animation: Prefs.instance,
        builder: (sheetContext, _) {
          final current = Prefs.instance.imageCacheLimit;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('图片缓存上限', style: TextStyle(fontWeight: FontWeight.w700))),
                for (final limit in ImageCacheLimit.values)
                  ListTile(
                    title: Text(limit.label),
                    trailing: limit == current ? const Icon(Icons.check_rounded) : null,
                    onTap: () async {
                      Haptic.selection.play();
                      Navigator.pop(sheetContext);
                      await Prefs.instance.setImageCacheLimit(limit);
                      // Applied at once rather than at the next download, so dropping from 2 GB to
                      // 200 MB frees the space while the reader is looking at the figure.
                      await InfImageCache.instance.sweep(force: true);
                      if (mounted) await _measureCache();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      await InfImageCache.instance.clear();
      await _measureCache();
      if (mounted) showMessage(context, '图片缓存已清除');
    } catch (_) {
      if (mounted) showMessage(context, '清除失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  /// The copies saving, sharing, downloading and drafting left behind. Unlike the picture cache
  /// these are not worth keeping: every one of them was made for a single use.
  Future<void> _clearTemp() async {
    setState(() => _clearing = true);
    try {
      await TempFiles.clear();
      // Draft pictures belong to drafts that still exist, so only the orphans go; the count here
      // is of the scratch folder alone.
      await DraftFiles.sweep();
      await _measureCache();
      if (mounted) showMessage(context, '临时文件已清除');
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
                left: contentGutter(context),
                right: contentGutter(context),
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
                if (prefs.visualStyle == VisualStyle.liquid) ...[
                  _ChoiceRow<LiquidTier>(
                    title: '液态玻璃',
                    options: [for (final value in LiquidTier.values) (value, value.label)],
                    selected: prefs.liquidTier,
                    onSelect: prefs.setLiquidTier,
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
                        prefs.liquidTier.description,
                        key: ValueKey(prefs.liquidTier),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: switch (prefs.visualStyle) {
                    VisualStyle.glass => const _GlassTuner(),
                    VisualStyle.liquid => const _LiquidTuner(),
                    VisualStyle.classic => const SizedBox(width: double.infinity),
                  },
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
                _ChoiceRow<DeviceLayout>(
                  title: '设备布局',
                  options: [for (final value in DeviceLayout.values) (value, value.label)],
                  selected: prefs.deviceLayout,
                  onSelect: prefs.setDeviceLayout,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                  child: Text(
                    prefs.deviceLayout.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                _ChoiceRow<PageMotion>(
                  title: '页面动效',
                  options: [for (final value in PageMotion.values) (value, value.label)],
                  selected: prefs.pageMotion,
                  onSelect: prefs.setPageMotion,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                  child: Text(
                    prefs.pageMotion.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
                ListTile(
                  title: const Text('已屏蔽的用户'),
                  subtitle: Text(
                    prefs.blockedUsers.isEmpty ? '长按微博可屏蔽此人；只保存在本机' : '${prefs.blockedUsers.length} 人，列表中不显示 TA 们的微博',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showBlocked(context),
                ),
                const Divider(),
                const _SectionTitle('存储'),
                _ChoiceRow<ImagePreload>(
                  title: '预加载图片',
                  options: [for (final value in ImagePreload.values) (value, value.label)],
                  selected: prefs.imagePreload,
                  onSelect: prefs.setImagePreload,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                  child: Text(
                    '浏览时提前下载列表里要显示的图片，滑动到的时候不用等。看图时才会下载原图',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  title: const Text('图片缓存上限'),
                  subtitle: Text(
                    prefs.imageCacheLimit == ImageCacheLimit.none
                        ? '不自动清理，只受系统存储空间限制'
                        : '存满 ${prefs.imageCacheLimit.label} 就删掉最久没看过的图片',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showCacheLimit(context),
                ),
                ListTile(
                  title: const Text('图片占用'),
                  subtitle: Text(_imageBytes == null ? '计算中…' : formatBytes(_imageBytes!)),
                  trailing: TextButton(
                    onPressed: _clearing ? null : _clearCache,
                    child: Text(_clearing ? '清除中…' : '清除'),
                  ),
                ),
                ListTile(
                  title: const Text('临时文件'),
                  subtitle: Text(
                    _tempBytes == null
                        ? '计算中…'
                        : '${formatBytes(_tempBytes!)} · 保存、分享、下载留下的副本，24 小时后自动清掉',
                  ),
                  trailing: TextButton(
                    onPressed: _clearing ? null : _clearTemp,
                    child: Text(_clearing ? '清除中…' : '清除'),
                  ),
                ),
                const Divider(),
                const _SectionTitle('关于'),
                const ListTile(
                  title: Text('INF $appVersion'),
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

/// Refraction, clarity and shine of liquid glass, over a preview that follows the sliders live.
class _LiquidTuner extends StatefulWidget {
  const _LiquidTuner();

  @override
  State<_LiquidTuner> createState() => _LiquidTunerState();
}

class _LiquidTunerState extends State<_LiquidTuner> {
  late double _refraction = Prefs.instance.liquidRefraction ?? InfLook.defaultRefraction;
  late double _clarity = Prefs.instance.liquidClarity ?? InfLook.defaultLiquidClarity;
  late double _shine = Prefs.instance.liquidShine ?? InfLook.defaultLiquidShine;

  bool get _isDefault =>
      _refraction == InfLook.defaultRefraction &&
      _clarity == InfLook.defaultLiquidClarity &&
      _shine == InfLook.defaultLiquidShine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = InfLook.of(context).copyWith(
      style: VisualStyle.liquid,
      refraction: _refraction,
      liquidClarity: _clarity,
      liquidShine: _shine,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Theme(
            data: theme.copyWith(extensions: [look]),
            // The preview draws on ultra's tier so the sliders show what the optics can do even
            // while the app itself is on standard; switching tiers rebuilds it in place.
            child: InfGlassQuality(
              look: look.copyWith(liquidTier: LiquidTier.ultra),
              // Inside the tier scope, not outside it: `resolveQuality` reads the *nearest*
              // adaptive scope, so a cap above this one would be shadowed by the premium ceiling
              // it establishes. Held at standard while the route moves — premium glass reads the
              // backdrop through a layer of its own, and this page is faded in and out by the
              // route transition, so the preview came out as black blocks until it ended.
              child: GlassSettled(
                child: const LiquidGlassTheme(child: _LiquidPreview()),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _TunerSlider(
            title: '折射',
            low: '轻',
            high: '强',
            value: _refraction,
            onChanged: (v) => setState(() => _refraction = v),
            onChangeEnd: (v) => Prefs.instance.setLiquid(refraction: v),
          ),
          _TunerSlider(
            title: '通透度',
            low: '厚实',
            high: '通透',
            value: _clarity,
            onChanged: (v) => setState(() => _clarity = v),
            onChangeEnd: (v) => Prefs.instance.setLiquid(clarity: v),
          ),
          _TunerSlider(
            title: '高光',
            low: '柔和',
            high: '明亮',
            value: _shine,
            onChanged: (v) => setState(() => _shine = v),
            onChangeEnd: (v) => Prefs.instance.setLiquid(shine: v),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isDefault
                  ? null
                  : () {
                      setState(() {
                        _refraction = InfLook.defaultRefraction;
                        _clarity = InfLook.defaultLiquidClarity;
                        _shine = InfLook.defaultLiquidShine;
                      });
                      Prefs.instance.resetLiquid();
                    },
              child: const Text('恢复默认'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A floating glass panel and a glass button over colourful sample content.
class _LiquidPreview extends StatelessWidget {
  const _LiquidPreview();

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
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [tile(scheme.primary), tile(scheme.secondary), tile(scheme.tertiary)]),
                  const SizedBox(height: 8),
                  Text(
                    '玻璃折射它下面的内容：折射越强，边缘弯得越明显；越通透，玻璃越薄越清楚；高光是边缘的亮线。发微博按钮跟着一起变。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Row(children: [tile(scheme.tertiary), tile(scheme.primary), tile(scheme.error)]),
                ],
              ),
            ),
            Positioned(
              left: 24,
              top: 30,
              width: 150,
              height: 64,
              child: GlassContainer(
                useOwnLayer: true,
                shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                child: Center(child: Text('首页', style: theme.textTheme.titleMedium)),
              ),
            ),
            Positioned(
              right: 18,
              top: 22,
              child: InfChrome.of(context).floatingButton(
                context,
                tooltip: '发微博',
                icon: const Icon(Icons.edit_rounded),
                onPressed: (_) {},
              ),
            ),
            Positioned(
              right: 14,
              bottom: 12,
              child: GlassButton.custom(
                useOwnLayer: true,
                width: 132,
                height: 44,
                shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                onTap: () {},
                child: Text('按住试试', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurface)),
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