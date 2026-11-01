import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/version.dart';

void main() {
  test('the version is the same in pubspec, HarmonyOS and the app', () {
    final pubspec = RegExp(r'^version:\s*([\d.]+)\+(\d+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!;
    final ohos = File('ohos/AppScope/app.json5').readAsStringSync();
    expect(pubspec.group(1), appVersion);
    expect(RegExp(r'"versionName":\s*"([^"]+)"').firstMatch(ohos)!.group(1), appVersion);
    expect(RegExp(r'"versionCode":\s*(\d+)').firstMatch(ohos)!.group(1), pubspec.group(2));
  });
}
