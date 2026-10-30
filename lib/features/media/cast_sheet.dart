import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cast.dart';
import '../../core/haptics.dart';
import '../../core/widgets/common.dart';

Future<void> showCastSheet(BuildContext context, String videoUrl) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _CastSheet(videoUrl: videoUrl),
  );
}

class _CastSheet extends StatefulWidget {
  const _CastSheet({required this.videoUrl});

  final String videoUrl;

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  List<CastDevice> _devices = const [];
  bool _loading = true;
  String? _error;
  String? _casting;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await DlnaCast.discover();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '搜索失败，请确认手机和电视在同一 Wi-Fi';
      });
    }
  }

  Future<void> _cast(CastDevice device) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _casting = device.controlUrl);
    try {
      await DlnaCast.play(device, widget.videoUrl);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('已发送到 ' + device.name)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _casting = null);
      showMessage(context, '投屏失败，电视可能不支持该视频地址');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.videoUrl));
    Haptic.success.play();
    if (!mounted) return;
    showMessage(context, '视频链接已复制');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                Icon(Icons.cast_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('投屏到电视', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: _loading ? null : _scan,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '重新搜索',
                ),
                IconButton(
                  onPressed: _copyLink,
                  icon: const Icon(Icons.link_rounded),
                  tooltip: '复制视频链接',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '搜索同一 Wi-Fi 下支持 DLNA 的电视或盒子',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          const Divider(height: 1),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 42),
              child: Column(
                children: [
                  SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
                  SizedBox(height: 14),
                  Text('正在搜索附近的电视…'),
                ],
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            )
          else if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
              child: Column(
                children: [
                  Icon(Icons.tv_off_rounded, size: 36, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 10),
                  const Text('没有找到支持 DLNA 的设备'),
                  const SizedBox(height: 6),
                  Text(
                    '确认电视已开机、和手机在同一 Wi-Fi；也可以复制链接后在大屏浏览器打开。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _copyLink,
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text('复制视频链接'),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  final casting = _casting == device.controlUrl;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: const Icon(Icons.tv_rounded),
                    ),
                    title: Text(device.name),
                    subtitle: Text(device.location, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: casting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: _casting == null ? () => _cast(device) : null,
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}
