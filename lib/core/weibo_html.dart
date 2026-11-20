/// Weibo's post text: HTML in, plain words and links out.
///
/// The text arrives as HTML with `<a>` wrappers around mentions, topics and links, and sometimes a
/// 「全文」 link the app must not show. What each anchor means — a person, a hashtag, a place, a
/// super topic, a video — is decided here, once, together with the address that stands in its
/// place in the text. Anything that draws a post's words goes through [weiboHtmlToRichText].
library;

import 'links.dart';
import 'models.dart';

/// The voice-post stub at the head of a text, shared with the audio parser: m.weibo.cn leaves a
/// voice post's `blog_audio` out and starts the text with
/// `[语音10"]请用最新版手机微博app收听原声<br />` instead (`1'05"` past a minute).
final voiceStub = RegExp(r'^\s*\[语音([^\]]{0,16})\]\s*请用最新版[^<]{0,12}收听原声\s*(?:<br\s*/?>)?');

String weiboHtmlToText(String html) => weiboHtmlToRichText(html).text;

/// The post's text, with each link's address standing in its place, and what m.weibo.cn drew for
/// those links: their own words (a place's name, a super topic, 抽奖详情) and kind.
({String text, Map<String, WeiboLink> links}) weiboHtmlToRichText(String html) {
  final links = <String, WeiboLink>{};
  final withoutAnchors = html.replaceFirst(voiceStub, '').replaceAllMapped(_anchorRegex, (match) {
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
      final pidsAttr = _attribute(attributes, 'data-pids');
      final host = sinaimgHostOf(resolved);
      final bundled = pidsAttr == null
          ? const <Media>[]
          : [
              for (final raw in pidsAttr.split(','))
                if (raw.trim().isNotEmpty) mediaFromPicId(raw.trim(), host: host),
            ];
      links[resolved] = WeiboLink(url: resolved, label: words, kind: kind, images: bundled);
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
  return normalized.contains('containerid=100808') || normalized.contains('containerid%3d100808');
}

String _htmlFragmentToText(String fragment) {
  final withBreaks = fragment
      .replaceAll(RegExp(r'<br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n');
  final withAlt = withBreaks.replaceAllMapped(
    RegExp(r'<img\b([^>]*)/?>', caseSensitive: false, dotAll: true),
    (match) => _attribute(match.group(1) ?? '', 'alt') ?? '',
  );
  return decodeHtmlEntities(withAlt.replaceAll(RegExp(r'<[^>]*>', dotAll: true), ''));
}

String? _attribute(String attributes, String name) {
  final pattern = '\\b${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))';
  final match = RegExp(pattern, caseSensitive: false).firstMatch(attributes);
  if (match == null) return null;
  for (final value in [match.group(1), match.group(2), match.group(3)]) {
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String decodeHtmlEntities(String value) => value.replaceAllMapped(
      RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'),
      (match) {
        final entity = match.group(1)!.toLowerCase();
        const named = {
          'amp': '&',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'nbsp': ' ',
          'hellip': '…',
          'mdash': '—',
          'ndash': '–',
          'middot': '·',
          'ldquo': '“',
          'rdquo': '”',
          'lsquo': '‘',
          'rsquo': '’',
        };
        final replacement = named[entity];
        if (replacement != null) return replacement;
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

final RegExp _sinaimgHostRegex = RegExp(r'^https?://([a-z0-9-]+\.sinaimg\.cn)/', caseSensitive: false);
final RegExp _sinaimgPidRegex = RegExp(r'sinaimg\.cn/[^/?#]+/([0-9a-zA-Z]+)(?:\.[a-zA-Z0-9]+)?', caseSensitive: false);

/// The `https://<host>` origin of a sinaimg URL, or null when [url] is not a sinaimg address.
String? sinaimgHostOf(String? url) {
  if (url == null || url.isEmpty) return null;
  final match = _sinaimgHostRegex.firstMatch(url);
  return match == null ? null : 'https://${match.group(1)}';
}

/// The picture id inside a sinaimg address, e.g. `008KczEmly1ij3940pl3uj30u011pgpq`.
String? picIdOfUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  return _sinaimgPidRegex.firstMatch(url)?.group(1);
}

final RegExp _inlineSinaimgUrlRegex = RegExp(
  r'https?://[a-z0-9-]+\.sinaimg\.cn/[^\s<>"]+\.(?:jpg|jpeg|png|gif|webp)',
  caseSensitive: false,
);

/// Extracts inline sinaimg picture URLs standing in plain post text (e.g. a 「查看图片」 anchor).
List<String> inlineSinaimgUrls(String text) =>
    [for (final m in _inlineSinaimgUrlRegex.allMatches(text)) m.group(0)!];

/// Builds a [Media.image] from a bare Weibo picture id when an endpoint sends `pic_ids` or
/// `data-pids` without full `pics`/`pic_infos` metadata.
Media mediaFromPicId(String pid, {String? host}) {
  // Position 21 (0-based) of a Weibo pic id encodes the format: `g` for GIF, `j` for JPEG.
  final ext = pid.length > 21 && (pid[21] == 'g' || pid[21] == 'G') ? 'gif' : 'jpg';
  final origin = host ?? 'https://wx3.sinaimg.cn';
  return Media.image(
    '$origin/large/$pid.$ext',
    previewUrl: '$origin/orj360/$pid.$ext',
  );
}

final _anchorRegex = RegExp(r'<a\b([^>]*)>(.*?)</a\s*>', caseSensitive: false, dotAll: true);
final _surlTextRegex = RegExp(
  r'<span\b[^>]*class\s*=\s*["\x27][^"\x27]*\bsurl-text\b[^"\x27]*["\x27][^>]*>(.*?)</span\s*>',
  caseSensitive: false,
  dotAll: true,
);
