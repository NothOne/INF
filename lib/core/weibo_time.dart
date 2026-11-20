/// How a timestamp and a count are written for people to read.
///
/// Time arrives in at least five shapes from the two sites — an epoch, an ISO string, 「3分钟前」,
/// 「今天 10:05」, and `Thu Nov 19 10:00:00 +0800 2026` — and it is parsed in exactly one place so a
/// new shape is one edit. The formatting side is here too, next to it, because the two are read
/// together whenever a list looks wrong.
library;

DateTime parseWeiboTime(String? raw, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final value = raw?.trim();
  if (value == null || value.isEmpty) return current;

  if (RegExp(r'^\d{10,13}$').hasMatch(value)) {
    final epoch = int.tryParse(value);
    if (epoch == null) return current;
    return value.length >= 13
        ? DateTime.fromMillisecondsSinceEpoch(epoch)
        : DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
  }

  final iso = DateTime.tryParse(value);
  if (iso != null) return iso.toLocal();

  final relative = RegExp(r'^(\d+)(秒|分钟|小时)前$').firstMatch(value);
  if (relative != null) {
    final amount = int.tryParse(relative.group(1)!) ?? 0;
    final unit = relative.group(2)!;
    final seconds = unit == '秒' ? amount : unit == '分钟' ? amount * 60 : amount * 3600;
    return current.subtract(Duration(seconds: seconds));
  }
  if (value == '刚刚') return current;

  final today = RegExp(r'^今天\s+(\d{2}):(\d{2})$').firstMatch(value);
  if (today != null) {
    return DateTime(current.year, current.month, current.day, int.parse(today.group(1)!), int.parse(today.group(2)!));
  }
  final yesterday = RegExp(r'^昨天\s+(\d{2}):(\d{2})$').firstMatch(value);
  if (yesterday != null) {
    final date = current.subtract(const Duration(days: 1));
    return DateTime(date.year, date.month, date.day, int.parse(yesterday.group(1)!), int.parse(yesterday.group(2)!));
  }

  final monthDay = RegExp(r'^(\d{2})-(\d{2})$').firstMatch(value);
  if (monthDay != null) {
    var date = DateTime(current.year, int.parse(monthDay.group(1)!), int.parse(monthDay.group(2)!));
    if (date.isAfter(current.add(const Duration(days: 1)))) {
      date = DateTime(current.year - 1, date.month, date.day);
    }
    return date;
  }

  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (dateOnly != null) {
    return DateTime(
      int.parse(dateOnly.group(1)!),
      int.parse(dateOnly.group(2)!),
      int.parse(dateOnly.group(3)!),
    );
  }

  final full = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(value);
  if (full != null) {
    return DateTime(
      int.parse(full.group(1)!),
      int.parse(full.group(2)!),
      int.parse(full.group(3)!),
      int.parse(full.group(4)!),
      int.parse(full.group(5)!),
      int.parse(full.group(6)!),
    );
  }

  final english = RegExp(
    r'^[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-])(\d{2})(\d{2})\s+(\d{4})$',
  ).firstMatch(value);
  if (english != null) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final month = months[english.group(1)!.toLowerCase()];
    if (month != null) {
      final offsetMinutes = int.parse(english.group(7)!) * 60 + int.parse(english.group(8)!);
      final sign = english.group(6) == '-' ? -1 : 1;
      final utc = DateTime.utc(
        int.parse(english.group(9)!),
        month,
        int.parse(english.group(2)!),
        int.parse(english.group(3)!),
        int.parse(english.group(4)!),
        int.parse(english.group(5)!),
      );
      return utc.subtract(Duration(minutes: sign * offsetMinutes)).toLocal();
    }
  }

  return current;
}

String relativeTime(DateTime instant, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final elapsed = current.difference(instant);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return '刚刚';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}分钟前';
  if (elapsed.inHours < 24) return '${elapsed.inHours}小时前';
  final date = instant.toLocal();
  final today = current.toLocal();
  final yesterday = today.subtract(const Duration(days: 1));
  if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
    return '昨天 ${_two(date.hour)}:${_two(date.minute)}';
  }
  if (date.year == today.year) return '${_two(date.month)}-${_two(date.day)}';
  return '${date.year}-${_two(date.month)}-${_two(date.day)}';
}

String compactCount(int n) {
  if (n < 10000) return n.clamp(0, 1 << 62).toString();
  if (n < 100000000) {
    final tenths = n ~/ 1000;
    final whole = tenths ~/ 10;
    final fraction = tenths % 10;
    return fraction == 0 ? '$whole万' : '$whole.$fraction万';
  }
  final tenths = n ~/ 10000000;
  final whole = tenths ~/ 10;
  final fraction = tenths % 10;
  return fraction == 0 ? '$whole亿' : '$whole.$fraction亿';
}

String _two(int value) => value.toString().padLeft(2, '0');
