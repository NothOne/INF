import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'image_url.dart';
import 'models.dart';
import 'native.dart';

/// From the file's first bytes: the URL says `.jpg` for GIFs too.
Future<({String extension, String mime})> imageTypeOf(File file) async {
  final handle = await file.open();
  final head = await handle.read(12);
  await handle.close();
  return imageTypeOfBytes(head);
}

({String extension, String mime}) imageTypeOfBytes(List<int> head) {
  bool starts(List<int> magic, [int at = 0]) {
    if (head.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (head[at + i] != magic[i]) return false;
    }
    return true;
  }

  if (starts([0x89, 0x50, 0x4E, 0x47])) return (extension: '.png', mime: 'image/png');
  if (starts([0x47, 0x49, 0x46, 0x38])) return (extension: '.gif', mime: 'image/gif');
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
    return (extension: '.webp', mime: 'image/webp');
  }
  return (extension: '.jpg', mime: 'image/jpeg');
}

int _serial = 0;

/// A file name no other save in this run takes, even within the same millisecond.
String exportName(String extension) => 'INF-${DateTime.now().millisecondsSinceEpoch}-${_serial++}$extension';

/// The picture at [url] as a file other apps can take. sinaimg refuses requests without a Weibo
/// Referer, so this hands over the bytes, usually straight from the cache the app has drawn from.
Future<({String path, String name, String mime})> exportImage(String url) async {
  final cached = await DefaultCacheManager().getSingleFile(sanitizeImageUrl(url), headers: weiboImageHeaders());
  final type = await imageTypeOf(cached);
  final name = exportName(type.extension);
  final path = '${(await getTemporaryDirectory()).path}/$name';
  await cached.copy(path);
  return (path: path, name: name, mime: type.mime);
}

/// How a batch save went: [live] of the [saved] went in as live photos, [stills] live photos only
/// as their still picture.
typedef SaveAllResult = ({int saved, int live, int stills});

/// Saves [images] to the gallery one after another, a live photo as a Motion Photo (its still
/// only when the clip cannot be had or joined); [onProgress] hears how many are done. On
/// HarmonyOS each one asks the reader, and live photos save as stills there.
Future<SaveAllResult> saveImagesToGallery(List<Media> images, {void Function(int done, int total)? onProgress}) async {
  var saved = 0, live = 0, stills = 0;
  for (var i = 0; i < images.length; i++) {
    final image = images[i];
    try {
      final file = await exportImage(sinaimgSized(image.url, 'large'));
      String? result;
      if (image.isLive) {
        try {
          final clip = await DefaultCacheManager().getSingleFile(sanitizeImageUrl(image.liveUrl!), headers: weiboImageHeaders());
          result = await Native.saveMotionPhoto(file.path, clip.path, file.name.replaceFirst(RegExp(r'\.\w+$'), '.jpg'));
        } catch (_) {}
        if (result != null) live++;
      }
      if (result == null) {
        result = await Native.saveImageToGallery(file.path, file.name, mime: file.mime);
        if (result != null && image.isLive) stills++;
      }
      if (result != null) saved++;
    } catch (_) {}
    onProgress?.call(i + 1, images.length);
  }
  return (saved: saved, live: live, stills: stills);
}

/// What to say once [saveImagesToGallery] is done with [total] pictures.
String saveAllMessage(SaveAllResult result, int total) {
  final parts = [
    result.saved == total ? '已保存全部 $total 张' : '已保存 ${result.saved} / $total 张',
    if (result.live > 0) '其中 ${result.live} 张实况',
    if (result.stills > 0) '${result.stills} 张实况只存了静态图',
  ];
  return parts.join('，');
}

/// The save-all menu entry: says how many are live, as those save as live photos.
String saveAllLabel(List<Media> images) {
  final live = images.where((image) => image.isLive).length;
  if (images.length == 1) return live == 1 ? '保存实况照片' : '保存图片';
  return live == 0 ? '保存全部图片（${images.length} 张）' : '保存全部（${images.length} 张，含 $live 张实况）';
}
