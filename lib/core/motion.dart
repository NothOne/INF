import 'package:flutter/material.dart';

import 'look.dart';

/// One file for every duration and curve, like the Compose app's InfMotion — but this time the
/// transitions are built around Flutter's own scheduling instead of fighting predictive back.
class InfMotion {
  static const tap = Duration(milliseconds: 110);
  static const feedback = Duration(milliseconds: 160);
  static const content = Duration(milliseconds: 190);
  static const push = Duration(milliseconds: 270);
  static const pop = Duration(milliseconds: 230);
  static const overlay = Duration(milliseconds: 190);
  static const tabOut = Duration(milliseconds: 110);
  static const tabIn = Duration(milliseconds: 230);
  static const tabDelay = Duration(milliseconds: 55);
  static const sheet = Duration(milliseconds: 250);
  static const hero = Duration(milliseconds: 300);
  static const breath = Duration(milliseconds: 1250);

  static const enter = Cubic(0.2, 0.0, 0.0, 1.0);
  static const exit = Cubic(0.3, 0.0, 1.0, 1.0);
  static const emphasized = Curves.easeOutCubic;
  static const spring = SpringDescription(mass: 1, stiffness: 260, damping: 28);

  static const incomingTravel = 0.16;
}

/// A sheet that behaves like a panel of the page behind it: the page is not pushed anywhere.
Future<T?> showInfSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: InfChrome.of(context).sheetMotion ??
        const AnimationStyle(
          duration: InfMotion.sheet,
          reverseDuration: Duration(milliseconds: 190),
          curve: InfMotion.enter,
          reverseCurve: InfMotion.exit,
        ),
    builder: (context) => builder(context),
  );
}

/// A sheet of actions or a picker, with a drag handle. Under glass it is frosted over the page
/// unless [frosted] is false, which keeps it solid in every style.
Future<T?> showActionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  Color? backgroundColor,
  bool frosted = true,
}) {
  final style = InfChrome.of(context);
  final chrome = frosted ? style : const ClassicChrome();
  final own = chrome.drawsActionSheet;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: !own,
    backgroundColor: own ? Colors.transparent : backgroundColor,
    elevation: own ? 0 : null,
    sheetAnimationStyle: style.sheetMotion,
    builder: (context) => chrome.actionSheet(context, child: builder(context)),
  );
}

/// Runs [action] once the route is on screen; used by the shared-element pages.
void afterFrame(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}