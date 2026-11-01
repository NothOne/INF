import 'dart:convert';

import 'links.dart';
import 'models.dart';

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

// ---------------------------------------------------------------------------------------------
// HTML text

String weiboHtmlToText(String html) => weiboHtmlToRichText(html).text;

/// The post's text, with each link's address standing in its place, and what m.weibo.cn drew for
/// those links: their own words (a place's name, a super topic, 抽奖详情) and kind.
({String text, Map<String, WeiboLink> links}) weiboHtmlToRichText(String html) {
  final links = <String, WeiboLink>{};
  final withoutAnchors = html.replaceAllMapped(_anchorRegex, (match) {
    final attributes = match.group(1) ?? '';
    final body = match.group(2) ?? '';
    final href = _attribute(attributes, 'href');
    final decodedHref = href == null ? null : decodeHtmlEntities(href);
    final visible = _htmlFragmentToText(body).trim();
    final labelMatch = _surlTextRegex.firstMatch(body);
    final label = labelMatch == null ? null : _htmlFragmentToText(labelMatch.group(1) ?? '').trim();
    final preferred = (label != null && label.isNotEmpty) ? label : visible;

    if (preferred == '全文') return '';
    if (decodedHref != null && _isMentionHref(decodedHref)) {
      if (preferred.startsWith('@')) return preferred;
      final name = _mentionName(decodedHref);
      return name == null ? preferred : '@$name';
    }
    final superTopic = decodedHref != null && _isSuperTopicHref(decodedHref);
    if (RegExp(r'#[^#\n]+#').hasMatch(preferred) || (decodedHref != null && _isTopicHref(decodedHref) && !superTopic)) {
      return preferred;
    }
    if (decodedHref != null) {
      final absolute = _resolveLink(decodedHref);
      if (absolute == null) return preferred;
      final resolved = _asciiUrl(absolute);
      final icon = RegExp(r'''<img\b[^>]*\bsrc\s*=\s*["']([^"']+)''', caseSensitive: false).firstMatch(body)?.group(1);
      final kind = linkKindOf(resolved, iconUrl: icon);
      final words = preferred == '网页链接' || preferred.startsWith('http') ? '' : preferred;
      links[resolved] = WeiboLink(url: resolved, label: words, kind: kind);
      return ' $resolved ';
    }
    return preferred;
  });
  final text = _htmlFragmentToText(withoutAnchors)
      .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
      .trim();
  return (text: text, links: links);
}

/// The text tokenizer ends a link at the first character outside URL ASCII, so a raw 肖战 or a
/// space in an href would cut it short.
String _asciiUrl(String url) {
  final buffer = StringBuffer();
  for (final rune in url.runes) {
    if (rune > 0x20 && rune < 0x7F && rune != 0x22 && rune != 0x3C && rune != 0x3E && rune != 0x5C &&
        rune != 0x5E && rune != 0x60 && rune != 0x7B && rune != 0x7C && rune != 0x7D) {
      buffer.writeCharCode(rune);
    } else {
      buffer.write(Uri.encodeComponent(String.fromCharCode(rune)));
    }
  }
  return buffer.toString();
}

bool _isSuperTopicHref(String href) {
  final normalized = href.toLowerCase();
  return normalized.contains('containerid=100808') ||
      normalized.contains('containerid%3d100808') ||
      normalized.contains('/p/100808');
}

String _htmlFragmentToText(String fragment) {
  final withBreaks = fragment.replaceAll(RegExp(r'<br\s*/?\s*>', caseSensitive: false), '\n');
  final withAlt = withBreaks.replaceAllMapped(
    RegExp(r'<img\b([^>]*)/?>', caseSensitive: false, dotAll: true),
    (match) => decodeHtmlEntities(_attribute(match.group(1) ?? '', 'alt') ?? ''),
  );
  return decodeHtmlEntities(withAlt.replaceAll(RegExp(r'<[^>]*>', dotAll: true), ''));
}

String? _attribute(String attributes, String name) {
  final pattern = '\\b' + RegExp.escape(name) + r'\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))';
  final match = RegExp(pattern, caseSensitive: false).firstMatch(attributes);
  if (match == null) return null;
  for (final value in [match.group(1), match.group(2), match.group(3)]) {
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String decodeHtmlEntities(String value) => value.replaceAllMapped(
      RegExp(r'&(#x[0-9a-f]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);', caseSensitive: false),
      (match) {
        final entity = match.group(1)!.toLowerCase();
        switch (entity) {
          case 'amp':
            return '&';
          case 'lt':
            return '<';
          case 'gt':
            return '>';
          case 'quot':
            return '"';
          case 'apos':
          case '#39':
            return "'";
          case 'nbsp':
            return ' ';
        }
        final codePoint = entity.startsWith('#x')
            ? int.tryParse(entity.substring(2), radix: 16)
            : entity.startsWith('#')
                ? int.tryParse(entity.substring(1))
                : null;
        if (codePoint == null || codePoint < 0 || codePoint > 0x10FFFF) return match.group(0)!;
        return String.fromCharCode(codePoint);
      },
    );

bool _isMentionHref(String href) =>
    RegExp(r'^(?:https?://m\.weibo\.cn)?/n/', caseSensitive: false).hasMatch(href);

String? _mentionName(String href) {
  final path = href.split('?').first;
  final index = path.lastIndexOf('/n/');
  if (index < 0) return null;
  return _decodeComponent(path.substring(index + 3));
}

bool _isTopicHref(String href) {
  final normalized = href.toLowerCase();
  return normalized.contains('containerid=231522') ||
      normalized.contains('containerid%3d231522') ||
      normalized.contains('containerid=100808') ||
      normalized.contains('containerid%3d100808');
}

String? _resolveLink(String href) {
  if (href.toLowerCase().startsWith('javascript:')) return null;
  String absolute;
  if (href.startsWith('//')) {
    absolute = 'https:$href';
  } else if (href.startsWith('/')) {
    absolute = 'https://m.weibo.cn$href';
  } else if (href.toLowerCase().startsWith('http://') || href.toLowerCase().startsWith('https://')) {
    absolute = href;
  } else {
    return null;
  }
  if (!absolute.toLowerCase().contains('sinaurl?')) return absolute;
  final after = absolute.contains('?') ? absolute.substring(absolute.indexOf('?') + 1) : '';
  for (final part in after.split('&')) {
    final key = part.contains('=') ? part.substring(0, part.indexOf('=')) : part;
    if (key != 'u') continue;
    final value = part.contains('=') ? part.substring(part.indexOf('=') + 1) : '';
    final decoded = _decodeComponent(value);
    if (decoded != null &&
        (decoded.toLowerCase().startsWith('http://') || decoded.toLowerCase().startsWith('https://'))) {
      return decoded;
    }
  }
  return absolute;
}

String? _decodeComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return null;
  }
}

final _anchorRegex = RegExp(r'<a\b([^>]*)>(.*?)</a\s*>', caseSensitive: false, dotAll: true);
final _surlTextRegex = RegExp(
  r'<span\b[^>]*class\s*=\s*["\x27][^"\x27]*\bsurl-text\b[^"\x27]*["\x27][^>]*>(.*?)</span\s*>',
  caseSensitive: false,
  dotAll: true,
);

// ---------------------------------------------------------------------------------------------
// Time

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
    return fraction == 0 ? '${whole}万' : '${whole}.${fraction}万';
  }
  final tenths = n ~/ 10000000;
  final whole = tenths ~/ 10;
  final fraction = tenths % 10;
  return fraction == 0 ? '${whole}亿' : '${whole}.${fraction}亿';
}

String _two(int value) => value.toString().padLeft(2, '0');

// ---------------------------------------------------------------------------------------------
// Users and statuses

User? toUser(dynamic element) {
  final json = asMap(element);
  if (json == null) return null;
  final id = idOf(json['id']);
  if (id == null) return null;
  String? avatar;
  for (final key in ['avatar_hd', 'avatar_large', 'profile_image_url']) {
    final value = textOf(json[key]);
    if (value != null && value.isNotEmpty) {
      avatar = value;
      break;
    }
  }
  final followers = countOf(json['followers_count']);
  return User(
    id: id,
    screenName: textOf(json['screen_name']) ?? '',
    avatarUrl: avatar,
    description: textOf(json['description']) ?? '',
    verified: boolOf(json['verified']),
    followersCount: followers != 0 ? followers : countOf(json['followers_count_str']),
    followingCount: countOf(json['follow_count']),
    statusesCount: countOf(json['statuses_count']),
    following: intOf(json['following']) == 1,
  );
}

Status? toStatus(dynamic element) {
  final json = asMap(element);
  if (json == null) return null;
  final id = idOf(json['id']) ?? idOf(json['mid']);
  if (id == null) return null;
  final rich = weiboHtmlToRichText(textOf(json['text']) ?? textOf(json['raw_text']) ?? '');
  final convertedText = rich.text;
  final pageInfo = asMap(json['page_info']);
  final pics = _imagesFromPics(json);
  final images = pics.isNotEmpty ? pics : _imagesFromPicInfos(json);
  _applyPicVideo(images, textOf(json['pic_video']));
  final media = <Media>[...images];
  final video = _videoFrom(pageInfo);
  if (video != null) media.add(video);

  final topicNames = <String>[
    ...RegExp(r'#([^#\n]+)#').allMatches(convertedText).map((m) => m.group(1)!),
    ...asList(json['topic_struct'])
        .map((e) => textOf(asMap(e)?['topic_title']))
        .whereType<String>()
        .where((value) => value.isNotEmpty),
  ].toSet().toList();

  final sourceText = textOf(json['source']);
  return Status(
    id: id,
    author: toUser(json['user']) ?? const User(id: '', screenName: ''),
    text: convertedText,
    createdAt: parseWeiboTime(textOf(json['created_at'])),
    source: sourceText == null ? null : weiboHtmlToText(sourceText).trim(),
    media: media,
    repostOf: toStatus(json['retweeted_status']),
    repostsCount: countOf(json['reposts_count']),
    commentsCount: countOf(json['comments_count']),
    likesCount: countOf(json['attitudes_count']),
    liked: intOf(json['attitudes_status']) == 1 || boolOf(json['liked']),
    favorited: boolOf(json['favorited']),
    topics: topicNames.map(Topic.new).toList(),
    place: pageInfo != null && textOf(pageInfo['type']) == 'place'
        ? Place(textOf(pageInfo['page_title']) ?? '', url: _pageUrlOf(pageInfo))
        : null,
    article: _articleCard(pageInfo),
    card: _linkCard(pageInfo),
    links: rich.links,
    isLongText: boolOf(json['isLongText']),
    region: textOf(json['region_name']),
    pinned: intOf(json['isTop']) == 1 ||
        (textOf(asMap(json['title'])?['text'])?.contains('置顶') ?? false),
  );
}

List<Media> _imagesFromPics(Map<String, dynamic> json) {
  final pics = json['pics'];
  final elements = <dynamic>[];
  if (pics is List) {
    elements.addAll(pics);
  } else if (pics is Map) {
    final entries = pics.entries.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a.key.toString()) ?? 1 << 30;
        final bi = int.tryParse(b.key.toString()) ?? 1 << 30;
        return ai.compareTo(bi);
      });
    elements.addAll(entries.map((e) => e.value));
  }
  final result = <Media>[];
  for (final element in elements) {
    final pic = asMap(element);
    if (pic == null) continue;
    final large = asMap(pic['large']);
    final largeUrl = textOf(large?['url']);
    final preview = textOf(pic['url']);
    final url = (largeUrl != null && largeUrl.isNotEmpty) ? largeUrl : preview;
    if (url == null || url.isEmpty) continue;
    final geo = asMap(large?['geo']) ?? asMap(pic['geo']);
    result.add(Media.image(
      url,
      previewUrl: (preview != null && preview.isNotEmpty) ? preview : url,
      width: intOf(geo?['width']) ?? 0,
      height: intOf(geo?['height']) ?? 0,
      liveUrl: _liveUrlOf(pic, 'videoSrc'),
    ));
  }
  return result;
}

/// A live photo's motion clip. m.weibo.cn names it `videoSrc`, weibo.com `video`; when only the
/// clip's `fid` survives, video.weibo.com still redirects the bare livephoto address to a signed one.
/// GIFs carry the same fields with an mp4, so only `type: livephoto` counts.
String? _liveUrlOf(Map<String, dynamic> pic, String key) {
  if (textOf(pic['type']) != 'livephoto') return null;
  final url = textOf(pic[key]) ?? textOf(pic['video']);
  if (url != null && url.isNotEmpty) return url;
  final fid = textOf(pic['fid']);
  if (fid != null && fid.isNotEmpty) return livePhotoUrl(fid);
  return null;
}

String livePhotoUrl(String fid) => 'https://video.weibo.com/media/play?livephoto='
    '${Uri.encodeComponent('https://livephoto.us.sinaimg.cn/$fid.mov')}';

/// weibo.com's `pic_video` lists the live pictures as `index:fid` pairs, e.g. `0:000C6S…,2:000Fx…`.
void _applyPicVideo(List<Media> images, String? picVideo) {
  if (picVideo == null || picVideo.isEmpty) return;
  for (final pair in picVideo.split(',')) {
    final colon = pair.indexOf(':');
    if (colon <= 0) continue;
    final index = int.tryParse(pair.substring(0, colon).trim());
    final fid = pair.substring(colon + 1).trim();
    if (index == null || index < 0 || index >= images.length || fid.isEmpty) continue;
    final image = images[index];
    if (image.isLive) continue;
    images[index] = Media.image(
      image.url,
      previewUrl: image.previewUrl,
      width: image.width,
      height: image.height,
      liveUrl: livePhotoUrl(fid),
    );
  }
}

List<Media> _imagesFromPicInfos(Map<String, dynamic> json) {
  final ids = asList(json['pic_ids']);
  final infos = asMap(json['pic_infos']);
  final infoList = <Map<String, dynamic>>[];
  if (infos != null) {
    if (ids.isEmpty) {
      // Some retweeted_status payloads contain pic_infos but no pic_ids.
      infoList.addAll(infos.values.map(asMap).whereType<Map<String, dynamic>>());
    } else {
      for (final idElement in ids) {
        final picId = idOf(idElement);
        final info = picId == null ? null : asMap(infos[picId]);
        if (info != null) infoList.add(info);
      }
    }
  } else if (json['pic_infos'] is List) {
    infoList.addAll(asList(json['pic_infos']).map(asMap).whereType<Map<String, dynamic>>());
  }
  if (infoList.isEmpty) return const [];
  final result = <Media>[];
  for (final info in infoList) {
    Map<String, dynamic>? original;
    for (final name in ['mw2000', 'largest', 'original', 'large']) {
      final candidate = asMap(info[name]);
      final url = textOf(candidate?['url']);
      if (candidate != null && url != null && url.isNotEmpty) {
        original = candidate;
        break;
      }
    }
    if (original == null) continue;
    Map<String, dynamic>? preview;
    for (final name in ['bmiddle', 'large', 'thumbnail']) {
      final candidate = asMap(info[name]);
      final url = textOf(candidate?['url']);
      if (candidate != null && url != null && url.isNotEmpty) {
        preview = candidate;
        break;
      }
    }
    Map<String, dynamic>? size;
    for (final name in ['largest', 'original', 'mw2000', 'large']) {
      final candidate = asMap(info[name]);
      if (candidate != null && ((intOf(candidate['width']) ?? 0) > 0 || (intOf(candidate['height']) ?? 0) > 0)) {
        size = candidate;
        break;
      }
    }
    final url = textOf(original['url'])!;
    result.add(Media.image(
      url,
      previewUrl: textOf(preview?['url']) ?? url,
      width: intOf(size?['width']) ?? 0,
      height: intOf(size?['height']) ?? 0,
      liveUrl: _liveUrlOf(info, 'video'),
    ));
  }
  return result;
}

Media? _videoFrom(Map<String, dynamic>? pageInfo) {
  // weibo.com numbers `type` and names the kind in `object_type`.
  if (pageInfo == null || (textOf(pageInfo['type']) != 'video' && textOf(pageInfo['object_type']) != 'video')) {
    return null;
  }
  final urls = asMap(pageInfo['urls']);
  final mediaInfo = asMap(pageInfo['media_info']);
  final candidates = [
    urls?['mp4_720p_mp4'],
    urls?['mp4_hd_mp4'],
    mediaInfo?['mp4_720p_mp4'],
    mediaInfo?['mp4_hd_url'],
    mediaInfo?['stream_url_hd'],
    mediaInfo?['mp4_sd_url'],
    mediaInfo?['stream_url'],
    urls?['mp4_ld_mp4'],
  ];
  String? url;
  for (final candidate in candidates) {
    final value = textOf(candidate);
    if (value != null && value.isNotEmpty) {
      url = value;
      break;
    }
  }
  if (url == null) return null;
  final pagePic = pageInfo['page_pic'];
  final String? cover = pagePic is Map ? textOf(pagePic['url']) : textOf(pagePic);
  final duration = doubleOf(mediaInfo?['duration']);
  return Media.video(
    url,
    previewUrl: cover ?? '',
    durationMs: duration == null ? 0 : (duration * 1000).round(),
  );
}

Article? _articleCard(Map<String, dynamic>? pageInfo) {
  if (pageInfo == null) return null;
  const articleHosts = {'card.weibo.com', 'media.weibo.cn'};
  const prefix = 'https://card.weibo.com/article/m/show/id/';
  final type = textOf(pageInfo['type']) ?? '';
  String? directUrl;
  for (final key in ['page_url', 'url', 'scheme']) {
    final value = textOf(pageInfo[key]);
    if (value != null && value.startsWith('http')) {
      directUrl = value;
      break;
    }
  }
  String? host;
  if (directUrl != null) {
    try {
      host = Uri.parse(directUrl).host.toLowerCase();
    } catch (_) {}
  }
  final isArticleHost = host != null && articleHosts.contains(host);
  if (type != 'article' && !isArticleHost) return null;
  final objectId = textOf(pageInfo['object_id']);
  final url = directUrl ?? (objectId != null && objectId.isNotEmpty ? prefix + objectId : null);
  if (url == null) return null;
  String title = '';
  for (final key in ['page_title', 'content1', 'title']) {
    final value = textOf(pageInfo[key]);
    if (value != null && value.isNotEmpty) {
      title = value;
      break;
    }
  }
  String? summary;
  for (final key in ['content2', 'content1']) {
    final value = textOf(pageInfo[key]);
    if (value != null && value.isNotEmpty && value != title) {
      summary = value;
      break;
    }
  }
  return Article(url: url, title: title, summary: summary);
}

String? _pageUrlOf(Map<String, dynamic> pageInfo) {
  for (final key in ['page_url', 'url_ori', 'url', 'scheme']) {
    final value = textOf(pageInfo[key]);
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// Cards other parts of the post already show (the video, an article, the place line, a topic
/// that is in the text) are left out; everything else gets the generic card.
LinkCard? _linkCard(Map<String, dynamic>? pageInfo) {
  if (pageInfo == null || _videoFrom(pageInfo) != null || _articleCard(pageInfo) != null) return null;
  final banner = _bannerCard(pageInfo);
  if (banner != null) return banner;
  final type = textOf(pageInfo['type']) ?? '';
  final objectType = textOf(pageInfo['object_type']) ?? '';
  if (const {'video', 'place', 'topic', 'search_topic', 'article'}.contains(type) || objectType == 'video') return null;
  final url = _pageUrlOf(pageInfo);
  final title = textOf(pageInfo['page_title']) ?? textOf(pageInfo['content1']) ?? '';
  if (url == null || title.isEmpty) return null;
  final content1 = textOf(pageInfo['content1']);
  final content2 = textOf(pageInfo['content2']) ?? textOf(pageInfo['page_desc']);
  final summary = [content1, content2].firstWhere((value) => value != null && value.isNotEmpty && value != title, orElse: () => null);
  final pagePic = pageInfo['page_pic'];
  final image = pagePic is Map ? textOf(pagePic['url']) : textOf(pagePic);
  final kind = type == 'hudongvote' || objectType == 'hudongvote' ? LinkKind.vote : linkKindOf(url);
  final typeLabel = switch (type) {
    'hudongvote' => '投票',
    'wenda' => '问答',
    'group' => '群聊',
    'user' => '用户',
    'live' => '直播',
    'music' => '音乐',
    'movie' => '影视',
    'book' => '书籍',
    'goods' || 'shop' => '商品',
    'event' || 'activity' => '活动',
    _ => kind == LinkKind.web ? siteNameOf(url) ?? '网页' : linkKindLabel(kind),
  };
  return LinkCard(
    url: url,
    title: title,
    summary: summary == null ? null : weiboHtmlToText(summary),
    imageUrl: image == null || image.isEmpty ? null : image,
    typeLabel: typeLabel,
    kind: kind,
  );
}

/// The birthday and medal posts: a transparent picture over a background, and often no text.
/// m.weibo.cn sends `type: bigPic` (the address, when there is one, in `page_pic.scheme`);
/// weibo.com sends a `card_info` of `card_type` 107.
LinkCard? _bannerCard(Map<String, dynamic> pageInfo) {
  String? foreground;
  String? background;
  String? url;
  String? title;
  final cardInfo = asMap(pageInfo['card_info']);
  if (textOf(pageInfo['type']) == 'bigPic') {
    final pagePic = asMap(pageInfo['page_pic']);
    foreground = textOf(pagePic?['url']);
    background = textOf(pageInfo['media_pic_url']);
    url = textOf(pagePic?['scheme']) ?? textOf(pageInfo['page_url']);
    title = textOf(pageInfo['title']);
  } else if (cardInfo != null && textOf(cardInfo['card_type']) == '107') {
    foreground = textOf(cardInfo['pic_url']);
    background = textOf(asMap(asMap(asMap(cardInfo['page_info'])?['pic_info'])?['pic_big'])?['url']);
    url = textOf(pageInfo['page_url']) ?? textOf(cardInfo['scheme']);
    title = textOf(cardInfo['title']);
  } else {
    return null;
  }
  if (foreground == null || foreground.isEmpty) return null;
  return LinkCard(
    url: url ?? '',
    title: title ?? '',
    imageUrl: foreground,
    backgroundUrl: background == null || background.isEmpty ? null : background,
    banner: true,
  );
}

// ---------------------------------------------------------------------------------------------
// Feeds

List<Map<String, dynamic>> mblogCards(dynamic cards) {
  final result = <Map<String, dynamic>>[];
  void visit(dynamic element) {
    final card = asMap(element);
    if (card == null) return;
    if (intOf(card['card_type']) == 9) {
      final own = asMap(card['mblog']);
      if (own != null) result.add(own);
    }
    for (final nested in asList(card['card_group'])) {
      visit(nested);
    }
  }
  for (final element in asList(cards)) {
    visit(element);
  }
  return result;
}

/// Reposts of one status. m.weibo.cn returns them under `data`, sometimes with a
/// `hot_data` list in front; a bare list is accepted too.
List<Status> parseReposts(dynamic data) {
  if (data == null) return const [];
  if (data is List) return _statusesOf(data);
  final root = asMap(data);
  if (root == null) return const [];
  final hot = root['hot_data'];
  final body = root['data'] ?? root['reposts'] ?? root['statuses'];
  return _statusesOf([
    if (hot is List) ...hot,
    if (body is List) ...body,
  ]);
}

List<Status> _statusesOf(List<dynamic> elements) {
  final items = <Status>[];
  for (final element in elements) {
    final status = toStatus(element);
    if (status != null) items.add(status);
  }
  return items;
}

PageResult<Status> parseFriendsFeed(dynamic data) {
  final root = asMap(data);
  final statusElements = data is List
      ? data
      : root != null
          ? (root['statuses'] is List
              ? root['statuses'] as List
              : (root['list'] is List ? root['list'] as List : const []))
          : const [];
  final items = <Status>[];
  for (final element in statusElements) {
    final status = toStatus(element);
    if (status != null) items.add(status);
  }
  String? next;
  if (items.isNotEmpty && root != null) {
    for (final key in ['max_id', 'next_cursor']) {
      final value = idOf(root[key]);
      if (value != null && value.isNotEmpty && value != '0') {
        next = value;
        break;
      }
    }
  }
  return PageResult(items, next);
}

PageResult<Status> parseContainerStatuses(dynamic data, int page) {
  final root = asMap(data);
  if (root == null) return const PageResult([], null);
  final items = <Status>[];
  for (final mblog in mblogCards(root['cards'])) {
    final status = toStatus(mblog);
    if (status != null) items.add(status);
  }
  final reported = intOf(asMap(root['cardlistInfo'])?['page']);
  final next = reported != null && reported > page ? reported : page + 1;
  return PageResult(items, items.isEmpty ? null : next.toString());
}

PageResult<Status> parseUserTimeline(dynamic data) {
  final root = asMap(data);
  if (root == null) return const PageResult([], null);
  final items = <Status>[];
  for (final mblog in mblogCards(root['cards'])) {
    final status = toStatus(mblog);
    if (status != null) items.add(status);
  }
  final next = idOf(asMap(root['cardlistInfo'])?['since_id']);
  return PageResult(
    items,
    (next != null && next.isNotEmpty && next != '0' && items.isNotEmpty) ? next : null,
  );
}

// ---------------------------------------------------------------------------------------------
// Comments

Comment? toComment(dynamic element, String statusId) {
  final json = asMap(element);
  if (json == null) return null;
  final id = idOf(json['id']) ?? textOf(json['idstr']);
  if (id == null) return null;
  final author = toUser(json['user']);
  if (author == null) return null;
  final replies = <Comment>[];
  for (final reply in asList(json['comments'])) {
    final parsed = toComment(reply, statusId);
    if (parsed != null) replies.add(parsed);
  }
  final images = _commentImages(json);
  final total = countOf(json['total_number']);
  return Comment(
    id: id,
    statusId: statusId,
    author: author,
    text: weiboHtmlToText(textOf(json['text']) ?? ''),
    createdAt: parseWeiboTime(textOf(json['created_at'])),
    likesCount: countOf(json['like_count'] ?? json['like_counts']),
    liked: boolOf(json['liked']),
    region: textOf(json['source']),
    replies: replies,
    repliesCount: total > replies.length ? total : replies.length,
    images: images,
  );
}

List<Media> _commentImages(Map<String, dynamic> comment) {
  final candidates = <Map<String, dynamic>>[
    ...asList(comment['pics']).map(asMap).whereType<Map<String, dynamic>>(),
    if (asMap(comment['pic']) != null) asMap(comment['pic'])!,
  ];
  final result = <Media>[];
  for (final item in candidates) {
    if (textOf(item['type']) == 'video') continue;
    final thumb = textOf(item['url']);
    if (thumb == null || !thumb.startsWith('http') || thumb.contains('&690')) continue;
    final large = asMap(item['large']);
    final full = textOf(large?['url']);
    final geo = asMap(large?['geo']) ?? asMap(item['geo']);
    result.add(Media.image(
      (full != null && full.startsWith('http')) ? full : thumb,
      previewUrl: thumb,
      width: intOf(geo?['width']) ?? 0,
      height: intOf(geo?['height']) ?? 0,
    ));
  }
  final seen = <String>{};
  return result.where((image) => seen.add(image.url)).toList();
}

PageResult<Comment> parseCommentPage(Map<String, dynamic>? container, String statusId) {
  if (container == null) return const PageResult([], null);
  // hotFlowChild wraps its list one level deeper than hotflow:
  // { data: { data: [...], max_id: ... } }
  final dataNode = container['data'];
  final nested = dataNode is Map ? asMap(dataNode) : null;
  final rawItems = dataNode is List
      ? dataNode
      : (nested?['data'] is List ? nested!['data'] as List : const []);
  final pageRoot = nested ?? container;
  final items = <Comment>[];
  for (final element in rawItems) {
    final comment = toComment(element, statusId);
    if (comment != null) items.add(comment);
  }
  final maxId = idOf(pageRoot['max_id']);
  final type = intOf(pageRoot['max_id_type']) ?? 0;
  final next = (maxId != null && maxId != '0' && items.isNotEmpty) ? '${maxId}:${type}' : null;
  return PageResult(items, next);
}

// ---------------------------------------------------------------------------------------------
// Messages and notifications

List<Map<String, dynamic>> _listItems(dynamic data) {
  final root = asMap(data);
  final list = data is List ? data : root?['data'];
  return asList(list).map(asMap).whereType<Map<String, dynamic>>().toList();
}

NotificationItem? _toNotification(Map<String, dynamic> json, NotificationKind kind) {
  final user = toUser(json['user']);
  if (user == null) return null;
  final id = idOf(json['id']) ?? idOf(json['mid']);
  if (id == null) return null;
  final text = weiboHtmlToText(textOf(json['text']) ?? '');
  Map<String, dynamic>? target;
  String? statusId;
  String? commentId;
  if (kind == NotificationKind.mentionInStatus) {
    target = asMap(json['retweeted_status']);
    statusId = id;
  } else {
    target = asMap(json['status']);
    statusId = idOf(target?['id']) ?? idOf(target?['mid']);
    commentId = kind == NotificationKind.like ? null : id;
  }
  final targetStatus = toStatus(target);
  String? targetImage;
  if (targetStatus != null) {
    for (final media in targetStatus.media) {
      if (media.kind == MediaKind.image) {
        targetImage = media.previewUrl;
        break;
      }
      if (media.kind == MediaKind.video && media.previewUrl.isNotEmpty) {
        targetImage = media.previewUrl;
        break;
      }
    }
  }
  final targetText = targetStatus == null
      ? null
      : (targetStatus.author.screenName.isEmpty
          ? targetStatus.text
          : '@${targetStatus.author.screenName}：${targetStatus.text}');
  return NotificationItem(
    id: '${kind.name}-$id',
    kind: kind,
    user: user,
    text: kind == NotificationKind.like && text.isEmpty ? '赞了你的微博' : text,
    createdAt: parseWeiboTime(textOf(json['created_at'])),
    statusId: statusId,
    commentId: commentId,
    targetText: targetText,
    targetImage: targetImage,
  );
}

List<NotificationItem> parseNotifications(dynamic data, NotificationKind kind) {
  final items = <NotificationItem>[];
  for (final json in _listItems(data)) {
    final notification = _toNotification(json, kind);
    if (notification != null) items.add(notification);
  }
  return items;
}

String? groupIdOf(String? scheme) {
  final raw = scheme?.trim() ?? '';
  if (raw.isEmpty) return null;
  final index = raw.indexOf('gid=');
  if (index < 0) return null;
  final value = raw.substring(index + 4).split('&').first;
  return value.isEmpty ? null : value;
}

List<Conversation> parseConversations(dynamic data) {
  final result = <Conversation>[];
  for (final item in _listItems(data)) {
    final user = toUser(item['user']);
    if (user == null) continue;
    result.add(Conversation(
      user: user,
      lastText: weiboHtmlToText(textOf(item['text']) ?? ''),
      updatedAt: parseWeiboTime(textOf(item['created_at'])),
      unread: intOf(item['unread']) ?? intOf(item['unread_count']) ?? 0,
      groupId: groupIdOf(textOf(item['scheme'])),
    ));
  }
  return result;
}

DirectMessage? _toMessage(Map<String, dynamic> msg, {Map<String, User>? users}) {
  final fromUser = asMap(msg['from_user']);
  final senderId = idOf(msg['sender_id']) ?? idOf(fromUser?['id']);
  final id = idOf(msg['id']);
  if (senderId == null || id == null) return null;
  final senderName = textOf(msg['sender_screen_name']) ??
      textOf(fromUser?['screen_name']) ??
      users?[senderId]?.screenName;
  return DirectMessage(
    id: id,
    senderId: senderId,
    text: weiboHtmlToText(textOf(msg['text']) ?? ''),
    createdAt: parseWeiboTime(textOf(msg['created_at']) ?? textOf(msg['time'])),
    senderName: (senderName != null && senderName.isNotEmpty) ? senderName : null,
    senderAvatar: users?[senderId]?.avatarUrl,
    mediaType: intOf(msg['media_type']) ?? 0,
  );
}

(List<DirectMessage>, Map<String, User>) parseChat(dynamic data) {
  final root = asMap(data);
  if (root == null) return (const <DirectMessage>[], const <String, User>{});
  final users = <String, User>{};
  final usersJson = asMap(root['users']);
  if (usersJson != null) {
    for (final value in usersJson.values) {
      final user = toUser(value);
      if (user != null) users[user.id] = user;
    }
  }
  final messages = <DirectMessage>[];
  for (final element in asList(root['msgs'])) {
    final msg = asMap(element);
    if (msg == null) continue;
    final parsed = _toMessage(msg, users: users);
    if (parsed != null) messages.add(parsed);
  }
  messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return (messages, users);
}

List<DirectMessage> parseGroupChat(dynamic data) {
  final root = asMap(data);
  if (root == null) return const [];
  final users = <String, User>{};
  final usersJson = asMap(root['users']);
  if (usersJson != null) {
    for (final entry in usersJson.entries) {
      final user = toUser(entry.value);
      if (user != null) users[user.id.isEmpty ? entry.key : user.id] = user;
    }
  }
  final messages = <DirectMessage>[];
  for (final element in asList(root['msgs'])) {
    final msg = asMap(element);
    if (msg == null) continue;
    final parsed = _toMessage(msg, users: users);
    if (parsed != null) messages.add(parsed);
  }
  messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return messages;
}

UnreadCounts parseUnread(dynamic data) {
  final root = asMap(data);
  if (root == null) return const UnreadCounts();
  return UnreadCounts(
    mentionsInStatuses: intOf(root['mention_status']) ?? 0,
    mentionsInComments: intOf(root['mention_cmt']) ?? 0,
    comments: intOf(root['cmt']) ?? 0,
    likes: intOf(root['attitude']) ?? 0,
    messages: intOf(root['dm']) ?? 0,
  );
}

// ---------------------------------------------------------------------------------------------
// Profiles, relations, search, topics

UserProfile? parseUserProfile(dynamic data) {
  final info = asMap(asMap(data)?['userInfo']);
  if (info == null) return null;
  final user = toUser(info);
  if (user == null) return null;
  return UserProfile(
    user: user,
    coverUrl: textOf(info['cover_image_phone']),
    verifiedReason: textOf(info['verified_reason']),
    following: boolOf(info['following']),
    followsYou: boolOf(info['follow_me']),
  );
}

PageResult<User> parseRelations(dynamic data, int page) {
  final root = asMap(data);
  if (root == null) return const PageResult([], null);
  final users = <User>[];
  void visit(dynamic element) {
    final card = asMap(element);
    if (card == null) return;
    final own = toUser(card['user']);
    if (own != null && own.screenName.isNotEmpty) users.add(own);
    for (final nested in asList(card['card_group'])) {
      visit(nested);
    }
  }
  for (final card in asList(root['cards'])) {
    visit(card);
  }
  final seen = <String>{};
  final unique = users.where((u) => seen.add(u.id)).toList();
  final total = intOf(asMap(root['cardlistInfo'])?['total']);
  const pageSize = 20;
  final hasMore = unique.isNotEmpty && (total == null || page * pageSize < total);
  return PageResult(unique, hasMore ? (page + 1).toString() : null);
}

List<HotSearch> parseHotSearch(dynamic data) {
  final root = asMap(data);
  if (root == null) return const [];
  final result = <HotSearch>[];
  for (final card in asList(root['cards'])) {
    for (final element in asList(asMap(card)?['card_group'])) {
      final item = asMap(element);
      if (item == null) continue;
      final word = textOf(item['desc'])?.trim();
      if (word == null || word.isEmpty) continue;
      final scheme = textOf(item['scheme']);
      final heat = textOf(item['desc_extr']) ?? idOf(item['desc_extr']);
      result.add(HotSearch(
        word: word,
        query: _searchQueryOf(scheme) ?? word,
        heat: heat?.trim(),
        iconUrl: textOf(item['icon']),
        pinned: item['promotion'] != null || (textOf(item['pic'])?.contains('stick') ?? false),
      ));
    }
  }
  final seen = <String>{};
  var rank = 0;
  return [
    for (final entry in result)
      if (seen.add(entry.word))
        entry.pinned
            ? entry
            : HotSearch(
                word: entry.word,
                query: entry.query,
                heat: entry.heat,
                iconUrl: entry.iconUrl,
                heatValue: countOf(entry.heat),
                rank: ++rank,
              ),
  ];
}

/// weibo.com's `statuses/hot_band`: the same board as m.weibo.cn, with the rank, badge, category
/// and the time each entry made the list.
List<HotSearch> parseHotBand(dynamic data, {HotBoard board = HotBoard.realtime}) {
  final root = asMap(data);
  if (root == null) return const [];
  final result = <HotSearch>[];
  final gov = asMap(root['hotgov']);
  final govWord = gov == null ? null : (textOf(gov['word']) ?? textOf(gov['name']))?.trim();
  if (gov != null && govWord != null && govWord.isNotEmpty) {
    result.add(HotSearch(
      word: govWord.replaceAll('#', ''),
      query: govWord.startsWith('#') ? govWord : '#$govWord#',
      label: textOf(gov['icon_desc']) ?? textOf(gov['small_icon_desc']),
      labelColor: _hexColor(textOf(gov['icon_desc_color'])),
      pinned: true,
    ));
  }
  var rank = 0;
  for (final element in asList(root['band_list'])) {
    final item = asMap(element);
    if (item == null || boolOf(item['is_ad']) || item['topic_ad'] != null && boolOf(item['topic_ad'])) continue;
    final word = (textOf(item['word']) ?? textOf(item['note']))?.trim();
    if (word == null || word.isEmpty) continue;
    rank++;
    final scheme = textOf(item['word_scheme'])?.trim();
    final topic = boolOf(item['topic_flag']) || (scheme?.startsWith('#') ?? false);
    final num = intOf(item['num']);
    final onboard = intOf(item['onboard_time']);
    result.add(HotSearch(
      word: word,
      query: topic ? '#${word.replaceAll('#', '')}#' : word,
      heat: num == null || num <= 0 ? null : compactCount(num),
      heatValue: num,
      rank: rank,
      label: textOf(item['label_name']) ?? textOf(item['icon_desc']),
      labelColor: _hexColor(textOf(item['icon_desc_color'])),
      category: textOf(item['category'])?.split(',').first.trim(),
      onboardAt: onboard == null || onboard <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(onboard * 1000),
      board: board,
    ));
  }
  final seen = <String>{};
  return result.where((entry) => seen.add(entry.word)).toList();
}

/// weibo.com's `feed/allGroups`: the 推荐 channels are its groups of type 1, 我的频道 then 频道推荐.
/// Its 热门 becomes two: [RecommendChannel.hot] for the account and [RecommendChannel.everyone].
List<RecommendChannel> parseRecommendChannels(dynamic data) {
  final result = <RecommendChannel>[];
  final seen = <String>{};
  var first = true;
  for (final element in asList(asMap(data)?['groups'])) {
    final group = asMap(element);
    if (group == null || intOf(group['group_type']) != 1) continue;
    for (final item in asList(group['group'])) {
      final channel = asMap(item);
      final gid = idOf(channel?['gid']);
      final container = textOf(channel?['containerid']);
      final title = textOf(channel?['title'])?.trim();
      if (gid == null || container == null || title == null || title.isEmpty || !seen.add(gid)) continue;
      if (gid == RecommendChannel.hot.gid) {
        result.addAll(const [RecommendChannel.hot, RecommendChannel.everyone]);
        continue;
      }
      result.add(RecommendChannel(gid: gid, containerId: container, title: title, featured: first));
    }
    first = false;
  }
  if (!result.any((channel) => channel.personal)) result.insertAll(0, const [RecommendChannel.hot, RecommendChannel.everyone]);
  return result;
}

/// weibo.com's `feed/hottimeline`: every call is a fresh draw, so pages overlap.
List<Status> parseHotTimeline(dynamic data) =>
    asList(asMap(data)?['statuses']).map(toStatus).whereType<Status>().toList();

int? _hexColor(String? hex) {
  final value = hex?.trim().replaceFirst('#', '');
  if (value == null || (value.length != 6 && value.length != 8)) return null;
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return value.length == 6 ? 0xFF000000 | parsed : parsed;
}

/// weibo.com's `side/search`: query completions and matching accounts.
SearchSuggestions parseSearchSuggestions(dynamic data) {
  final root = asMap(data);
  if (root == null) return const SearchSuggestions();
  final words = <SearchSuggestion>[];
  final seen = <String>{};
  for (final element in asList(root['hotquery'])) {
    final item = asMap(element);
    final word = textOf(item?['suggestion'])?.trim();
    if (item == null || word == null || word.isEmpty || !seen.add(word)) continue;
    words.add(SearchSuggestion(
      word: word,
      count: intOf(item['count']),
      hot: (intOf(item['top_flag']) ?? 0) > 0,
    ));
  }
  final users = <User>[];
  final userIds = <String>{};
  for (final element in asList(root['users'])) {
    final user = toUser(element);
    if (user != null && user.screenName.isNotEmpty && userIds.add(user.id)) users.add(user);
  }
  return SearchSuggestions(words: words, users: users);
}

final _statLabelFirst = RegExp(r'(阅读|讨论|原创|互动)(?:量|数|人数)?\s*([\d.]+\s*[万亿]?)');
final _statNumberFirst = RegExp(r'([\d.]+\s*[万亿]?)\s*(阅读|讨论|原创|互动)');

/// Figures in a stats line, which Weibo writes both ways: 「阅读量501.5万 讨论量1929」 and
/// 「1.2亿阅读 3.4万讨论」.
Map<String, int> _statsOf(String text) {
  final result = <String, int>{};
  for (final match in _statLabelFirst.allMatches(text)) {
    result.putIfAbsent(match.group(1)!, () => countOf(match.group(2)!.replaceAll(' ', '')));
  }
  if (result.isEmpty) {
    for (final match in _statNumberFirst.allMatches(text)) {
      result.putIfAbsent(match.group(2)!, () => countOf(match.group(1)!.replaceAll(' ', '')));
    }
  }
  return result;
}

/// The head of an m.weibo.cn topic or search container:
/// `cardlistInfo.cardlist_head_cards[].head_data` with a title, a cover, a stats line in
/// `midtext` and 「主持人：… | 14家媒体发布」 in `downtext`.
TopicInfo? parseTopicInfo(dynamic data) {
  final info = asMap(asMap(data)?['cardlistInfo']);
  if (info == null) return null;
  for (final head in asList(info['cardlist_head_cards'])) {
    final headData = asMap(asMap(head)?['head_data']);
    if (headData == null) continue;
    String? stats;
    Map<String, int> figures = const {};
    String? host;
    final notes = <String>[];
    for (final key in ['midtext', 'downtext', 'desc']) {
      final text = textOf(headData[key])?.replaceAll(RegExp(r'详情\s*>?'), '').trim();
      if (text == null || text.isEmpty) continue;
      final parsed = _statsOf(text);
      if (parsed.isNotEmpty && stats == null) {
        stats = text;
        figures = parsed;
        continue;
      }
      for (final part in text.split('|').map((part) => part.trim()).where((part) => part.isNotEmpty)) {
        final named = RegExp(r'^主持人[：:]\s*(.+)$').firstMatch(part);
        if (named != null) {
          host ??= named.group(1)!.trim();
        } else {
          notes.add(part);
        }
      }
    }
    final parsed = TopicInfo(
      title: textOf(headData['title']),
      coverUrl: textOf(headData['portrait_url']),
      stats: stats,
      reads: figures['阅读'],
      discussions: figures['讨论'],
      originals: figures['原创'],
      interactions: figures['互动'],
      host: host,
      note: notes.isEmpty ? null : notes.join(' · '),
    );
    if (!parsed.isEmpty) return parsed;
  }
  return null;
}

/// m.s.weibo.com's `ajax_topic/detail`, the card behind 「详情>」 on a topic head.
TopicInfo? parseTopicDetail(dynamic data) {
  final root = asMap(data);
  final base = asMap(root?['baseInfo']);
  if (root == null || base == null) return null;
  final object = asMap(base['object']);
  final count = asMap(base['count']);
  final claim = asMap(base['claim_info']);
  final band = asMap(asMap(asMap(base['band_info'])?['hot_band'])?['ori']);
  final summary = textOf(object?['summary']);
  final hostName = textOf(claim?['screen_name']);
  final boards = <TopicBoardStint>[];
  for (final element in asList(asMap(asMap(root['baseData'])?['m_rank_pos_duration'])?['data'])) {
    final item = asMap(element);
    final name = textOf(item?['cate_desc']);
    if (item == null || name == null) continue;
    final on = _boardTime(item['on_board_time']);
    final off = _boardTime(item['off_board_time']);
    boards.add(TopicBoardStint(
      board: name,
      bestRank: intOf(item['top_pos']),
      minutes: intOf(item['duration_minute']) ?? 0,
      onAt: on,
      // A board still running reports the latest update as its end.
      offAt: off != null && DateTime.now().difference(off) > const Duration(minutes: 12) ? off : null,
    ));
  }
  List<User> usersOf(dynamic list) => [
        for (final element in asList(list))
          if (toUser(element) case final user? when user.screenName.isNotEmpty) user,
      ];
  final media = asMap(root['media_info']);
  final created = intOf(asMap(object?['creator'])?['create_at']) ?? intOf(object?['create_at']);
  int? positive(dynamic value) {
    final number = intOf(value);
    return number == null || number <= 0 ? null : number;
  }

  final category = textOf(band?['category']) ?? textOf(object?['category_str']) ?? textOf(object?['category'])?.split('|').first;
  final parsed = TopicInfo(
    title: textOf(object?['display_name']),
    lead: summary == null ? null : weiboHtmlToText(summary).trim(),
    coverUrl: textOf(asMap(object?['image'])?['url']),
    reads: positive(count?['read']),
    discussions: positive(count?['mention']),
    originals: positive(count?['ori_m']),
    interactions: positive(count?['interact']),
    host: hostName,
    hostId: hostName == null ? null : idOf(claim?['idstr']) ?? idOf(claim?['id']),
    note: textOf(media?['show_str']) == null ? null : '${textOf(media?['show_str'])}发布',
    category: category == null || category.trim().isEmpty ? null : category.trim(),
    highlight: textOf(asMap(base['dim_data'])?['content']),
    boards: boards,
    contributors: usersOf(base['lists_users']),
    media: usersOf(media?['users']),
    createdAt: created == null || created <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(created * 1000),
    firstStatusId: idOf(asMap(object?['creator'])?['mid']),
  );
  return parsed.isEmpty && parsed.interactions == null ? null : parsed;
}

/// Board times are written `yyyyMMddHHmm` in Beijing time.
DateTime? _boardTime(dynamic value) {
  final text = textOf(value);
  if (text == null || text.length != 12 || int.tryParse(text) == null) return null;
  int part(int from, int to) => int.parse(text.substring(from, to));
  return DateTime.utc(part(0, 4), part(4, 6), part(6, 8), part(8, 10), part(10, 12))
      .subtract(const Duration(hours: 8))
      .toLocal();
}

/// m.s.weibo.com's `ajax_topic/trend`: hourly reads for the last day.
List<TopicTrendPoint> parseTopicTrend(dynamic data) => [
      for (final element in asList(asMap(data)?['read']))
        if (asMap(element) case final point?)
          TopicTrendPoint(textOf(point['time']) ?? '', intOf(point['value']) ?? 0),
    ];

/// The comment a reply thread hangs off. hotFlowChild sends it as `rootComment`, a one-item list.
Comment? parseRootComment(Map<String, dynamic>? root, String statusId) {
  if (root == null) return null;
  final node = root['rootComment'] ?? asMap(root['data'])?['rootComment'];
  final first = node is List ? (node.isEmpty ? null : node.first) : node;
  return toComment(first, statusId);
}

String? _searchQueryOf(String? scheme) {
  if (scheme == null) return null;
  try {
    final uri = Uri.parse(scheme);
    final q = uri.queryParameters['q'];
    if (q != null && q.isNotEmpty) return q;
    final container = uri.queryParameters['containerid'];
    if (container == null) return null;
    for (final part in container.split('&')) {
      if (part.startsWith('q=') && part.length > 2) return part.substring(2);
    }
  } catch (_) {}
  return null;
}

List<FeedSource> parseFeedGroups(dynamic data) {
  final root = asMap(data);
  if (root == null) return const [];
  final result = <FeedSource>[];
  for (final element in asList(root['groups'])) {
    final group = asMap(element);
    if (group == null) continue;
    final gid = idOf(group['gid']);
    final name = textOf(group['name']);
    if (gid == null || name == null || name.isEmpty) continue;
    result.add(FeedSource(FeedKind.group, name, gid));
  }
  return result;
}

PageResult<SuperTopic> parseSuperTopics(dynamic data) {
  final root = asMap(data);
  if (root == null) return const PageResult([], null);
  final topics = <SuperTopic>[];
  void visit(dynamic element) {
    final card = asMap(element);
    if (card == null) return;
    if (intOf(card['card_type']) == 8) {
      final name = textOf(card['title_sub']);
      if (name != null && name.isNotEmpty) {
        String? containerId;
        final scheme = textOf(card['scheme']);
        if (scheme != null) {
          try {
            containerId = Uri.parse(scheme).queryParameters['containerid'];
          } catch (_) {}
        }
        topics.add(SuperTopic(
          name: name,
          iconUrl: textOf(card['pic']),
          containerId: (containerId != null && containerId.isNotEmpty) ? containerId : null,
          followersLabel: textOf(card['desc2']),
          followed: intOf(card['followed']) == 1,
        ));
      }
    }
    for (final nested in asList(card['card_group'])) {
      visit(nested);
    }
  }
  for (final card in asList(root['cards'])) {
    visit(card);
  }
  final seen = <String>{};
  final unique = topics.where((topic) => seen.add(topic.containerId ?? topic.name)).toList();
  final next = idOf(asMap(root['cardlistInfo'])?['since_id']);
  return PageResult(unique, (next != null && unique.isNotEmpty) ? next : null);
}

// ---------------------------------------------------------------------------------------------
// Emoji

Map<String, String> collectEmoji(dynamic root) {
  final found = <String, String>{};
  void visit(dynamic element) {
    if (element is Map) {
      for (final value in element.values) {
        visit(value);
      }
    } else if (element is List) {
      for (final value in element) {
        visit(value);
      }
    } else if (element is String && element.toLowerCase().contains('<img')) {
      for (final match in RegExp(r'<img\b([^>]*)>', caseSensitive: false).allMatches(element)) {
        final attributes = match.group(1) ?? '';
        final alt = RegExp(r'\balt\s*=\s*["\x27]([^"\x27]*)["\x27]', caseSensitive: false)
            .firstMatch(attributes)
            ?.group(1)
            ?.trim();
        if (alt == null || !RegExp(r'^\[[^\[\]\s]{1,12}\]$').hasMatch(alt)) continue;
        var src = RegExp(r'\bsrc\s*=\s*["\x27]([^"\x27]*)["\x27]', caseSensitive: false)
            .firstMatch(attributes)
            ?.group(1)
            ?.trim();
        if (src == null) continue;
        if (src.startsWith('//')) {
          src = 'https:$src';
        } else if (src.startsWith('http://')) {
          src = 'https://${src.substring(7)}';
        } else if (!src.startsWith('https://')) {
          continue;
        }
        found[alt] = src;
      }
    }
  }
  visit(root);
  return found;
}

// ---------------------------------------------------------------------------------------------
// Offline sample data

List<Status> parseFakeTimeline(String source) {
  final root = jsonDecode(source);
  final statuses = asList(asMap(root)?['statuses']);
  final result = <Status>[];
  for (final element in statuses) {
    final json = asMap(element);
    if (json == null) continue;
    final author = asMap(json['author']);
    if (author == null) continue;
    final media = <Media>[];
    for (final m in asList(json['media'])) {
      final item = asMap(m);
      if (item == null) continue;
      if (textOf(item['type']) == 'video') {
        media.add(Media.video(textOf(item['url']) ?? '', previewUrl: textOf(item['cover_url']) ?? ''));
      } else {
        media.add(Media.image(
          textOf(item['url']) ?? '',
          previewUrl: textOf(item['preview_url']) ?? textOf(item['url']) ?? '',
          width: intOf(item['width']) ?? 0,
          height: intOf(item['height']) ?? 0,
        ));
      }
    }
    final articleJson = asMap(json['article']);
    final repostJson = asMap(json['repost_of']);
    final placeJson = asMap(json['place']);
    result.add(Status(
      id: textOf(json['id']) ?? '',
      author: User(
        id: textOf(author['id']) ?? '',
        screenName: textOf(author['screen_name']) ?? '',
        avatarUrl: textOf(author['avatar_url']),
        description: textOf(author['description']) ?? '',
        verified: author['verified'] == true,
        followersCount: intOf(author['followers_count']) ?? 0,
        followingCount: intOf(author['following_count']) ?? 0,
        statusesCount: intOf(author['statuses_count']) ?? 0,
      ),
      text: textOf(json['text']) ?? '',
      createdAt: parseWeiboTime(textOf(json['created_at'])),
      source: textOf(json['source']),
      media: media,
      repostOf: repostJson == null
          ? null
          : Status(
              id: textOf(repostJson['id']) ?? '',
              author: User(
                id: textOf(asMap(repostJson['author'])?['id']) ?? '',
                screenName: textOf(asMap(repostJson['author'])?['screen_name']) ?? '',
                avatarUrl: textOf(asMap(repostJson['author'])?['avatar_url']),
              ),
              text: textOf(repostJson['text']) ?? '',
              createdAt: parseWeiboTime(textOf(repostJson['created_at'])),
            ),
      repostsCount: intOf(json['reposts_count']) ?? 0,
      commentsCount: intOf(json['comments_count']) ?? 0,
      likesCount: intOf(json['likes_count']) ?? 0,
      liked: json['liked'] == true,
      topics: asList(json['topics']).map((e) => Topic(e.toString())).toList(),
      place: placeJson == null ? null : Place(textOf(placeJson['name']) ?? ''),
      article: articleJson == null
          ? null
          : Article(
              url: textOf(articleJson['url']) ?? '',
              title: textOf(articleJson['title']) ?? '',
              summary: textOf(articleJson['summary']),
            ),
      isLongText: json['is_long_text'] == true,
      region: textOf(json['region']),
    ));
  }
  return result;
}