import 'package:flutter/services.dart';

/// Bridge to the tiny native layer in MainActivity: the WebView cookie store, its user agent, and
/// the display's peak refresh rate.
class Native {
  static const MethodChannel _channel = MethodChannel('app.inf.flutter/native');

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

  static Future<String?> saveVideoToGallery(String path, String name) async {
    try {
      return await _channel.invokeMethod<String>('saveVideo', {'path': path, 'name': name}).timeout(
            const Duration(seconds: 60),
          );
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

  static Future<void> requestPeakRefreshRate() async {
    try {
      await _channel.invokeMethod<double>('peakRefreshRate').timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}
  }
}