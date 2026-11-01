import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/share.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/status_card.dart';

class LongImagePage extends StatefulWidget {
  const LongImagePage({super.key, required this.status});

  final Status status;

  @override
  State<LongImagePage> createState() => _LongImagePageState();
}

class _LongImagePageState extends State<LongImagePage> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _capturing = false;

  Future<void> _share() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('no boundary');
      final image = await boundary.toImage(pixelRatio: 2.2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('no png');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/inf-long-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      await shareFile(file.path, mime: 'image/png');
    } catch (_) {
      if (mounted) showMessage(context, '长图生成失败');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(title: const Text('生成长图'), flexibleSpace: lookBarBackground(context)),
      body: Column(
        children: [
          Expanded(
            child: Builder(
              builder: (context) => SingleChildScrollView(
                padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: ColoredBox(
                    color: scheme.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        StatusCard(
                          status: widget.status,
                          detail: true,
                          onOpenStatus: (_) {},
                          onOpenUser: (_) {},
                          onOpenTopic: (_) {},
                          onOpenUrl: (_) {},
                          onOpenMedia: (a, b, c) {},
                          enableImageHeroes: false,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                          child: Row(
                            children: [
                              const InfLogo(height: 13),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '长图由 INF 生成 · https://m.weibo.cn/detail/${widget.status.id}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    height: 1.3,
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _capturing ? null : _share,
                    icon: _capturing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(_capturing ? '正在生成…' : '生成并分享'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}