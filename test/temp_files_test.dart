import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/temp_files.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);

  final Directory root;

  @override
  Future<String?> getTemporaryPath() async => '${root.path}/cache';

  @override
  Future<String?> getApplicationDocumentsPath() async => '${root.path}/documents';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('inf-temp-test');
    await Directory('${root.path}/cache').create(recursive: true);
    await Directory('${root.path}/documents').create(recursive: true);
    PathProviderPlatform.instance = _Paths(root);
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('TempFiles', () {
    test('what a share wrote is gone once the caller is done with it', () async {
      final file = await TempFiles.file('INF-1.jpg');
      await file.writeAsBytes([1, 2, 3]);
      expect(await TempFiles.size(), 3);

      await TempFiles.delete(file.path);
      expect(await file.exists(), isFalse);
      expect(await TempFiles.size(), 0);
    });

    test('a sweep takes what earlier builds dropped loose in the cache directory', () async {
      final support = File('${root.path}/cache/INF-123-0.jpg');
      final longImage = File('${root.path}/cache/inf-long-123.png');
      final chat = File('${root.path}/cache/chat-123.jpg');
      final old = DateTime.now().subtract(const Duration(days: 2));
      for (final file in [support, longImage, chat]) {
        await file.writeAsBytes([0]);
        await file.setLastModified(old);
      }
      // Not ours: another package's cache folder, and a file with no marker of ours.
      final other = File('${root.path}/cache/other.tmp');
      await other.writeAsBytes([0]);
      // Ours, but written this session: a share may still be reading it.
      final fresh = File('${root.path}/cache/INF-456-0.jpg');
      await fresh.writeAsBytes([0]);

      await TempFiles.sweep();
      expect(await support.exists(), isFalse);
      expect(await longImage.exists(), isFalse);
      expect(await chat.exists(), isFalse);
      expect(await other.exists(), isTrue);
      expect(await fresh.exists(), isTrue);
    });

    test('a sweep keeps this run\'s files until they are a day old', () async {
      final fresh = await TempFiles.file('INF-fresh.jpg');
      await fresh.writeAsBytes([0]);
      final stale = await TempFiles.file('INF-stale.jpg');
      await stale.writeAsBytes([0]);
      await stale.setLastModified(DateTime.now().subtract(const Duration(days: 2)));

      // A share sheet in another app may still be reading the fresh one.
      await TempFiles.sweep();
      expect(await fresh.exists(), isTrue);
      expect(await stale.exists(), isFalse);
    });

    test('clearing takes the whole scratch folder', () async {
      await (await TempFiles.file('a.jpg')).writeAsBytes([0]);
      await (await TempFiles.file('b.mp4')).writeAsBytes([0]);
      await TempFiles.clear();
      expect(await TempFiles.size(), 0);
    });
  });

  group('DraftFiles', () {
    Future<File> picked(String name) async {
      final file = File('${root.path}/$name');
      await file.writeAsBytes([7]);
      return file;
    }

    test('a picture goes in the documents folder, so a draft outlives the cache', () async {
      final path = await DraftFiles.add(await picked('picked.jpg'));
      expect(path, startsWith('${root.path}/documents/drafts/'));
      expect(await File(path).exists(), isTrue);
    });

    test('a sweep takes the pictures no draft mentions', () async {
      final kept = await DraftFiles.add(await picked('kept.jpg'));
      final orphan = await DraftFiles.add(await picked('orphan.jpg'));
      await Prefs.instance.saveDrafts([
        Draft(
          id: 1,
          type: DraftType.original,
          text: 'hi',
          images: [kept],
          crossPost: false,
          state: DraftState.editing,
          updatedAt: DateTime.now(),
        ),
      ]);

      await DraftFiles.sweep();
      expect(await File(kept).exists(), isTrue);
      expect(await File(orphan).exists(), isFalse);
    });

    test('deleting a draft\'s pictures takes exactly those files', () async {
      final first = await DraftFiles.add(await picked('one.jpg'));
      final second = await DraftFiles.add(await picked('two.jpg'));
      await DraftFiles.delete([first]);
      expect(await File(first).exists(), isFalse);
      expect(await File(second).exists(), isTrue);
    });
  });
}
