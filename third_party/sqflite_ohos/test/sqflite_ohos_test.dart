// Copyright (c) 2025 Huawei Device Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_HW file.
// Based on Camera.java originally written by
// Copyright 2013 The Flutter Authors.

// Unit tests for the `SqfliteOhos` plugin registration entry point.
//
// `SqfliteOhos.registerWith()` is the only public API of this package: it
// installs the method-channel based `SqflitePlatform` implementation as the
// default sqflite `databaseFactory`. These tests cover the normal, edge,
// concurrent and error scenarios of the registration behavior using the mock
// method channel machinery provided by flutter_test.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqflite.dart' show databaseFactory, databaseFactoryOrNull;
import 'package:sqflite_common/sqlite_api.dart' show DatabaseException, DatabaseFactory;
import 'package:sqflite_ohos/sqflite_ohos.dart';
import 'package:sqflite_platform_interface/sqflite_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every sqflite dart call is routed through this method channel.
  const channel = MethodChannel('com.tekartik.sqflite');

  group('SqfliteOhos.registerWith', () {
    setUp(() {
      // Start each test from a clean, unregistered state.
      databaseFactoryOrNull = null;
    });

    tearDown(() {
      // Leave the global factory unregistered and drop the channel mock so
      // that other test suites are not affected.
      databaseFactoryOrNull = null;
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    group('normal scenarios', () {
      test('should register the method channel factory as the default one',
          () {
        expect(databaseFactoryOrNull, isNull,
            reason: 'no factory should be set before registration');
        SqfliteOhos.registerWith();
        expect(
            databaseFactoryOrNull, same(SqflitePlatform.databaseFactoryMethodChannel));
      });

      test('should make the global databaseFactory getter usable', () {
        SqfliteOhos.registerWith();
        expect(databaseFactory, same(databaseFactoryOrNull));
      });

      test('should route calls through the sqflite method channel', () async {
        const expectedPath = '/data/app/el2/100/database';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
          expect(call.method, 'getDatabasesPath');
          return expectedPath;
        });
        SqfliteOhos.registerWith();
        expect(await databaseFactory.getDatabasesPath(), expectedPath);
      });
    });

    group('edge scenarios', () {
      test('should be idempotent when called repeatedly', () {
        SqfliteOhos.registerWith();
        final first = databaseFactoryOrNull;
        SqfliteOhos.registerWith();
        SqfliteOhos.registerWith();
        expect(databaseFactoryOrNull, same(first),
            reason: 'an already registered factory must not be replaced');
      });

      test('should register the exact same factory instance every time', () {
        SqfliteOhos.registerWith();
        expect(databaseFactoryOrNull,
            same(SqflitePlatform.databaseFactoryMethodChannel));
      });
    });

    group('concurrent scenarios', () {
      test('should stay safe when registering from concurrent futures',
          () async {
        final registered = <DatabaseFactory?>[];
        await Future.wait(List.generate(20, (_) {
          return Future(() {
            SqfliteOhos.registerWith();
            registered.add(databaseFactoryOrNull);
          });
        }));
        expect(registered, isNotEmpty);
        expect(registered.every((factory) => factory == registered.first), isTrue,
            reason: 'a single factory instance must be registered');
        expect(
            databaseFactoryOrNull, same(SqflitePlatform.databaseFactoryMethodChannel));
      });
    });

    group('error scenarios', () {
      test('should keep databaseFactory throwing before registration', () {
        expect(() => databaseFactory, throwsStateError);
      });

      test('should wrap native sqlite errors into DatabaseException',
          () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(
              code: 'sqlite_error', message: 'unable to open database file');
        });
        SqfliteOhos.registerWith();
        await expectLater(databaseFactory.databaseExists('missing.db'),
            throwsA(isA<DatabaseException>()));
      });
    });
  });
}
