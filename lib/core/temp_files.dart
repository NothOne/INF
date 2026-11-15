import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'prefs.dart';

/// The files this app writes and then has to clean up after: a copy on its way to the gallery or
/// the share sheet, a video being downloaded, a long screenshot, a chat picture about to be
/// uploaded, and the pictures attached to a draft.
///
/// They used to be written straight into the cache directory and left there. Nothing ever removed
/// them — Android only clears an app's cache under storage pressure, which on a phone with room to
/// spare means never — so they piled up alongside the pictures. Everything now goes into one
/// folder, and [sweep] empties it of yesterday's leftovers on every start.
class TempFiles {
  TempFiles._();

  /// Everything this class hands out lives here, so a sweep can take the lot without matching on
  /// the names each caller makes up.
  static const folder = 'inf-temp';

  /// What builds before this class dropped in the cache directory itself.
  static const _legacy = ['INF-', 'inf-long-', 'chat-'];

  static Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/$folder');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// A file in the scratch folder for the caller to write.
  static Future<File> file(String name) async => File('${(await _dir()).path}/$name');

  static Future<int> size() async {
    final dir = await _dir();
    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  static Future<void> clear() async {
    final dir = await _dir();
    await for (final entity in dir.list(followLinks: false)) {
      await entity.delete(recursive: true);
    }
  }

  /// Removes one scratch file once whatever it was made for has taken it.
  static Future<void> delete(String path) => _delete(File(path));

  /// Deletes what earlier builds left loose in the cache directory, and this build's leftovers
  /// older than [age]. A share another app is still reading is done with well before a day is up.
  static Future<void> sweep({Duration age = const Duration(hours: 24)}) async {
    final base = await getTemporaryDirectory();
    final cutoff = DateTime.now().subtract(age);
    // The files an earlier build wrote carry their own names and no folder of ours, so they are
    // matched by prefix; they are also old enough that nothing is still holding them.
    await for (final entity in base.list(followLinks: false)) {
      if (entity is! File || !_legacy.any(entity.uri.pathSegments.last.startsWith)) continue;
      if ((await entity.lastModified()).isBefore(cutoff)) await _delete(entity);
    }
    final dir = await _dir();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && (await entity.lastModified()).isBefore(cutoff)) await _delete(entity);
    }
  }
}

/// A draft's pictures: copied out of the picker into the app's documents, because a draft has to
/// outlive the system clearing its cache. Nothing used to delete them either, so a draft that was
/// sent or thrown away left its pictures on the device; [sweep] compares the folder with the drafts
/// that still exist and takes the rest.
class DraftFiles {
  DraftFiles._();

  static const _folder = 'drafts';

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_folder');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies a picked picture in and returns its new path.
  static Future<String> add(File picked) async {
    final dir = await _dir();
    final target = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}-${picked.uri.pathSegments.last}';
    await picked.copy(target);
    return target;
  }

  static Future<void> delete(Iterable<String> paths) async {
    for (final path in paths) {
      await _delete(File(path));
    }
  }

  static Future<int> size() async {
    final dir = await _dir();
    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Everything in the folder no draft mentions any more.
  static Future<void> sweep() async {
    final kept = {for (final draft in Prefs.instance.drafts) ...draft.images};
    final dir = await _dir();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && !kept.contains(entity.path)) await _delete(entity);
    }
  }
}

Future<void> _delete(FileSystemEntity entity) async {
  try {
    await entity.delete();
  } on FileSystemException {
    // Already gone, or being read by another app; the next sweep sees it again.
  }
}
