import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the tiny native layer in MainActivity (on HarmonyOS, `NativePlugin.ets`): the WebView
/// cookie store, its user agent, and the display's peak refresh rate.
class Native {
  static const MethodChannel _channel = MethodChannel('app.inf.flutter/native');

  /// HarmonyOS NEXT, under the OpenHarmony Flutter fork. Compared by name so the stock SDK, whose
  /// `Platform` has no `isOhos`, still builds this file.
  static final bool isOhos = Platform.operatingSystem == 'ohos';

  /// The system share panel, for platforms share_plus does not cover. One of [text] or [path].
  static Future<void> share({String? text, String? path, String? mime}) =>
      _call('share', {'text': text, 'path': path, 'mime': mime});

  static Future<String> getCookies([String url = 'https://m.weibo.cn/']) async {
    try {
      final value = await _channel
          .invokeMethod<String>('getCookies', {'url': url})
          .timeout(const Duration(seconds: 2), onTimeout: () => '');
      return value ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> setCookie(String value, {String url = 'https://m.weibo.cn/'}) async {
    try {
      await _channel
          .invokeMethod<bool>('setCookie', {'url': url, 'value': value})
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}
  }

  static Future<void> clearCookies() async {
    try {
      await _channel.invokeMethod<bool>('clearCookies').timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}
  }

  /// Remove only the signed-in session cookies, keeping visitor/SSO cookies
  /// required by the Sina crossdomain login chain.
  static Future<void> clearAuthCookies() async {
    try {
      await _channel.invokeMethod<bool>('clearAuthCookies').timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}
  }

  static Future<String?> userAgent() async {
    try {
      return await _channel
          .invokeMethod<String>('userAgent')
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  /// Hands [url] to the system browser. False when nothing on the device can open it.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}).timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isPipAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isPipAvailable').timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enterPip({double aspectRatio = 16 / 9}) async {
    try {
      return await _channel.invokeMethod<bool>('enterPip', {'aspectRatio': aspectRatio}).timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// [remux] copies a QuickTime clip (a live photo's) into an MP4 first, which galleries expect.
  static Future<String?> saveVideoToGallery(String path, String name, {bool remux = false}) async {
    try {
      return await _channel.invokeMethod<String>('saveVideo', {'path': path, 'name': name, 'remux': remux}).timeout(
            const Duration(seconds: 60),
          );
    } catch (_) {
      return null;
    }
  }

  /// Saves a live photo as one Motion Photo JPEG with the clip embedded.
  static Future<String?> saveMotionPhoto(String image, String video, String name) async {
    try {
      return await _channel.invokeMethod<String>('saveMotionPhoto', {
        'image': image,
        'video': video,
        'name': name,
      }).timeout(const Duration(seconds: 60));
    } catch (_) {
      return null;
    }
  }

  static Future<String?> saveImageToGallery(String path, String name, {String mime = 'image/jpeg'}) async {
    try {
      return await _channel.invokeMethod<String>('saveImage', {
        'path': path,
        'name': name,
        'mime': mime,
      }).timeout(const Duration(seconds: 60));
    } catch (_) {
      return null;
    }
  }

  /// False only when the native side could not be reached; a disabled system haptics switch still
  /// counts as handled.
  static Future<bool> haptic(String kind) async {
    try {
      await _channel.invokeMethod<bool>('haptic', {'kind': kind});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Null when unknown; callers that save data should treat that as metered.
  static Future<bool?> isMeteredNetwork() async {
    try {
      return await _channel
          .invokeMethod<bool>('isMetered')
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  /// This window's brightness, 0–1, falling back to the system level when the window follows it.
  static Future<double?> brightness() => _number('brightness');

  /// [value] below 0 hands brightness back to the system.
  static Future<void> setBrightness(double value) => _call('setBrightness', {'value': value});

  /// Media volume, 0–1.
  static Future<double?> volume() => _number('volume');

  static Future<void> setVolume(double value) => _call('setVolume', {'value': value});

  static Future<void> keepScreenOn(bool on) => _call('keepScreenOn', {'on': on});

  static Future<double?> _number(String method) async {
    try {
      return await _channel.invokeMethod<double>(method).timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _call(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<bool>(method, arguments).timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}
  }

  static Future<void> requestPeakRefreshRate() async {
    try {
      await _channel.invokeMethod<double>('peakRefreshRate').timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}
  }
}