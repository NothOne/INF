import 'dart:io';

import 'models.dart';

/// Where a link in a post, a comment, a chat or a web page should take the reader.
sealed class LinkTarget {
  const LinkTarget();
}

class StatusTarget extends LinkTarget {
  /// A numeric mid or the short bid; m.weibo.cn takes either.
  final String id;
  const StatusTarget(this.id);
}

class UserTarget extends LinkTarget {
  /// A numeric uid, or a screen name to look up.
  final String user;
  const UserTarget(this.user);
}

class TopicTarget extends LinkTarget {
  final String name;
  const TopicTarget(this.name);
}

class SuperTopicTarget extends LinkTarget {
  final String containerId;
  final String name;
  const SuperTopicTarget(this.containerId, this.name);
}

/// t.cn: where it goes is only known after asking.
class ShortLinkTarget extends LinkTarget {
  final String url;
  const ShortLinkTarget(this.url);
}

class WebTarget extends LinkTarget {
  final String url;
  const WebTarget(this.url);
}

/// Only the Weibo app understands it (a `sinaweibo://` page with no web twin).
class AppOnlyTarget extends LinkTarget {
  final String url;
  const AppOnlyTarget(this.url);
}

/// A web address whose page only works inside the Weibo app: a wbox mini program (medals, match
/// ratings) or an article column. In a browser it just asks for the app.
class ClientPageTarget extends LinkTarget {
  final String url;

  /// The same page as the Weibo app opens it.
  final String appUrl;
  const ClientPageTarget(this.url, this.appUrl);
}

/// The Weibo app's own browser, which runs wbox pages.
String weiboAppBrowserUrl(String url) => 'sinaweibo://browser?url=${Uri.encodeComponent(url)}';

/// The 文章专栏 wbox app; a column is the app opened on its `cid`.
ClientPageTarget _column(String cid) {
  final url = 'https://m.weibo.cn/c/wbox?id=wqh75bb2ni&cid=$cid';
  return ClientPageTarget(url, weiboAppBrowserUrl(url));
}

/// An article column's id from `weibo.com/a/hot/<cid>_1.html` or `m.weibo.cn/p/232718<cid>`.
String? _columnId(List<String> parts) {
  if (parts.length == 3 && parts[0] == 'a' && parts[1] == 'hot') {
    return RegExp(r'^(\d+)_\d+\.html$').firstMatch(parts[2])?.group(1);
  }
  if (parts.length == 2 && parts[0] == 'p' && parts[1].startsWith('232718')) return parts[1].substring(6);
  return null;
}

const _weiboHosts = {'m.weibo.cn', 'weibo.cn', 'weibo.com', 'www.weibo.com', 'm.weibo.com', 'd.weibo.com'};
final _numeric = RegExp(r'^\d+$');
final _bid = RegExp(r'^[0-9A-Za-z]{8,10}$');

/// The super-topic containers: `100808` plus a hex id.
bool isSuperTopicContainer(String? containerId) => containerId != null && containerId.startsWith('100808');

LinkTarget linkTargetOf(String raw) {
  final url = unwrapWeiboRedirect(raw.trim());
  final uri = Uri.tryParse(url);
  if (uri == null) return AppOnlyTarget(url);
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'sinaweibo') return _appSchemeTarget(uri, url);
  if (scheme != 'http' && scheme != 'https') return AppOnlyTarget(url);

  final host = uri.host.toLowerCase();
  if (host == 't.cn') return ShortLinkTarget(url);
  if (!_weiboHosts.contains(host)) return WebTarget(url);

  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  final first = parts.isEmpty ? '' : parts[0];
  if (host == 'm.weibo.cn' && parts.length == 2 && first == 'c' && parts[1] == 'wbox') {
    return ClientPageTarget(url, weiboAppBrowserUrl(url));
  }
  final column = _columnId(parts);
  if (column != null && column.isNotEmpty) return _column(column);
  if (parts.length >= 2) {
    if ((first == 'detail' || first == 'status') && parts.length == 2) return StatusTarget(parts[1]);
    if ((first == 'u' || first == 'profile') && _numeric.hasMatch(parts[1])) return UserTarget(parts[1]);
    if (first == 'n') return UserTarget(parts[1]);
    if (_numeric.hasMatch(first) && parts.length == 2 && (_numeric.hasMatch(parts[1]) || _bid.hasMatch(parts[1]))) {
      return StatusTarget(parts[1]);
    }
  }
  if (first == 'p') {
    final container = parts.length >= 2 && parts[1] != 'index' ? parts[1] : uri.queryParameters['containerid'];
    if (isSuperTopicContainer(container)) return SuperTopicTarget(container!, _superTopicName(uri));
  }
  if (first == 'search' || first == 'searchs') {
    final topic = _topicOf(uri);
    if (topic != null) return TopicTarget(topic);
  }
  if (parts.length == 1 && _numeric.hasMatch(first) && host != 'weibo.cn') return UserTarget(first);
  return WebTarget(url);
}

LinkTarget _appSchemeTarget(Uri uri, String url) {
  final query = uri.queryParameters;
  switch (uri.host.toLowerCase()) {
    case 'detail' || 'mblogdetail' || 'mblog':
      final id = query['mblogid'] ?? query['mid'] ?? query['id'];
      if (id != null && id.isNotEmpty) return StatusTarget(id);
    case 'userinfo' || 'profile':
      final uid = query['uid'] ?? query['nick'];
      if (uid != null && uid.isNotEmpty) return UserTarget(uid);
    case 'searchall' || 'search':
      final topic = _topicOf(uri);
      if (topic != null) return TopicTarget(topic);
    case 'pageinfo' || 'cardlist':
      final container = query['containerid'];
      if (isSuperTopicContainer(container)) return SuperTopicTarget(container!, _superTopicName(uri));
      if (container != null && container.isNotEmpty) {
        return WebTarget('https://m.weibo.cn/p/index?containerid=${Uri.encodeQueryComponent(container)}');
      }
    case 'browser':
      final inner = query['url'];
      if (inner != null && inner.isNotEmpty) return linkTargetOf(inner);
    case 'video':
      final object = query['object_id'] ?? query['fid'];
      if (object != null && object.isNotEmpty) {
        return WebTarget('https://video.weibo.com/show?fid=${Uri.encodeQueryComponent(object)}');
      }
  }
  return AppOnlyTarget(url);
}

/// `#话题#` from a search link, whether the query sits in `q`, `extparam` or inside `containerid`.
String? _topicOf(Uri uri) {
  final query = uri.queryParameters;
  // containerid carries a query of its own (`231522type=1&t=10&q=#话题#`), already decoded once.
  final candidates = <String?>[query['q'], query['containerid'], query['extparam']];
  for (final candidate in candidates) {
    final value = candidate?.trim();
    if (value == null || value.isEmpty) continue;
    final match = RegExp(r'#([^#]+)#').firstMatch(value);
    if (match != null) return match.group(1)!.trim();
  }
  return null;
}

String _superTopicName(Uri uri) {
  final name = uri.queryParameters['extparam'] ?? '';
  return name.split('|').first.replaceAll('#', '').trim();
}

const _appNames = {
  'sinaweibo': '微博',
  'bilibili': '哔哩哔哩',
  'cctvnews': '央视新闻',
  'yangshipin': '央视频',
  'zhihu': '知乎',
  'snssdk1128': '抖音',
  'snssdk141': '今日头条',
  'kwai': '快手',
  'ksnebula': '快手',
  'xhsdiscover': '小红书',
  'douban': '豆瓣',
  'weixin': '微信',
  'mqq': 'QQ',
  'taobao': '淘宝',
  'tbopen': '淘宝',
  'openapp.jdmobile': '京东',
  'pinduoduo': '拼多多',
  'imeituan': '美团',
  'dianping': '大众点评',
  'alipays': '支付宝',
  'alipay': '支付宝',
  'orpheus': '网易云音乐',
  'qqmusic': 'QQ 音乐',
  'tenvideo': '腾讯视频',
  'iqiyi': '爱奇艺',
  'youku': '优酷',
  'baiduboxapp': '百度',
};

const _siteNames = {
  'bilibili.com': '哔哩哔哩',
  'b23.tv': '哔哩哔哩',
  'zhihu.com': '知乎',
  'douyin.com': '抖音',
  'xiaohongshu.com': '小红书',
  'xhslink.com': '小红书',
  'mp.weixin.qq.com': '微信公众号',
  'v.qq.com': '腾讯视频',
  'cctv.com': '央视网',
  'cctvnews.cctv.com': '央视新闻',
  'douban.com': '豆瓣',
  'youtube.com': 'YouTube',
  'youtu.be': 'YouTube',
  'github.com': 'GitHub',
  'music.163.com': '网易云音乐',
  'taobao.com': '淘宝',
  'tmall.com': '天猫',
  'jd.com': '京东',
};

/// The site a link card points at, by its host or a parent domain; null for others.
String? siteNameOf(String url) {
  var host = Uri.tryParse(unwrapWeiboRedirect(url))?.host.toLowerCase() ?? '';
  while (host.isNotEmpty) {
    final name = _siteNames[host];
    if (name != null) return name;
    final dot = host.indexOf('.');
    if (dot < 0) break;
    host = host.substring(dot + 1);
  }
  return null;
}

/// Which app a page's jump (`bilibili://…`, `intent://…#Intent;scheme=bilibili;…`) is for. Null
/// when it is not one INF knows by name.
String? appNameOf(String url) {
  var scheme = Uri.tryParse(url)?.scheme.toLowerCase() ?? url.split(':').first.toLowerCase();
  if (scheme == 'intent') {
    scheme = RegExp(r'[#;]scheme=([^;]+)').firstMatch(url)?.group(1)?.toLowerCase() ?? '';
  }
  return _appNames[scheme];
}

/// The link in something pasted: a bare address, or the text the Weibo app copies when sharing
/// (`【标题】… https://weibo.com/…`). Null when there is none, so the text is a search.
String? linkInText(String text) {
  final match = RegExp(r'(?:https?|sinaweibo)://[^\s，。！？、）)\]】>"“”]+', caseSensitive: false).firstMatch(text);
  if (match != null) return match.group(0);
  final bare = RegExp(r'^(?:t\.cn|(?:m\.)?weibo\.(?:cn|com))/\S+$', caseSensitive: false).firstMatch(text.trim());
  return bare == null ? null : 'https://${bare.group(0)}';
}

/// weibo.cn/sinaurl?u=… is Weibo's warning page in front of an outside link.
String unwrapWeiboRedirect(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final host = uri.host.toLowerCase();
  if ((host == 'weibo.cn' || host == 'm.weibo.cn') && uri.path.contains('sinaurl')) {
    final inner = uri.queryParameters['u'] ?? uri.queryParameters['toasturl'];
    if (inner != null && inner.startsWith('http')) return inner;
  }
  return url;
}

/// What the link is, from its address and the icon m.weibo.cn draws in front of it
/// (`timeline_card_small_<kind>…png`).
LinkKind linkKindOf(String url, {String? iconUrl}) {
  final icon = (iconUrl ?? '').toLowerCase();
  if (icon.contains('card_small_location')) return LinkKind.place;
  if (icon.contains('card_small_super')) return LinkKind.superTopic;
  if (icon.contains('card_small_video')) return LinkKind.video;
  if (icon.contains('card_small_article')) return LinkKind.article;
  if (icon.contains('card_small_vote')) return LinkKind.vote;
  final uri = Uri.tryParse(unwrapWeiboRedirect(url));
  if (uri == null) return LinkKind.web;
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final container = uri.queryParameters['containerid'] ?? (path.startsWith('/p/') ? path.substring(3) : '');
  if (host == 'video.weibo.com' || (host.endsWith('weibo.com') && path.startsWith('/tv/'))) return LinkKind.video;
  if (host == 'vote.weibo.com') return LinkKind.vote;
  if (host == 'lottery.media.weibo.com') return LinkKind.lottery;
  if (host == 'card.weibo.com' || path.startsWith('/ttarticle') || host == 'media.weibo.cn') return LinkKind.article;
  if (path.startsWith('/a/hot/') || container.startsWith('232718') || uri.queryParameters['id'] == 'wqh75bb2ni') {
    return LinkKind.article;
  }
  if (isSuperTopicContainer(container) || host == 'huati.weibo.com') return LinkKind.superTopic;
  if (container.startsWith('100101')) return LinkKind.place;
  if (container.startsWith('230491')) return LinkKind.group;
  return LinkKind.web;
}

/// The words for a link whose own text says nothing more than 网页链接.
String linkKindLabel(LinkKind kind) => switch (kind) {
      LinkKind.web => '网页链接',
      LinkKind.video => '查看视频',
      LinkKind.article => '文章',
      LinkKind.place => '位置',
      LinkKind.superTopic => '超话',
      LinkKind.vote => '投票',
      LinkKind.lottery => '抽奖详情',
      LinkKind.group => '群聊',
    };

/// Asks t.cn where it points without following it there. Null when it does not say.
Future<String?> expandShortLink(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  try {
    final request = await client.getUrl(Uri.parse(url.replaceFirst(RegExp('^http:', caseSensitive: false), 'https:')));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 5));
    await response.drain<void>();
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (location == null || location.isEmpty) return null;
    return Uri.parse(url).resolve(location).toString();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
