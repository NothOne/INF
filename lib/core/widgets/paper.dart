import 'package:flutter/material.dart';

import '../chrome.dart';

/// What every page is laid on, drawn by the current style ([InfChrome.backdrop]).
class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => InfChrome.of(context).backdrop(context, child: child);
}
