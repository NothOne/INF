import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/native.dart';
import '../../core/navigation.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/smart_image.dart';

/// A place a post was sent from, from what the post itself carries: Weibo's place page needs a
/// login and only loads on some devices, so this sheet never depends on it.
Future<void> showPlaceSheet(BuildContext context, Place place) {
  return showActionSheet<void>(
    context: context,
    builder: (sheetContext) => _PlaceSheet(place: place, host: context),
  );
}

class _PlaceSheet extends StatelessWidget {
  const _PlaceSheet({required this.place, required this.host});

  final Place place;

  /// The page the sheet was opened from; pages opened from the sheet are pushed from there.
  final BuildContext host;

  String get _query => place.address ?? place.name;

  Future<void> _navigate(BuildContext context) async {
    Navigator.of(context).pop();
    final query = Uri.encodeComponent(_query);
    if (await Native.openUrl('geo:0,0?q=$query')) return;
    if (host.mounted) await openWeb(host, 'https://uri.amap.com/search?keyword=$query');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final picture = place.picUrl;
    final url = place.url;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: picture == null
                        ? ColoredBox(
                            color: scheme.primaryContainer,
                            child: Icon(Icons.place_rounded, color: scheme.onPrimaryContainer),
                          )
                        : SmartImage(url: picture, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (place.summary != null) ...[
                        const SizedBox(height: 3),
                        Text(place.summary!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (place.address != null) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.place_outlined, size: 17, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: SelectableText(place.address!, style: text.bodyMedium)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: place.address ?? place.name));
                      Haptic.success.play();
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      if (host.mounted) showMessage(host, place.address == null ? '地点已复制' : '地址已复制');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(place.address == null ? '复制地点' : '复制地址'),
                  ),
                ),
                if (url != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (host.mounted) openWeb(host, url);
                      },
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text('地点详情'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _navigate(context),
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('用地图导航'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
