import 'session.dart';

String sanitizeImageUrl(String? value) {
  if (value == null) return '';
  var url = value.trim();
  if (url.startsWith('//')) url = 'https:' + url;
  if (url.startsWith('http://')) url = 'https://' + url.substring(7);
  return url;
}

Map<String, String> weiboImageHeaders() => {
      'Referer': 'https://m.weibo.cn/',
      'User-Agent': Session.instance.userAgent,
    };

final RegExp _sinaimg = RegExp(r'^(https://[^/]*sinaimg\.cn/)([A-Za-z0-9_.]+)/([^/]+)$');

/// sinaimg serves every picture at a handful of sizes named by the first path segment
/// (`orj360`, `mw690`, `large`, …). Returns [url] unchanged when it is not such a URL.
String sinaimgSized(String url, String size) {
  final clean = sanitizeImageUrl(url);
  final match = _sinaimg.firstMatch(clean);
  if (match == null) return clean;
  return match.group(1)! + size + '/' + match.group(3)!;
}
