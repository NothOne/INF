import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../emoji.dart';
import '../image_url.dart';
import '../links.dart';
import '../models.dart';
import 'smart_image.dart';

enum _TokenKind { plain, mention, topic, url, emoji }

class _Token {
  final _TokenKind kind;
  final int start;
  final int end;
  final String value;
  const _Token(this.kind, this.start, this.end, this.value);
}

/// Text with @mentions, #topics#, links and inline emoji. Links are real tap targets; the emoji
/// picture is only drawn when the catalog has seen that code in an API response.
class RichStatusText extends StatefulWidget {
  const RichStatusText({
    super.key,
    required this.text,
    this.style,
    this.color,
    this.maxLines = 1000,
    this.onMention,
    this.onTopic,
    this.onUrl,
    this.onOpenImage,
    this.inlineImages = true,
    this.links = const {},
  });

  final String text;

  /// What the post drew for the links in [text], by address.
  final Map<String, WeiboLink> links;
  final TextStyle? style;
  final Color? color;
  final int maxLines;
  final ValueChanged<String>? onMention;
  final ValueChanged<String>? onTopic;
  final ValueChanged<String>? onUrl;
  final void Function(String url, String? heroTag)? onOpenImage;
  final bool inlineImages;

  @override
  State<RichStatusText> createState() => _RichStatusTextState();
}

class _RichStatusTextState extends State<RichStatusText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  String _imageTag(int start) => 'link-img-' + identityHashCode(this).toString() + '-' + start.toString();

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? Theme.of(context).textTheme.bodyLarge!;
    final style = widget.color == null ? base : base.copyWith(color: widget.color);
    final scheme = Theme.of(context).colorScheme;
    _clearRecognizers();
    return ListenableBuilder(
      listenable: EmojiStore.instance,
      builder: (context, _) {
        final spans = <InlineSpan>[];
        for (final token in _tokenize(widget.text)) {
          switch (token.kind) {
            case _TokenKind.plain:
              spans.add(TextSpan(text: token.value));
            case _TokenKind.mention:
              final callback = widget.onMention;
              spans.add(_link(
                token.value,
                scheme.primary,
                callback == null ? null : () => callback(_mentionName(token.value)),
              ));
            case _TokenKind.topic:
              final callback = widget.onTopic;
              spans.add(_link(
                token.value,
                scheme.primary,
                callback == null ? null : () => callback(_topicName(token.value)),
              ));
            case _TokenKind.url:
              final imageUrl = _inlineImageUrl(token.value);
              if (imageUrl != null && !widget.inlineImages) {
                final callback = widget.onOpenImage;
                final tag = _imageTag(token.start);
                Widget link = InlineLinkLabel(icon: Icons.image_outlined, label: '查看图片', style: style);
                if (callback != null) {
                  link = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => callback(imageUrl, tag),
                    child: Hero(
                      tag: tag,
                      child: Material(type: MaterialType.transparency, child: link),
                    ),
                  );
                }
                spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: link));
              } else if (imageUrl != null) {
                final callback = widget.onOpenImage;
                final tag = _imageTag(token.start);
                Widget picture = ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 150,
                    height: 150,
                    child: SmartImage(url: imageUrl, fit: BoxFit.cover),
                  ),
                );
                if (callback != null) {
                  picture = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => callback(imageUrl, tag),
                    child: Hero(
                      tag: tag,
                      child: Material(type: MaterialType.transparency, child: picture),
                    ),
                  );
                }
                spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: picture));
              } else {
                final callback = widget.onUrl;
                final known = widget.links[token.value];
                var kind = known?.kind ?? linkKindOf(token.value);
                if (kind == LinkKind.web && isVideoLink(token.value)) kind = LinkKind.video;
                Widget link = InlineLinkLabel(
                  icon: linkKindIcon(kind),
                  label: _linkLabel(known?.label ?? '', kind),
                  style: style,
                );
                if (callback != null) {
                  link = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => callback(token.value),
                    child: link,
                  );
                }
                spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: link));
              }
            case _TokenKind.emoji:
              final url = EmojiStore.instance.urlFor(token.value);
              if (url == null) {
                spans.add(TextSpan(text: token.value));
              } else {
                final size = (style.fontSize ?? 16) * 1.25;
                spans.add(WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: SmartImage(
                      url: url,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                    ),
                  ),
                ));
              }
          }
        }
        return Text.rich(
          TextSpan(style: style, children: spans),
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  InlineSpan _link(String text, Color color, VoidCallback? onTap) {
    if (onTap == null) {
      return TextSpan(text: text, style: TextStyle(color: color));
    }
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return TextSpan(
      text: text,
      style: TextStyle(color: color),
      recognizer: recognizer,
    );
  }
}

/// A link in running text drawn as an icon and a word, in the accent colour and the text's size:
/// 查看图片, 网页链接, 查看视频.
class InlineLinkLabel extends StatelessWidget {
  const InlineLinkLabel({super.key, required this.icon, required this.label, this.style});

  final IconData icon;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final base = style ?? DefaultTextStyle.of(context).style;
    final size = base.fontSize ?? 15;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: color),
        SizedBox(width: size * 0.15),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(color: color, height: 1.2),
          ),
        ),
      ],
    );
  }
}

IconData linkKindIcon(LinkKind kind) => switch (kind) {
      LinkKind.web => Icons.link_rounded,
      LinkKind.video => Icons.smart_display_outlined,
      LinkKind.article => Icons.article_outlined,
      LinkKind.place => Icons.place_outlined,
      LinkKind.superTopic => Icons.diamond_outlined,
      LinkKind.vote => Icons.how_to_vote_outlined,
      LinkKind.lottery => Icons.redeem_outlined,
      LinkKind.group => Icons.groups_outlined,
    };

/// A link reads as its own words when the post gave some, and a super topic says that it is one.
String _linkLabel(String label, LinkKind kind) {
  final words = label.trim();
  if (words.isEmpty) return linkKindLabel(kind);
  if (kind == LinkKind.superTopic && !words.endsWith('超话')) return '$words超话';
  return words;
}

/// Weibo's own video pages; the post text links a video with one of these.
bool isVideoLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (host == 'video.weibo.com') return true;
  if (host.endsWith('weibo.com') && path.startsWith('/tv/')) return true;
  if (host == 'm.weibo.cn' && path.startsWith('/s/video')) return true;
  final object = uri.queryParameters['fid'] ?? uri.queryParameters['object_id'] ?? '';
  return object.startsWith('1034:');
}

String? _inlineImageUrl(String value) {
  var candidate = value;
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.host == 'weibo.cn' && parsed.path.contains('sinaurl')) {
    candidate = parsed.queryParameters['u'] ?? value;
  }
  final clean = sanitizeImageUrl(candidate);
  final path = Uri.tryParse(clean)?.path.toLowerCase() ?? '';
  for (final extension in ['.jpg', '.jpeg', '.png', '.gif', '.webp']) {
    if (path.endsWith(extension)) return clean;
  }
  return null;
}

String _mentionName(String token) => token.startsWith('@') ? token.substring(1) : token;
String _topicName(String token) => token.replaceAll('#', '');

List<_Token> _tokenize(String text) {
  final tokens = <_Token>[];
  var plainStart = 0;
  var index = 0;

  void emit(_Token token) {
    if (plainStart < token.start) {
      tokens.add(_Token(_TokenKind.plain, plainStart, token.start, text.substring(plainStart, token.start)));
    }
    tokens.add(token);
    plainStart = token.end;
    index = token.end;
  }

  while (index < text.length) {
    final char = text[index];
    _Token? token;
    if (char == '@') {
      token = _parseMention(text, index);
    } else if (char == '#') {
      token = _parseTopic(text, index);
    } else if (char == 'h' || char == 'H') {
      token = _parseUrl(text, index);
    } else if (char == '[') {
      token = _parseEmoji(text, index);
    }
    if (token != null) {
      emit(token);
    } else {
      index++;
    }
  }
  if (plainStart < text.length) {
    tokens.add(_Token(_TokenKind.plain, plainStart, text.length, text.substring(plainStart)));
  }
  return tokens;
}

bool _isNameChar(int code) {
  if (code == 95 || code == 45) return true; // _ -
  if (code >= 48 && code <= 57) return true;
  if (code >= 65 && code <= 90) return true;
  if (code >= 97 && code <= 122) return true;
  if (code <= 127) return false;
  // A mention ends at Chinese punctuation. Treating every non-ASCII code point
  // as a name character made "@name：正文" one giant blue link.
  final char = String.fromCharCode(code);
  if (code == 0x00B7) return true; // ·
  return RegExp(r'[\u3400-\u9FFF\u3040-\u30FF\uAC00-\uD7AF\u00C0-\u024F]').hasMatch(char);
}

_Token? _parseMention(String text, int at) {
  if (at > 0) {
    final previous = text.codeUnitAt(at - 1);
    if (previous < 128 && (_isNameChar(previous))) return null;
  }
  var end = at + 1;
  while (end < text.length && _isNameChar(text.codeUnitAt(end))) {
    end++;
  }
  if (end == at + 1) return null;
  return _Token(_TokenKind.mention, at, end, text.substring(at, end));
}

_Token? _parseTopic(String text, int open) {
  final limit = open + 52 < text.length ? open + 52 : text.length;
  var close = open + 1;
  while (close < limit && text[close] != '#') {
    if (text[close] == '\n') return null;
    close++;
  }
  if (close >= limit || text[close] != '#') return null;
  final name = text.substring(open + 1, close);
  if (name.isEmpty || name.trim() != name) return null;
  return _Token(_TokenKind.topic, open, close + 1, text.substring(open, close + 1));
}

_Token? _parseEmoji(String text, int open) {
  final limit = open + 14 < text.length ? open + 14 : text.length;
  var close = open + 1;
  while (close < limit && text[close] != ']') {
    if (text[close] == '[' || text[close].trim().isEmpty) return null;
    close++;
  }
  if (close >= limit || close == open + 1) return null;
  return _Token(_TokenKind.emoji, open, close + 1, text.substring(open, close + 1));
}

const _urlTrailing = '.,;:!?)]}\'"，。；：！？）】';
const _urlSpecial = "-._~:/?#[]@!\$&'()*+,;=%";

_Token? _parseUrl(String text, int start) {
  final lower = text.substring(start).toLowerCase();
  final int prefixLength;
  if (lower.startsWith('https://')) {
    prefixLength = 8;
  } else if (lower.startsWith('http://')) {
    prefixLength = 7;
  } else {
    return null;
  }
  if (start > 0) {
    final previous = text.codeUnitAt(start - 1);
    if (previous < 128 && ((previous >= 48 && previous <= 57) || (previous >= 65 && previous <= 90) || (previous >= 97 && previous <= 122))) {
      return null;
    }
  }
  var end = start + prefixLength;
  while (end < text.length) {
    final char = text[end];
    final code = char.codeUnitAt(0);
    final asciiAllowed = code >= 48 && code <= 57 || code >= 65 && code <= 90 || code >= 97 && code <= 122;
    if (!asciiAllowed && !_urlSpecial.contains(char)) break;
    end++;
  }
  while (end > start + prefixLength && _urlTrailing.contains(text[end - 1])) {
    end--;
  }
  if (end == start + prefixLength) return null;
  return _Token(_TokenKind.url, start, end, text.substring(start, end));
}