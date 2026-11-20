/// Reading one scalar out of Weibo's JSON.
///
/// Every parser in the app does this, and it is the part that has to be lenient: the same field
/// comes back as a number in one answer and a string in the next, `"1"` for a boolean, `"12.3万"`
/// for a count. These are the only place that leniency lives; a parser reads a field and gets a
/// `String?` or a 0, never a cast.
library;

class WeiboEnvelope {
  final int ok;
  final dynamic data;
  final int? errno;
  final String? message;
  final String? loginUrl;

  const WeiboEnvelope({required this.ok, this.data, this.errno, this.message, this.loginUrl});

  bool get isOk => ok == 1;
  bool get needsLogin => ok == -100;
}

WeiboEnvelope parseWeiboResult(dynamic root) {
  if (root is! Map) return const WeiboEnvelope(ok: 0);
  return WeiboEnvelope(
    ok: intOf(root['ok']) ?? 0,
    data: root['data'],
    errno: intOf(root['errno']),
    message: textOf(root['msg']),
    loginUrl: textOf(root['url']),
  );
}

Map<String, dynamic>? asMap(dynamic value) =>
    value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : null;

List<dynamic> asList(dynamic value) => value is List ? value : const [];

String? textOf(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }
  if (value is num) return value.toString();
  return null;
}

String? idOf(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is int) return value.toString();
  if (value is double) return value.isFinite ? value.toStringAsFixed(0) : null;
  return null;
}

int? intOf(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) {
    final trimmed = value.trim().replaceAll(',', '');
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.toInt();
  }
  return null;
}

bool boolOf(dynamic value) => value == true || value == 1 || value == '1' || value == 'true';

double? doubleOf(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

/// A count, which Weibo writes as `12`, `"12"`, `"12.3万"` or `"1.2亿"`. Missing is 0.
int countOf(dynamic value) {
  if (value == null || value is bool) return 0;
  if (value is num) return value.toInt();
  final text = value.toString().trim().replaceAll(',', '');
  if (text.isEmpty) return 0;
  final match = RegExp(r'^([+-]?\d+(?:\.\d+)?)\s*(万|亿)\+?$').firstMatch(text);
  if (match != null) {
    final number = double.tryParse(match.group(1)!) ?? 0;
    final multiplier = match.group(2) == '亿' ? 100000000 : 10000;
    return (number * multiplier).round();
  }
  return int.tryParse(text) ?? double.tryParse(text)?.toInt() ?? 0;
}
