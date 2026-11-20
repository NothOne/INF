import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture guardrails derived from `AGENTS.md` and `CODE_MAP.md`.
///
/// Keeps hard layer boundaries, single-owner conventions (retry footer, page caching, image cache),
/// scoped listener discipline, and native MethodChannel parity enforced automatically on every test
/// run instead of relying on code review memory.
void main() {
  final libFiles = [
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));

  final sources = {for (final file in libFiles) file.path: file.readAsStringSync()};
  final importPattern = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

  String? resolveImport(String fromLibRel, String spec) {
    if (spec.startsWith('dart:')) return null;
    if (spec.startsWith('package:')) {
      if (!spec.startsWith('package:inf_flutter/')) return null;
      return spec.substring('package:inf_flutter/'.length);
    }
    final dir = File(fromLibRel).parent.path;
    final combined = dir == '.' ? spec : '$dir/$spec';
    final segments = <String>[];
    for (final seg in combined.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(seg);
      }
    }
    return segments.join('/');
  }

  test('layer rule: only core/navigation.dart may import features/*', () {
    final violations = <String>[];
    for (final entry in sources.entries) {
      final rel = entry.key.substring('lib/'.length);
      if (!rel.startsWith('core/') || rel == 'core/navigation.dart') continue;
      for (final match in importPattern.allMatches(entry.value)) {
        final dst = resolveImport(rel, match.group(1)!);
        if (dst != null && dst.startsWith('features/')) {
          violations.add('$rel -> $dst');
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('layer rule: features do not import each other (except shell/)', () {
    final violations = <String>[];
    for (final entry in sources.entries) {
      final rel = entry.key.substring('lib/'.length);
      if (!rel.startsWith('features/')) continue;
      final srcFeature = rel.split('/')[1];
      if (srcFeature == 'shell') continue;
      for (final match in importPattern.allMatches(entry.value)) {
        final dst = resolveImport(rel, match.group(1)!);
        if (dst != null && dst.startsWith('features/')) {
          final dstFeature = dst.split('/')[1];
          if (dstFeature != srcFeature) {
            violations.add('$rel -> $dst');
          }
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('retry rule: footer buttons call retryMore via PagerTail, never loadMore directly', () {
    final violations = <String>[];
    final badRetry = RegExp(r'onPressed:\s*[A-Za-z0-9_]+\.loadMore\b');
    for (final entry in sources.entries) {
      if (badRetry.hasMatch(entry.value)) {
        violations.add(entry.key);
      }
    }
    expect(violations, isEmpty, reason: 'loadMore is blocked after failure; use PagerTail(pager)');
  });

  test('caching rule: API files go through CachedPage/CachedValue, not PageCache directly', () {
    final violations = <String>[];
    for (final entry in sources.entries) {
      final name = entry.key.split('/').last;
      if (!entry.key.startsWith('lib/core/')) continue;
      if (name != 'api.dart' && !name.startsWith('api_')) continue;
      if (entry.value.contains('PageCache.instance')) {
        violations.add(entry.key);
      }
    }
    expect(violations, isEmpty);
  });

  test('image cache rule: DefaultCacheManager is never constructed in lib/', () {
    final violations = <String>[
      for (final entry in sources.entries)
        if (entry.value.contains('DefaultCacheManager(')) entry.key,
    ];
    expect(violations, isEmpty);
  });

  test('scoped listener rule: lists do not subscribe to whole StatusStore or whole Prefs', () {
    final wholeStatusStore = RegExp(r'(?:animation:\s*|Listenable\.merge\([^\)]*)StatusStore\.instance(?![\.\w])');
    final statusViolations = <String>[];
    for (final entry in sources.entries) {
      if (wholeStatusStore.hasMatch(entry.value)) statusViolations.add(entry.key);
    }
    expect(statusViolations, isEmpty, reason: 'use StatusStore.instance.of([...]) instead of listening to whole store');

    for (final path in ['lib/core/widgets/paged_status_list.dart', 'lib/features/feed/feed_page.dart']) {
      final wholePrefs = RegExp(r'(?:animation:\s*|Listenable\.merge\([^\)]*)Prefs\.instance(?![\.\w])');
      expect(wholePrefs.hasMatch(sources[path]!), isFalse,
          reason: '$path should subscribe to scoped Prefs notifiers, not whole Prefs.instance');
    }
  });

  test('native channel rule: Dart methods exist on both Android and HarmonyOS', () {
    final dartSource = File('lib/core/native.dart').readAsStringSync();
    final dartMethods = {
      for (final match in RegExp(r"invokeMethod(?:<[^>]+>)?\('([^']+)'").allMatches(dartSource)) match.group(1)!,
    };
    final ktSource = File('android/app/src/main/kotlin/app/inf/flutter/MainActivity.kt').readAsStringSync();
    final ktMethods = {
      for (final match in RegExp(r'"([a-zA-Z0-9_]+)"\s*->').allMatches(ktSource)) match.group(1)!,
    };
    final etsSource = File('ohos/entry/src/main/ets/plugins/NativePlugin.ets').readAsStringSync();
    final etsMethods = {
      for (final match in RegExp(r"case\s+'([a-zA-Z0-9_]+)'\s*:").allMatches(etsSource)) match.group(1)!,
    };

    expect(dartMethods.difference(ktMethods), isEmpty, reason: 'missing Android MethodChannel handlers');
    expect(dartMethods.difference(etsMethods), isEmpty, reason: 'missing HarmonyOS MethodChannel handlers');
  });

  test('network rule: features do not instantiate Dio directly', () {
    final violations = <String>[
      for (final entry in sources.entries)
        if (entry.key.startsWith('lib/features/') && RegExp(r'\bDio\(').hasMatch(entry.value)) entry.key,
    ];
    expect(violations, isEmpty, reason: 'use WeiboApi / GroupChatApi so headers and Cookie isolation stay centralized');
  });

  test('error rule: lib/ never formats errors with error.toString()', () {
    final violations = <String>[];
    for (final entry in sources.entries) {
      for (final line in entry.value.split('\n')) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (line.contains('error.toString()')) {
          violations.add(entry.key);
          break;
        }
      }
    }
    expect(violations, isEmpty, reason: 'use Failure.from(error).message or friendlyError(error)');
  });

  test('error rule: ErrorView receives raw Object? errors, not pre-stringified String? fields', () {
    final violations = <String>[];
    final errorViewField = RegExp(r'ErrorView\([^)]*error:\s*(_[A-Za-z0-9_]+)');
    for (final entry in sources.entries) {
      for (final match in errorViewField.allMatches(entry.value)) {
        final field = match.group(1)!;
        if (RegExp('String\\?\\s+$field\\b').hasMatch(entry.value)) {
          violations.add('${entry.key}: $field');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'stringifying an exception before ErrorView turns it into BusinessFailure and hides Retry/Login');
  });
}
