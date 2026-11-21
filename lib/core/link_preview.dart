import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api.dart';
import 'entities.dart';
import 'links.dart';
import 'models.dart';
import 'parse.dart';
import 'session.dart';

/// What a link points at: a full Weibo [status] or [user], or a page's title, description and cover.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.site,
    this.imageUrl,
    this.kind = LinkKind.web,
    this.status,
    this.user,
  });

  /// Where the link really goes, after t.cn and Weibo's warning page.
  final String url;
  final String? title;
  final String? description;
  final String? site;
  final String? imageUrl;
  final LinkKind kind;

  /// Populated when the link points at a Weibo status, so chat can draw a dedicated post card.
  final Status? status;

  /// Populated when the link points at a Weibo user profile.
  final User? user;
}

/// Previews for the links in private and group messages, fetched once per address and kept in a
/// bounded LRU cache for the session. Transient network failures are not pinned so a later view
/// can retry.
class LinkPreviews {
  LinkPreviews._();
  static final LinkPreviews instance = LinkPreviews._();

  static const int _kept = 100;

  final Map<String, Future<LinkPreview?>> _cache = {};
  HttpClient? _client;

  HttpClient get _http {
    final client = _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 5);
    client.userAgent = Session.instance.userAgent;
    return client;
  }

  Future<LinkPreview?> of(String url, {ChatLinkMeta? meta}) {
    final key = meta?.targetUrl ?? url;
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
      return existing;
    }
    final future = _load(key, url, meta: meta);
    _cache[key] = future;
    if (_cache.length > _kept) _cache.remove(_cache.keys.first);
    return future;
  }

  Future<LinkPreview?> _load(String cacheKey, String raw, {ChatLinkMeta? meta}) async {
    var url = unwrapWeiboRedirect((meta?.targetUrl ?? raw).trim());
    if (linkTargetOf(url) is ShortLinkTarget) {
      url = unwrapWeiboRedirect(await expandShortLink(url) ?? url);
    }
    // If webim's `url_objects` already gave us an embedded status, try fetching full details for
    // multi-image/video/counts and fall back to the embedded copy immediately on error.
    if (meta?.status != null) {
      final embedded = meta!.status!;
      final full = embedded.id.isNotEmpty
          ? await WeiboApi.instance.status(embedded.id).catchError((Object _) => null)
          : null;
      final resolved = Entities.instance.put(full ?? embedded);
      return _ofStatus(url, resolved);
    }
    if (meta?.user != null) {
      return _ofUser(url, meta!.user!);
    }

    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    final kind = linkKindOf(url);
    switch (linkTargetOf(url)) {
      case StatusTarget(:final id):
        final status = await WeiboApi.instance.status(id).catchError((Object _) => null);
        if (status == null) {
          _cache.remove(cacheKey);
          return LinkPreview(url: url, title: '微博', site: '微博');
        }
        return _ofStatus(url, Entities.instance.put(status));
      case UserTarget(:final user):
        if (RegExp(r'^\d+$').hasMatch(user)) {
          final profile = await WeiboApi.instance.user(user).catchError((Object _) => null);
          if (profile != null) return _ofUser(url, profile);
        }
        return LinkPreview(url: url, title: '微博用户主页', site: '微博');
      case TopicTarget(:final name):
        return LinkPreview(url: url, title: '#$name#', site: '微博话题', kind: LinkKind.web);
      case SuperTopicTarget(:final name):
        return LinkPreview(
          url: url,
          title: name.isEmpty ? '超话' : '$name超话',
          site: '微博超话',
          kind: LinkKind.superTopic,
        );
      case WebTarget() || ShortLinkTarget():
        if (meta != null && (meta.title?.isNotEmpty ?? false)) {
          return LinkPreview(
            url: url,
            title: meta.title,
            description: meta.description,
            site: meta.site ?? siteNameOf(url) ?? host,
            imageUrl: meta.imageUrl,
            kind: kind,
          );
        }
        // Weibo's own pages answer a client without the login with the login page.
        if (_weiboHost(host)) {
          return LinkPreview(url: url, title: _weiboPageTitle(url), site: siteNameOf(url) ?? host, kind: kind);
        }
        return _ofPage(cacheKey, url, host, kind);
      case AppOnlyTarget() || ClientPageTarget():
        return LinkPreview(
          url: url,
          title: meta?.title ?? '需要在客户端中查看',
          description: meta?.description,
          site: meta?.site ?? siteNameOf(url) ?? host,
          imageUrl: meta?.imageUrl,
          kind: kind,
        );
    }
  }

  LinkPreview _ofStatus(String url, Status status) {
    final text = status.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final picture = status.media.where((m) => m.kind == MediaKind.image).firstOrNull?.previewUrl ??
        status.media.where((m) => m.kind == MediaKind.video).firstOrNull?.previewUrl;
    return LinkPreview(
      url: url,
      title: '@${status.author.screenName}',
      description: text.isEmpty ? (status.repostOf == null ? null : '转发微博') : text,
      site: '微博',
      imageUrl: picture != null && picture.isNotEmpty ? picture : null,
      status: status,
    );
  }

  LinkPreview _ofUser(String url, User user) {
    final desc = user.description;
    return LinkPreview(
      url: url,
      title: user.screenName,
      description: desc.isEmpty ? null : desc,
      site: '微博用户',
      imageUrl: (user.avatarUrl?.isNotEmpty ?? false) ? user.avatarUrl : null,
      user: user,
    );
  }

  /// The page's own title and description, read from the head of its HTML.
  Future<LinkPreview> _ofPage(String cacheKey, String url, String host, LinkKind kind) async {
    final site = siteNameOf(url) ?? host;
    try {
      final request = await _http.getUrl(Uri.parse(secureLink(url)));
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*;q=0.8');
      final response = await request.close().timeout(const Duration(seconds: 6));
      final type = response.headers.contentType;
      if (response.statusCode >= 400 || (type != null && type.mimeType != 'text/html')) {
        await response.drain<void>();
        return LinkPreview(url: url, site: site, kind: kind);
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
        final content = tag == null
            ? null
            : RegExp('content=["\']([^"\']*)["\']', caseSensitive: false).firstMatch(tag)?.group(1);
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
        kind: kind,
      );
    } catch (_) {
      _cache.remove(cacheKey);
      return LinkPreview(url: url, site: site, kind: kind);
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
