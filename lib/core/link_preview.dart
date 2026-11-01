import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api.dart';
import 'links.dart';
import 'models.dart';
import 'parse.dart';
import 'session.dart';

/// What a link points at, in a few words: a post's author and text, or a page's title.
class LinkPreview {
  const LinkPreview({required this.url, this.title, this.description, this.site, this.imageUrl});

  /// Where the link really goes, after t.cn and Weibo's warning page.
  final String url;
  final String? title;
  final String? description;
  final String? site;
  final String? imageUrl;
}

/// Previews for the links in private messages, fetched once per address and kept for the session.
class LinkPreviews {
  LinkPreviews._();
  static final LinkPreviews instance = LinkPreviews._();

  final Map<String, Future<LinkPreview?>> _cache = {};

  Future<LinkPreview?> of(String url) => _cache.putIfAbsent(url, () => _load(url));

  Future<LinkPreview?> _load(String raw) async {
    var url = unwrapWeiboRedirect(raw.trim());
    if (linkTargetOf(url) is ShortLinkTarget) url = unwrapWeiboRedirect(await expandShortLink(url) ?? url);
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    switch (linkTargetOf(url)) {
      case StatusTarget(:final id):
        final status = await WeiboApi.instance.status(id).catchError((Object _) => null);
        if (status == null) return LinkPreview(url: url, title: '微博', site: '微博');
        return _ofStatus(url, status);
      case UserTarget():
        return LinkPreview(url: url, title: '微博用户主页', site: '微博');
      case TopicTarget(:final name):
        return LinkPreview(url: url, title: '#$name#', site: '微博话题');
      case SuperTopicTarget(:final name):
        return LinkPreview(url: url, title: name.isEmpty ? '超话' : '$name超话', site: '微博超话');
      case WebTarget() || ShortLinkTarget():
        // Weibo's own pages answer a client without the login with the login page.
        if (_weiboHost(host)) return LinkPreview(url: url, title: _weiboPageTitle(url), site: host);
        return _ofPage(url, host);
      case AppOnlyTarget() || ClientPageTarget():
        return LinkPreview(url: url, title: '需要在客户端中查看', site: siteNameOf(url) ?? host);
    }
  }

  LinkPreview _ofStatus(String url, Status status) {
    final text = status.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final picture = status.media.where((m) => m.kind == MediaKind.image).firstOrNull?.previewUrl;
    return LinkPreview(
      url: url,
      title: '@${status.author.screenName}',
      description: text.isEmpty ? (status.repostOf == null ? null : '转发微博') : text,
      site: '微博',
      imageUrl: picture,
    );
  }

  /// The page's own title and description, read from the head of its HTML.
  Future<LinkPreview> _ofPage(String url, String host) async {
    final site = siteNameOf(url) ?? host;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..userAgent = Session.instance.userAgent;
    try {
      final request = await client.getUrl(Uri.parse(secureLink(url)));
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*;q=0.8');
      final response = await request.close().timeout(const Duration(seconds: 6));
      final type = response.headers.contentType;
      if (response.statusCode >= 400 || (type != null && type.mimeType != 'text/html')) {
        await response.drain<void>();
        return LinkPreview(url: url, site: site);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 6))) {
        bytes.addAll(chunk);
        if (bytes.length > 192 * 1024) break;
      }
      final html = utf8.decode(bytes, allowMalformed: true);
      String? meta(String name) {
        final tag = RegExp(
          '<meta[^>]+(?:property|name)=["\']$name["\'][^>]*>',
          caseSensitive: false,
        ).firstMatch(html)?.group(0);
        final content = tag == null ? null : RegExp('content=["\']([^"\']*)["\']', caseSensitive: false).firstMatch(tag)?.group(1);
        final value = content == null ? null : decodeHtmlEntities(content).trim();
        return value == null || value.isEmpty ? null : value;
      }

      final titleTag = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html)?.group(1);
      var title = meta('og:title') ?? (titleTag == null ? null : decodeHtmlEntities(titleTag).trim());
      if (title != null && _wall.hasMatch(title)) title = null;
      final image = meta('og:image');
      return LinkPreview(
        url: url,
        title: title == null || title.isEmpty ? null : title,
        description: meta('og:description') ?? meta('description'),
        site: meta('og:site_name') ?? site,
        imageUrl: image == null ? null : Uri.parse(url).resolve(image).toString(),
      );
    } catch (_) {
      return LinkPreview(url: url, site: site);
    } finally {
      client.close(force: true);
    }
  }
}

/// Titles of the pages sites put in front of a client that is not logged in.
final _wall = RegExp(r'^(登录|登錄|Sign in|Log in|Sina Visitor System|访客)', caseSensitive: false);

bool _weiboHost(String host) => host == 'weibo.com' || host.endsWith('.weibo.com') || host.endsWith('weibo.cn');

String _weiboPageTitle(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.contains('vip')) return '微博会员页面';
  if (host.startsWith('video.') || host.startsWith('h5.video.')) return '微博视频';
  if (host.startsWith('card.') || host.contains('article')) return '微博文章';
  if (host.contains('game')) return '微博游戏';
  if (host.contains('shop')) return '微博小店';
  return '微博页面';
}

String secureLink(String url) => url.replaceFirst(RegExp('^http:', caseSensitive: false), 'https:');
