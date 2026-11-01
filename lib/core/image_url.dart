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
