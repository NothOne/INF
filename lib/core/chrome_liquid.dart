import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassButton, GlassContainer, GlassSheet, LiquidRoundedSuperellipse;

import 'liquid_glass.dart';
import 'look.dart' hide GlassSheet;

/// Liquid glass, drawn by `liquid_glass_widgets`: floating controls and sheets are its glass, under
/// the theme the sliders set (see [liquidGlassTheme]). Top bars, edge panels and the page behind
/// are the plain page colour: no frost, no veil, nothing tinted for glass to pick up.
class LiquidChrome extends GlassChrome {
  const LiquidChrome();

  @override
  Widget? barBackground(BuildContext context) => ColoredBox(color: Theme.of(context).colorScheme.surface);

  @override
  Widget backdrop(BuildContext context, {required Widget child}) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);

  @override
  ActionIconThemeData get actionIconTheme => ActionIconThemeData(
        backButtonIconBuilder: (context) => const _BarRoundButton(icon: Icons.arrow_back_rounded, tooltip: '返回'),
        closeButtonIconBuilder: (context) => const _BarRoundButton(icon: Icons.close_rounded, tooltip: '关闭'),
      );

  /// The buttons share one glass capsule, as iOS 26 groups a bar's trailing items.
  @override
  List<Widget> barActions(BuildContext context, List<Widget> actions) {
    if (actions.isEmpty) return const [SizedBox(width: 4)];
    return [
      Center(
        child: GlassContainer(
          useOwnLayer: true,
          height: _barControl,
          shape: const LiquidRoundedSuperellipse(borderRadius: _barControl / 2),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(
                minimumSize: const Size.square(_barControl),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                iconSize: 21,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ),
      ),
      const SizedBox(width: 10),
    ];
  }

  /// The tabs lie on a glass capsule, the chosen one on a tinted pill.
  @override
  Widget barTabs(
    BuildContext context, {
    required TabController controller,
    required List<Widget> labels,
    EdgeInsetsGeometry? labelPadding,
  }) {
    const height = 38.0;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, InfChrome.barTabsHeight - height - 3),
      child: GlassContainer(
        useOwnLayer: true,
        height: height,
        shape: const LiquidRoundedSuperellipse(borderRadius: height / 2),
        child: TabBar(
          controller: controller,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(3),
          indicator: ShapeDecoration(shape: const StadiumBorder(), color: scheme.primary.withValues(alpha: 0.14)),
          dividerHeight: 0,
          splashBorderRadius: BorderRadius.circular(height / 2),
          labelPadding: labelPadding,
          tabs: [for (final label in labels) Tab(height: height, child: label)],
        ),
      ),
    );
  }

  @override
  Widget actionSheet(BuildContext context, {required Widget child}) => GlassSheet(child: child);

  @override
  Widget edgePanel(BuildContext context, {required Widget child}) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);

  @override
  Widget floatingPanel(BuildContext context, {required BorderRadius radius, required Widget child, double body = 0}) =>
      GlassContainer(
        useOwnLayer: true,
        shape: LiquidRoundedSuperellipse(borderRadius: radius.topLeft.x),
        child: child,
      );

  @override
  Widget floatingButton(
    BuildContext context, {
    required String tooltip,
    required Widget icon,
    required ValueChanged<BuildContext> onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return LiquidGlassTheme(
      tint: floatingButtonTint(context),
      child: Builder(
        builder: (buttonContext) => Tooltip(
          message: tooltip,
          child: GlassButton(
            useOwnLayer: true,
            icon: icon,
            iconSize: 26,
            iconColor: scheme.onPrimary,
            onTap: () => onPressed(buttonContext),
          ),
        ),
      ),
    );
  }

  /// 通透度 thins the colour as it thins every other glass, so the sliders show on this button too:
  /// 0.95 at the solid end, 0.45 at the clear end.
  @override
  Color floatingButtonTint(BuildContext context) =>
      Theme.of(context).colorScheme.primary.withValues(alpha: 0.95 - 0.5 * InfLook.of(context).liquidClarity);

  @override
  Widget floatingCapsule(BuildContext context, {required Widget child, VoidCallback? onTap}) {
    return LiquidGlassTheme(
      tint: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
      child: GlassButton.custom(
        useOwnLayer: true,
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        enabled: onTap != null,
        onTap: onTap ?? () {},
        child: child,
      ),
    );
  }

  @override
  SnackBar snackBar(BuildContext context, Widget content) {
    final dark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    // White text needs a dark body whatever lies behind it.
    final tint = dark ? const Color(0xFF33343E) : const Color(0xFF2B2B33);
    return SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      content: LiquidGlassTheme(
        tint: tint.withValues(alpha: 0.78),
        child: GlassContainer(
          useOwnLayer: true,
          shape: const LiquidRoundedSuperellipse(borderRadius: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            child: content,
          ),
        ),
      ),
    );
  }

  @override
  AnimationStyle? get sheetMotion => const AnimationStyle(
        duration: Duration(milliseconds: 420),
        reverseDuration: Duration(milliseconds: 220),
        curve: Cubic(0.16, 1, 0.3, 1),
        reverseCurve: Curves.easeInCubic,
      );
}

/// Height of the glass controls in a top bar.
const _barControl = 40.0;

/// The back or close button of a top bar: a glass disc that pops the route. It stands in for the
/// icon of Material's button, and takes the tap itself so the glass can give under the finger.
class _BarRoundButton extends StatelessWidget {
  const _BarRoundButton({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) => GlassButton(
        useOwnLayer: true,
        label: tooltip,
        width: _barControl,
        height: _barControl,
        iconSize: 21,
        iconColor: Theme.of(context).colorScheme.onSurface,
        icon: Icon(icon),
        onTap: () => Navigator.maybePop(context),
      );
}
