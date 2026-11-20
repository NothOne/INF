import 'dart:convert';
import 'dart:math' as math;

import 'links.dart';
import 'models.dart';
import 'weibo_html.dart';
import 'weibo_json.dart';
import 'weibo_time.dart';

/// Everything a JSON answer becomes, plus the three things every reader of it needs: the lenient
/// scalar readers, the time and count formatting, and the HTML-to-text for a post's words. They
/// live in their own files — `weibo_json.dart`, `weibo_time.dart`, `weibo_html.dart` — because they
/// are pure and are used far from the parsers; this file re-exports them so a caller still has one
/// import for "read Weibo's answer".
export 'weibo_html.dart';
export 'weibo_json.dart';
export 'weibo_time.dart';

// ---------------------------------------------------------------------------------------------
// Users and statuses

final _defaultAvatar = RegExp(r'default_avatar_(male|female)_\d+');

/// m.weibo.cn's comments give an account still on the default avatar a dead address,
/// `ss1.sinaimg.cn/orj480/default_avatar_male_180&690`; the picture lives under `default/images`.
String defaultAvatarFixed(String url) {
  final match = _defaultAvatar.firstMatch(url);
  if (match == null || url.contains('/default/images/')) return url;
  return 'https://tvax1.sinaimg.cn/default/images/default_avatar_${match.group(1)}_180.gif';
}

User? toUser(dynamic element) {
  final json = asMap(element);
  if (json == null) return null;
  final id = idOf(json['id']);
  if (id == null) return null;
  String? avatar;
  for (final key in ['avatar_hd', 'avatar_large', 'profile_image_url']) {
    final value = textOf(json[key]);
    if (value != null && value.isNotEmpty) {
      avatar = defaultAvatarFixed(value);
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
  final html = textOf(json['text']) ?? textOf(json['raw_text']) ?? '';
  final rich = weiboHtmlToRichText(html);
  final convertedText = rich.text;
  final links = _mergeUrlStructImages(json, rich.links);
  final pageInfo = asMap(json['page_info']);
  final mixed = _mediaFromMixMedia(json);
  final List<Media> media;
  if (mixed.isNotEmpty) {
    _applyPicVideo(mixed, textOf(json['pic_video']));
    media = mixed;
  } else {
    final pics = _imagesFromPics(json);
    final baseImages = pics.isNotEmpty ? pics : _imagesFromPicInfos(json);
    final images = _completeImagesFromPicIds(json, baseImages);
    _applyPicVideo(images, textOf(json['pic_video']));
    media = <Media>[...images];
  }
  final video = _videoFrom(pageInfo);
  if (video != null && !media.any((m) => m.kind == MediaKind.video && m.url == video.url)) {
    media.add(video);
  }

  final topicNames = <String>{
    ...RegExp(r'#([^#\n]+)#').allMatches(convertedText).map((m) => m.group(1)!),
    ...asList(json['topic_struct'])
        .map((e) => textOf(asMap(e)?['topic_title']))
        .whereType<String>()
        .where((value) => value.isNotEmpty),
  }.toList();

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
        ? Place(
            textOf(pageInfo['page_title']) ?? '',
            url: _pageUrlOf(pageInfo),
            address: textOf(pageInfo['content1']),
            summary: textOf(pageInfo['content2']),
            picUrl: textOf(asMap(pageInfo['page_pic'])?['url']),
          )
        : null,
    article: _articleCard(pageInfo),
    card: _linkCard(pageInfo),
    audio: _voiceOf(asMap(json['blog_audio'])) ?? _audioFrom(pageInfo) ?? _voiceFromStub(html),
    links: links,
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

List<Media> _mediaFromMixMedia(Map<String, dynamic> json) {
  final items = asList(asMap(json['mix_media_info'])?['items']);
  if (items.isEmpty) return const [];
  final result = <Media>[];
  for (final element in items) {
    final item = asMap(element);
    if (item == null) continue;
    final type = textOf(item['type']);
    final data = asMap(item['data']);
    if (data == null) continue;
    if (type == 'video') {
      final video = _videoFrom(data);
      if (video != null) result.add(video);
    } else if (type == 'pic') {
      final image = _imageFromPicInfo(data);
      if (image != null) result.add(image);
    }
  }
  return result;
}

/// Completes picture lists when `pic_ids` carries more entries than `pics` or `pic_infos`:
/// m.weibo.cn caps `pics` at 9 on mixed-media posts and omits `pics` on some retweeted payloads,
/// while still listing every id in `pic_ids`.
List<Media> _completeImagesFromPicIds(Map<String, dynamic> json, List<Media> existing) {
  final ids = asList(json['pic_ids']).map(idOf).whereType<String>().where((id) => id.isNotEmpty).toList();
  if (ids.isEmpty) return existing;
  final seen = <String>{
    for (final media in existing) ?(picIdOfUrl(media.url) ?? picIdOfUrl(media.previewUrl)),
  };
  final missing = [for (final id in ids) if (seen.add(id)) id];
  if (missing.isEmpty) return existing;
  final host = existing.map((m) => sinaimgHostOf(m.url) ?? sinaimgHostOf(m.previewUrl)).whereType<String>().firstOrNull ??
      sinaimgHostOf(textOf(json['original_pic']) ?? textOf(json['bmiddle_pic']) ?? textOf(json['thumbnail_pic']));
  return [
    ...existing,
    for (final pid in missing) mediaFromPicId(pid, host: host),
  ];
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
    final image = _imageFromPicInfo(info);
    if (image != null) result.add(image);
  }
  return result;
}

Media? _imageFromPicInfo(Map<String, dynamic> info) {
  Map<String, dynamic>? original;
  for (final name in ['mw2000', 'largest', 'original', 'large', 'woriginal']) {
    final candidate = asMap(info[name]);
    final url = textOf(candidate?['url']);
    if (candidate != null && url != null && url.isNotEmpty) {
      original = candidate;
      break;
    }
  }
  if (original == null) return null;
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
  for (final name in ['largest', 'original', 'mw2000', 'large', 'woriginal']) {
    final candidate = asMap(info[name]);
    if (candidate != null && ((intOf(candidate['width']) ?? 0) > 0 || (intOf(candidate['height']) ?? 0) > 0)) {
      size = candidate;
      break;
    }
  }
  final url = textOf(original['url'])!;
  return Media.image(
    url,
    previewUrl: textOf(preview?['url']) ?? url,
    width: intOf(size?['width']) ?? 0,
    height: intOf(size?['height']) ?? 0,
    liveUrl: _liveUrlOf(info, 'video'),
  );
}

/// Attaches bundled picture lists from weibo.com's `url_struct` (such as 「查看2张图片」 in a
/// repost chain) onto the corresponding [WeiboLink]s in [base].
Map<String, WeiboLink> _mergeUrlStructImages(Map<String, dynamic> json, Map<String, WeiboLink> base) {
  final structs = asList(json['url_struct']).map(asMap).whereType<Map<String, dynamic>>().toList();
  if (structs.isEmpty) return base;
  var result = base;
  void attach(String key, List<Media> images, String? title) {
    if (identical(result, base)) result = Map<String, WeiboLink>.from(base);
    final existing = result[key];
    final currentLabel = existing?.label ?? '';
    final label = images.length > 1 && (currentLabel.isEmpty || currentLabel == '查看图片')
        ? (title != null && title.isNotEmpty && title != '查看图片' ? title : '查看${images.length}张图片')
        : (currentLabel.isNotEmpty ? currentLabel : (title ?? ''));
    result[key] = WeiboLink(
      url: key,
      label: label,
      kind: existing?.kind ?? LinkKind.web,
      images: images,
    );
  }

  for (final entry in structs) {
    final parsed = _completeImagesFromPicIds(entry, _imagesFromPicInfos(entry));
    if (parsed.isEmpty) continue;
    final title = textOf(entry['url_title']);
    final entryPids = {
      for (final img in parsed) ?picIdOfUrl(img.url),
    };
    var matched = false;
    for (final candidate in [textOf(entry['short_url']), textOf(entry['ori_url']), textOf(entry['h5_target_url'])]) {
      if (candidate != null && result.containsKey(candidate)) {
        attach(candidate, parsed, title);
        matched = true;
      }
    }
    for (final key in result.keys.toList()) {
      final pid = picIdOfUrl(key);
      if (pid != null && entryPids.contains(pid)) {
        attach(key, parsed, title);
        matched = true;
      }
    }
    if (!matched) {
      final fallback = parsed.first.url;
      attach(fallback, parsed, title);
    }
  }
  return result;
}

/// Folds richer media and bundled link pictures from weibo.com's `ajax/statuses/show` into the
/// [Status] parsed from m.weibo.cn, keeping m.weibo.cn's text and URLs as the anchor keys.
Status mergeStatusDetails(Status base, Status supplemental) {
  final baseVideos = base.media.where((m) => m.kind == MediaKind.video).length;
  final extraVideos = supplemental.media.where((m) => m.kind == MediaKind.video).length;
  final media = (supplemental.media.length > base.media.length ||
          (supplemental.media.length == base.media.length && extraVideos > baseVideos))
      ? supplemental.media
      : base.media;

  final byPid = <String, WeiboLink>{};
  for (final link in supplemental.links.values) {
    if (link.images.isEmpty) continue;
    for (final img in link.images) {
      final pid = picIdOfUrl(img.url) ?? picIdOfUrl(img.previewUrl);
      if (pid != null) byPid[pid] = link;
    }
  }

  var links = base.links;
  if (byPid.isNotEmpty) {
    Map<String, WeiboLink>? updated;
    for (final entry in base.links.entries) {
      final pid = picIdOfUrl(entry.key);
      final richer = pid == null ? null : byPid[pid];
      if (richer != null && richer.images.length > entry.value.images.length) {
        updated ??= Map<String, WeiboLink>.from(base.links);
        final label = richer.images.length > 1 && (entry.value.label.isEmpty || entry.value.label == '查看图片')
            ? '查看${richer.images.length}张图片'
            : entry.value.label;
        updated[entry.key] = WeiboLink(
          url: entry.key,
          label: label,
          kind: entry.value.kind,
          images: richer.images,
        );
      }
    }
    // Also attach directly for any inline image URL present in text that had no WeiboLink entry yet.
    for (final imageUrl in inlineSinaimgUrls(base.text)) {
      if ((updated ?? base.links).containsKey(imageUrl)) continue;
      final pid = picIdOfUrl(imageUrl);
      final richer = pid == null ? null : byPid[pid];
      if (richer != null && richer.images.length > 1) {
        updated ??= Map<String, WeiboLink>.from(base.links);
        updated[imageUrl] = WeiboLink(
          url: imageUrl,
          label: '查看${richer.images.length}张图片',
          images: richer.images,
        );
      }
    }
    if (updated != null) links = updated;
  }

  final repost = (base.repostOf != null && supplemental.repostOf != null && base.repostOf!.id == supplemental.repostOf!.id)
      ? mergeStatusDetails(base.repostOf!, supplemental.repostOf!)
      : base.repostOf;

  if (identical(media, base.media) && identical(links, base.links) && identical(repost, base.repostOf)) {
    return base;
  }
  return base.copyWith(media: media, links: links, repostOf: repost);
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
  final bigPic = asMap(asMap(mediaInfo?['big_pic_info'])?['pic_big']);
  final String? cover = (pagePic is Map ? textOf(pagePic['url']) : textOf(pagePic)) ?? textOf(bigPic?['url']);
  final duration = doubleOf(mediaInfo?['duration']);
  return Media.video(
    url,
    previewUrl: cover ?? '',
    durationMs: duration == null ? 0 : (duration * 1000).round(),
  );
}

/// A voice post's recording. Its `duration` is in milliseconds.
AudioClip? _voiceOf(Map<String, dynamic>? audio) {
  final url = textOf(audio?['media_url']);
  if (audio == null || url == null) return null;
  return AudioClip(
    url: _secureUrl(url),
    title: '语音',
    durationMs: intOf(audio['duration']) ?? 0,
    transcript: textOf(audio['transcript'])?.trim(),
    voice: true,
  );
}

/// A podcast or any other sound card (weibo.com's `object_type: podcast_audio`, `type: 44`). Its
/// `duration` is in seconds, like a video's.
AudioClip? _audioFrom(Map<String, dynamic>? pageInfo) {
  if (pageInfo == null) return null;
  final type = textOf(pageInfo['type']) ?? '';
  final objectType = textOf(pageInfo['object_type']) ?? '';
  if (!objectType.contains('audio') && !const {'audio', '44', 'podcast'}.contains(type)) return null;
  final media = asMap(pageInfo['media_info']);
  String? url;
  for (final key in ['stream_url_hd', 'stream_url', 'mp3_url', 'url']) {
    url = textOf(media?[key]);
    if (url != null) break;
  }
  if (url == null) return null;
  final cardInfo = asMap(pageInfo['card_info']);
  final pagePic = pageInfo['page_pic'];
  final cover = pagePic is Map ? textOf(pagePic['url']) : textOf(pagePic);
  final duration = doubleOf(media?['duration']);
  return AudioClip(
    url: _secureUrl(url),
    title: textOf(cardInfo?['title']) ?? textOf(pageInfo['page_title']) ?? textOf(pageInfo['content1']) ?? '音频',
    author: textOf(cardInfo?['author_name']) ?? textOf(asMap(media?['author_info'])?['screen_name']),
    coverUrl: textOf(cardInfo?['cover']) ?? cover,
    durationMs: duration == null ? 0 : (duration * 1000).round(),
  );
}

/// The voice clip a text-only voice post implies, its address left for weibo.com to sign at play
/// time. [voiceStub], the pattern that finds the stub, lives with the HTML reader.
AudioClip? _voiceFromStub(String html) {
  final stub = voiceStub.firstMatch(html);
  if (stub == null) return null;
  final length = _voiceLength.firstMatch(stub.group(1)!.replaceAll('&quot;', '"').trim());
  final seconds = length == null ? 0 : (int.parse(length.group(1) ?? '0') * 60 + int.parse(length.group(2)!));
  return AudioClip(url: '', title: '语音', durationMs: seconds * 1000, voice: true);
}

final _voiceLength = RegExp(r'''^(?:(\d+)')?(\d+)''');

/// http → https: Android plays no cleartext media.
String _secureUrl(String url) => url.startsWith('http://') ? 'https://${url.substring(7)}' : url;

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

/// Cards other parts of the post already show (a playable video or sound, an article, the place
/// line, a topic that is in the text) are left out; everything else gets the generic card, also
/// one Weibo left without an address or title, which [WeiboApi.cardUrl] and the fallback page
/// still open.
LinkCard? _linkCard(Map<String, dynamic>? pageInfo) {
  if (pageInfo == null || _videoFrom(pageInfo) != null || _articleCard(pageInfo) != null) return null;
  if (_audioFrom(pageInfo) != null) return null;
  final banner = _bannerCard(pageInfo);
  if (banner != null) return banner;
  final type = textOf(pageInfo['type']) ?? '';
  final objectType = textOf(pageInfo['object_type']) ?? '';
  if (const {'place', 'topic', 'search_topic', 'article'}.contains(type)) return null;
  final cardInfo = asMap(pageInfo['card_info']);
  final media = asMap(pageInfo['media_info']);
  final video = type == 'video' || objectType == 'video';
  final url = _pageUrlOf(pageInfo) ?? textOf(media?['h5_url']) ?? textOf(cardInfo?['scheme']) ?? '';
  final content1 = textOf(pageInfo['content1']);
  final content2 = textOf(pageInfo['content2']) ?? textOf(pageInfo['page_desc']);
  final pagePic = pageInfo['page_pic'];
  final image = (pagePic is Map ? textOf(pagePic['url']) : textOf(pagePic)) ?? textOf(cardInfo?['cover']) ?? textOf(cardInfo?['pic_url']);
  var title = textOf(pageInfo['page_title']) ?? textOf(cardInfo?['title']) ?? content1 ?? '';
  final kind = type == 'hudongvote' || objectType == 'hudongvote'
      ? LinkKind.vote
      : (video ? LinkKind.video : (type == 'music' || objectType.contains('audio') ? LinkKind.audio : linkKindOf(url)));
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
    'story' => '故事',
    'panorama' => '全景',
    _ when video => '视频',
    _ => kind == LinkKind.web ? (url.isEmpty ? '卡片' : siteNameOf(url) ?? '网页') : linkKindLabel(kind),
  };
  if (title.isEmpty && url.isEmpty && image == null) return null;
  if (title.isEmpty) title = video ? '这个视频无法在这里播放' : typeLabel;
  final summary = [content1, content2].firstWhere((value) => value != null && value.isNotEmpty && value != title, orElse: () => null);
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
    // Picture search draws rows of pictures, each with the post it belongs to.
    for (final pic in asList(card['pics'])) {
      final own = asMap(asMap(pic)?['mblog']);
      if (own != null && !result.any((mblog) => idOf(mblog['id']) == idOf(own['id']))) result.add(own);
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
    replyTo: _replyToOf(json),
    replies: replies,
    repliesCount: total > replies.length ? total : replies.length,
    images: images,
  );
}

/// Who a reply answers. m.weibo.cn sends the answered comment as `reply_comment`; older answers
/// carry only the name in `reply_text` ("回复@某人:…"), so that is read as the fallback. Without
/// this the 「回复 X：」 prefix never appeared on a reply — [Comment.replyTo] had no source at all.
User? _replyToOf(Map<String, dynamic> json) {
  final answered = asMap(json['reply_comment']);
  if (answered != null) {
    final user = toUser(answered['user']);
    if (user != null) return user;
  }
  final text = textOf(json['reply_text']);
  if (text == null) return null;
  final match = RegExp(r'回复\s*@([^:：\s]+)').firstMatch(text);
  final name = match?.group(1);
  if (name == null || name.isEmpty) return null;
  return User(id: '', screenName: name);
}

List<Media> _commentImages(Map<String, dynamic> comment) {
  final candidates = <Map<String, dynamic>>[
    ...asList(comment['pics']).map(asMap).whereType<Map<String, dynamic>>(),
    if (asMap(comment['pic']) != null) asMap(comment['pic'])!,
  ];
  final result = <Media>[];
  for (final item in candidates) {
    // A video in a comment is not a picture: it cannot be drawn by the picture grid, so it is
    // left out of the images rather than shown as a still frame that plays nothing.
    if (textOf(item['type']) == 'video') continue;
    final thumb = textOf(item['url']);
    // `&690` is part of the default avatar's dead address, not a picture size: it is matched on the
    // path itself, so a 690-wide thumbnail is no longer dropped as if it were an avatar.
    if (thumb == null || !thumb.startsWith('http') || thumb.contains('/default_avatar')) continue;
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

/// [maxIdType] is what the request asked for, used when the answer does not say. Weibo leaves
/// `max_id_type` out of the first page of 按时间 often enough that defaulting it to 0 turned every
/// later page back into the hot order, which repeats and reorders the comments already shown.
PageResult<Comment> parseCommentPage(Map<String, dynamic>? container, String statusId, {String? maxIdType}) {
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
  final type = intOf(pageRoot['max_id_type'])?.toString() ?? maxIdType ?? '0';
  final next = (maxId != null && maxId != '0' && items.isNotEmpty) ? '$maxId:$type' : null;
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

/// The group's title, which is where m.weibo.cn keeps its name and member count.
String? groupTitle(dynamic data) {
  final title = textOf(asMap(asMap(data)?['data'])?['title']) ?? textOf(asMap(data)?['title']);
  return (title == null || title.isEmpty) ? null : title;
}

/// The announcement out of a `bulletin`'s content, or null when it says nothing.
///
/// The content is plain text with newlines; it is run through `weiboHtmlToText` all the same, because
/// some groups keep HTML in it.
String? parseGroupNotice(dynamic content) {
  final raw = textOf(content);
  if (raw == null) return null;
  final text = weiboHtmlToText(raw).trim();
  return text.isEmpty ? null : text;
}

/// The members out of a `query_group.json` answer.
///
/// The answer carries them under `member_infos`, and some answers also under `members` — both are
/// read, because which one is populated has varied. A member's name is `screen_name`, falling back to
/// the remark the reader gave them and then to the pinyin field.
List<GroupMember> parseGroupMembers(Map<String, dynamic>? root) {
  if (root == null) return const [];
  final members = <GroupMember>[];
  final seen = <String>{};
  void add(dynamic raw) {
    final map = asMap(raw);
    if (map == null) return;
    final uid = idOf(map['uid']) ?? idOf(map['id']);
    if (uid == null || uid.isEmpty || !seen.add(uid)) return;
    final name = textOf(map['screen_name']) ??
        textOf(map['name']) ??
        textOf(map['jp']) ??
        uid;
    members.add(GroupMember(
      uid: uid,
      screenName: name,
      avatarUrl: textOf(map['profile_image_url']) ?? textOf(map['avatar']) ?? '',
      verified: boolOf(map['verified']),
      level: intOf(map['level']) ?? 0,
    ));
  }

  for (final raw in asList(root['member_infos'])) {
    add(raw);
  }
  for (final raw in asList(root['members'])) {
    add(raw);
  }
  return members;
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
    coverUrl: profileCover(textOf(info['cover_image_phone'])),
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

/// passport's `sso/v2/qrcode/image`; the code's content is the `data` parameter of its image URL.
QrLogin? parseQrLogin(dynamic data) {
  final root = asMap(data);
  if (intOf(root?['retcode']) != 20000000) return null;
  final body = asMap(root?['data']);
  final qrid = textOf(body?['qrid']);
  final image = textOf(body?['image']);
  if (qrid == null || image == null) return null;
  final scan = Uri.tryParse(image)?.queryParameters['data'];
  if (scan == null || !scan.startsWith('https://')) return null;
  return QrLogin(qrid: qrid, imageUrl: image, scanUrl: scan);
}

/// passport's `sso/v2/qrcode/check`, answered with the retcodes its own login page switches on.
QrLoginStatus parseQrLoginStatus(dynamic data) {
  final root = asMap(data);
  final message = textOf(root?['msg']);
  switch (intOf(root?['retcode'])) {
    case 20000000:
      return QrLoginStatus(QrLoginState.confirmed, message: message, url: textOf(asMap(root?['data'])?['url']));
    case 50114001:
      return QrLoginStatus(QrLoginState.waiting, message: message);
    case 50114002:
      return QrLoginStatus(QrLoginState.scanned, message: message);
    case 50114003:
    case 50114004:
    case 50114015:
      return QrLoginStatus(QrLoginState.failed, message: message);
    default:
      return QrLoginStatus(QrLoginState.waiting, message: message);
  }
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

final _channelType = RegExp(r'type(?:=|%3D)(\d+)', caseSensitive: false);

/// The tabs a search offers, from the head of its first page
/// (`cardlistInfo.cardlist_head_cards[].channel_list`, each naming its `100103type=<n>&q=…`
/// container). 用户 is put back when the list leaves it out. Null when the page does not say.
List<SearchChannel>? parseSearchChannels(dynamic data) {
  final info = asMap(asMap(data)?['cardlistInfo']);
  final channels = <SearchChannel>[];
  final seen = <int>{};
  for (final head in asList(info?['cardlist_head_cards'])) {
    for (final element in asList(asMap(head)?['channel_list'])) {
      final channel = asMap(element);
      final name = textOf(channel?['name'])?.trim();
      final container = textOf(channel?['containerid']) ?? '';
      final type = intOf(_channelType.firstMatch(container)?.group(1)) ?? intOf(channel?['id']);
      if (name == null || type == null || !seen.add(type)) continue;
      channels.add(SearchChannel(name, type));
    }
  }
  if (channels.length < 2) return null;
  if (!seen.contains(SearchChannel.users)) channels.insert(math.min(3, channels.length), const SearchChannel('用户', SearchChannel.users));
  return channels;
}

/// A search page's cards that are neither posts nor people: topics (`card_type` 8 with a
/// `title_sub`), super topics, places and whatever else a channel lists.
List<SearchEntry> parseSearchEntries(dynamic data) {
  final result = <SearchEntry>[];
  String? plain(dynamic value) {
    final text = textOf(value);
    if (text == null) return null;
    final clean = weiboHtmlToText(text).trim();
    return clean.isEmpty ? null : clean;
  }

  void visit(dynamic element) {
    final card = asMap(element);
    if (card == null) return;
    final type = intOf(card['card_type']);
    if (type != 9 && type != 11 && type != 58 && card['user'] == null && card['mblog'] == null) {
      final title = plain(card['title_sub']) ?? plain(card['title']) ?? plain(card['desc']);
      final url = textOf(card['scheme']) ?? textOf(card['openurl']);
      final subtitle = plain(card['desc1']);
      if (title != null && (url != null || subtitle != null)) {
        result.add(SearchEntry(
          title: title,
          subtitle: subtitle,
          detail: plain(card['desc2']),
          imageUrl: textOf(card['pic']) ?? textOf(card['icon']),
          url: url,
        ));
      }
    }
    for (final nested in asList(card['card_group'])) {
      visit(nested);
    }
  }

  for (final card in asList(asMap(data)?['cards'])) {
    visit(card);
  }
  return result;
}

/// weibo.com's `profile/info` `tabList`, in INF's order; the posts and 精选 tabs always come.
List<ProfileTab> parseProfileTabs(dynamic data) {
  final keys = {for (final tab in asList(asMap(data)?['tabList'])) textOf(asMap(tab)?['name'])};
  if (keys.isEmpty) return ProfileTab.fallback;
  return [
    for (final tab in ProfileTab.values)
      if (tab == ProfileTab.posts || tab == ProfileTab.featured || keys.contains(tab.key)) tab,
  ];
}

/// weibo.com's `profile/info` (tabs, `user.status_total_counter`) and `profile/detail` (facts).
ProfileExtras parseProfileExtras(dynamic info, dynamic detail) {
  final user = asMap(asMap(info)?['user']);
  final counter = asMap(user?['status_total_counter']);
  final gender = textOf(user?['gender']);
  final about = asMap(detail);
  String? plain(dynamic value) {
    final text = textOf(value)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  final ip = plain(about?['ip_location']);
  final birthday = plain(about?['birthday']);
  final createdAt = plain(about?['created_at']);
  final credit = plain(asMap(about?['sunshine_credit'])?['level']);
  return ProfileExtras(
    tabs: parseProfileTabs(info),
    interactions: intOf(counter?['total_cnt']),
    likes: intOf(counter?['like_cnt']),
    comments: intOf(counter?['comment_cnt']),
    reposts: intOf(counter?['repost_cnt']),
    facts: [
      if (ip != null) ip.startsWith('IP') ? ip : 'IP属地：$ip',
      ?birthday,
      if (createdAt != null && createdAt.length >= 10) '${createdAt.substring(0, 10)} 加入微博',
      ?credit,
      for (final label in asList(about?['label_desc'])) ?plain(asMap(label)?['name']),
    ],
    coverUrl: profileCover(textOf(user?['cover_image_phone'])),
    verified: user == null ? null : verifiedBadgeOf(user),
    vip: user == null ? null : vipIconOf(user),
    gender: gender == 'm' || gender == 'f' ? gender : null,
  );
}

/// A cover at full size. `cover_image_phone` may list several, `;`-separated, as 640px crops;
/// the two stock covers are swapped for the one weibo.com itself shows instead.
String? profileCover(String? raw) {
  final first = raw?.split(';').first.trim();
  if (first == null || first.isEmpty) return null;
  return first
      .replaceAll(RegExp(r'549d0121tw1egm1kjly3jj20hs0hsq4f|9d44112bjw1f1xl1c10tuj20hs0hs0tw'), '70ace9b7ly1ggzusnypoej20yi0yiaop')
      .replaceAll(RegExp(r'crop\.0\.0\.640\.640\.640'), 'mw2000');
}

/// weibo.com's own choice of V colour from `verified_type` and `verified_type_ext`.
VerifiedBadge? verifiedBadgeOf(Map<String, dynamic> user) {
  if (!boolOf(user['verified'])) return null;
  final type = intOf(user['verified_type']);
  final ext = intOf(user['verified_type_ext']);
  if (type == 0) {
    return switch (ext) { 1 => VerifiedBadge.gold, 2 => VerifiedBadge.orange, _ => VerifiedBadge.yellow };
  }
  if (type != null && type >= 1 && type <= 7) {
    if (ext == -1) return VerifiedBadge.grey;
    return type == 3 && ext == 53 ? VerifiedBadge.red : VerifiedBadge.blue;
  }
  return null;
}

/// The 会员 icon weibo.com draws. Its artwork stops at VIP 7, SVIP 10 and VVIP 5.
VipIcon? vipIconOf(Map<String, dynamic> user) {
  final rank = intOf(user['mbrank']) ?? 0;
  final type = intOf(user['mbtype']) ?? 0;
  if (rank <= 0 || type == 0 || type == 2) return null;
  final (kind, top, aspect) = boolOf(user['vvip'])
      ? ('vvip', 5, 77 / 28)
      : boolOf(user['svip'])
          ? ('svip', 10, 54 / 42)
          : ('vip', 7, 1.0);
  return VipIcon('https://h5.sinaimg.cn/upload/108/1866/2022/11/02/${kind}_${rank.clamp(1, top)}.png', aspect);
}

/// weibo.com's plain lists of posts, `{list}`: the profile search.
List<Status> parseStatusList(dynamic data) => _statusesOf(asList(asMap(data)?['list']));

/// weibo.com's cursor lists of posts (`profile/getWaterFallContent`, `profile/getAudioList`):
/// `{list, next_cursor}`, the cursor `-1` or `0` at the end.
PageResult<Status> parseCursorStatuses(dynamic data) {
  final root = asMap(data);
  final items = _statusesOf(asList(root?['list']));
  final next = idOf(root?['next_cursor']);
  final more = items.isNotEmpty && next != null && next != '0' && next != '-1';
  return PageResult(items, more ? next : null);
}

/// weibo.com's `profile/getImageWall`: picture ids with the post each came from, `since_id` `0`
/// at the end.
PageResult<ProfilePhoto> parseImageWall(dynamic data) {
  final root = asMap(data);
  final photos = <ProfilePhoto>[];
  for (final element in asList(root?['list'])) {
    final item = asMap(element);
    final pid = textOf(item?['pid']);
    if (item == null || pid == null) continue;
    photos.add(ProfilePhoto(
      Media.image(
        'https://wx1.sinaimg.cn/mw2000/$pid.jpg',
        previewUrl: 'https://wx1.sinaimg.cn/orj360/$pid.jpg',
        liveUrl: _liveUrlOf(item, 'video'),
      ),
      statusId: idOf(item['mid']),
    ));
  }
  final next = idOf(root?['since_id']);
  return PageResult(photos, photos.isEmpty || next == null || next == '0' ? null : next);
}

/// A post's sound out of weibo.com's copy of it, which signs the address and carries the
/// transcript.
AudioClip? audioClipOf(dynamic status) {
  final json = asMap(status);
  if (json == null) return null;
  return _voiceOf(asMap(json['blog_audio'])) ?? _audioFrom(asMap(json['page_info']));
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