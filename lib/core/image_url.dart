import 'session.dart';

String sanitizeImageUrl(String? value) => secureUrl(value);

/// Android refuses cleartext HTTP in the WebView and the video player, and the API still hands
/// out `http://` links and video URLs whose hosts all answer on HTTPS.
String secureUrl(String? value) {
  if (value == null) return '';
  var url = value.trim();
  if (url.startsWith('//')) url = 'https:' + url;
  if (url.toLowerCase().startsWith('http://')) url = 'https://' + url.substring(7);
  return url;
}

/// Weibo's video CDN signs each address with an `Expires` time (Unix seconds); past it the CDN
/// answers 403. Unsigned addresses never expire.
bool signedUrlExpired(String url, DateTime now) {
  final expires = int.tryParse(Uri.tryParse(url)?.queryParameters['Expires'] ?? '');
  return expires != null && expires * 1000 <= now.millisecondsSinceEpoch;
}

/// sinaimg wants Weibo as the referrer; other sites' covers in link cards (Bilibili's hdslb.com)
/// refuse exactly that one, so they get none.
Map<String, String> weiboImageHeaders([String? url]) {
  final host = url == null ? null : Uri.tryParse(sanitizeImageUrl(url))?.host.toLowerCase();
  final weibo = host == null || host.endsWith('sinaimg.cn') || host.endsWith('weibo.com') || host.endsWith('weibo.cn');
  return {
    if (weibo) 'Referer': 'https://m.weibo.cn/',
    'User-Agent': Session.instance.userAgent,
  };
}

final RegExp _sinaimg = RegExp(r'^(https://[^/]*sinaimg\.cn/)([A-Za-z0-9_.]+)/([^/]+)$');

/// sinaimg serves every picture at a handful of sizes named by the first path segment
/// (`orj360`, `mw690`, `large`, …). Returns [url] unchanged when it is not such a URL.
String sinaimgSized(String url, String size) {
  final clean = sanitizeImageUrl(url);
  final match = _sinaimg.firstMatch(clean);
  if (match == null) return clean;
  return match.group(1)! + size + '/' + match.group(3)!;
}

final RegExp _avatarCrop = RegExp(r'(/crop\.\d+\.\d+\.\d+\.\d+)\.\d+/');
final RegExp _avatarSize = RegExp(r'(sinaimg\.cn)/(orj|thumb|mw)\d+/');

/// An avatar at its full size: the crop's last number is the size it is drawn at, and 1024 is
/// the largest; the signature in the query does not cover it.
String avatarLarge(String url) => _avatarCrop.hasMatch(url)
    ? url.replaceFirstMapped(_avatarCrop, (m) => '${m[1]}.1024/')
    : url.replaceFirstMapped(_avatarSize, (m) => '${m[1]}/large/');
