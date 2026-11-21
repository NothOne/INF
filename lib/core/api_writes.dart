part of 'api.dart';

/// Everything this app creates or changes on Weibo's side. Each goes through `_post`, which is where the captcha retry lives.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiWrites on WeiboApi {

  Future<void> setLiked(String statusId, bool liked) async {
    final path = liked ? 'api/attitudes/create' : 'api/attitudes/destroy';
    await _post(path, {
      'id': statusId,
      'attitude': 'heart',
    }, referer: '${WeiboApi._web}/detail/$statusId');
  }

  Future<void> setCommentLiked(String commentId, bool liked, {String? statusId}) async {
    final path = liked ? 'api/likes/update' : 'api/likes/destroy';
    try {
      await _post(path, {
        'id': commentId,
        'type': 'comment',
      }, referer: statusId == null ? null : '${WeiboApi._web}/detail/$statusId');
    } on ApiException catch (error) {
      // m.weibo.cn's own comment like answers the same for an account it holds back.
      if (error.code == 20000) throw ApiException('微博暂时不让这个账号给评论点赞（网页版同样失败），请稍后再试', code: 20000);
      rethrow;
    }
  }

  /// m.weibo.cn's own menu posts these; the path names are its own.
  Future<void> setFavorited(String statusId, bool favorited) async {
    final path = favorited ? 'api/statuses/createfav' : 'api/statuses/destroyfav';
    await _post(path, {'id': statusId}, referer: '${WeiboApi._web}/detail/$statusId');
  }

  Future<String> uploadImage(File file, {String? referer}) async {
    final st = await _token(refresh: true);
    final response = await _dio.post(
      'api/statuses/uploadPic',
      data: FormData.fromMap({
        'type': 'json',
        'st': st,
        'pic': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split(Platform.pathSeparator).last,
          contentType: DioMediaType.parse(_imageType(file.path)),
        ),
      }),
      options: Options(headers: {
        'X-XSRF-TOKEN': st,
        'Origin': WeiboApi._web,
        // The same upload serves a post and a comment; each sends the page it is written on.
        'Referer': referer ?? '${WeiboApi._web}/compose/',
      }),
    );
    final root = _decodeEnvelope(response, false, returnRoot: true);
    final direct = textOf(asMap(root)?['pic_id']);
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = textOf(asMap(asMap(root)?['data'])?['pic_id']);
    if (nested != null && nested.isNotEmpty) return nested;
    throw ApiException('图片上传失败');
  }

  Future<String> uploadCommentImage(String statusId, File file) =>
      uploadImage(file, referer: '${WeiboApi._web}/detail/$statusId');

  Future<void> postStatus(
    String content,
    List<String> picIds, {
    PostVisibility visibility = PostVisibility.public,
    ContentStatement statement = ContentStatement.none,
    VideoUploadResult? video,
    String? videoTitle,
  }) async {
    final needsWeiboCom =
        video != null || visibility != PostVisibility.public || statement != ContentStatement.none;
    final (cookie, _) = await WeiboComSession.instance.cookie();
    if (WeiboComSession.hasAuth(cookie)) {
      final fields = buildWeiboComPostFields(
        content: content,
        picIds: picIds,
        visibility: visibility,
        statement: statement,
        video: video,
        videoTitle: videoTitle,
      );
      try {
        await _postWeiboComForm('statuses/update', fields, referer: 'https://weibo.com/');
        return;
      } on LoginRequiredException {
        // Plain public posts can still go through m.weibo.cn if only the weibo.com session expired.
        if (needsWeiboCom) rethrow;
      }
    }
    if (needsWeiboCom) {
      throw ApiException('当前功能需要 weibo.com 登录态，请在「我的 → 账号」重新登录');
    }
    await _post('api/statuses/update', {
      'content': content,
      if (picIds.isNotEmpty) 'picId': picIds.join(','),
    }, referer: '${WeiboApi._web}/compose/');
  }

  Future<void> repost(
    String statusId,
    String content,
    bool alsoComment, {
    List<String> picIds = const [],
    PostVisibility visibility = PostVisibility.public,
  }) async {
    final needsWeiboCom = picIds.isNotEmpty || visibility != PostVisibility.public;
    final (cookie, _) = await WeiboComSession.instance.cookie();
    if (WeiboComSession.hasAuth(cookie)) {
      final fields = buildWeiboComRepostFields(
        statusId: statusId,
        content: content,
        alsoComment: alsoComment,
        picIds: picIds,
        visibility: visibility,
      );
      try {
        await _postWeiboComForm('statuses/normal_repost', fields, referer: 'https://weibo.com/');
        return;
      } on LoginRequiredException {
        if (needsWeiboCom) rethrow;
      }
    }
    if (needsWeiboCom) {
      throw ApiException('转发带图或设置可见范围需要 weibo.com 登录态，请重新登录');
    }
    await _post('api/statuses/repost', {
      'id': statusId,
      'mid': statusId,
      'content': content,
      if (alsoComment) 'dualPost': '1',
    }, referer: '${WeiboApi._web}/compose/');
  }

  /// Uploads a local video file through weibo.com's 4-step chunked multimedia pipeline
  /// (`dispatch` → `init` → binary chunks with per-chunk MD5 → `check` → optional cover screenshot).
  Future<VideoUploadResult> uploadVideo(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    const source = '339644097';
    final (cookie, _) = await WeiboComSession.instance.cookie();
    if (!WeiboComSession.hasAuth(cookie)) {
      throw ApiException('上传视频需要 weibo.com 登录态，请重新登录');
    }
    final size = await file.length();
    if (size <= 0) throw ApiException('视频文件为空');
    final fileName = file.path.split(Platform.pathSeparator).last;

    // 1. Dispatch: obtain upload host URLs.
    final dispatchRaw = await _postWeiboComForm(
      'multimedia/dispatch',
      {
        'source': source,
        'types': 'video',
        'version': '4',
        'auth_accept': 'video',
        'size': '$size',
        'timeout': '180000',
      },
      referer: 'https://weibo.com/',
    );
    final videoEndpoints = asMap(asMap(asMap(dispatchRaw)?['data'])?['video']);
    final initUrl = textOf(videoEndpoints?['init_url']);
    final uploadUrl = textOf(videoEndpoints?['upload_url']);
    final checkUrl = textOf(videoEndpoints?['check_url']);
    if (initUrl == null || uploadUrl == null || checkUrl == null) {
      throw ApiException('获取视频上传地址失败');
    }
    onProgress?.call(0.05);

    // 2. Init: declare upload session and get upload_id, media_id, auth, and chunk size.
    final sessionId = md5.convert(utf8.encode('$fileName:$size:${DateTime.now().millisecondsSinceEpoch}')).toString();
    const boundary = '----InfWeiboVideoBoundary7MA4YWxkTrZu0gW';
    final bizFile = jsonEncode({'mediaprops': jsonEncode({'screenshot': 1})});
    final initBody = '--$boundary\r\n'
        'Content-Disposition: form-data; name="biz_file"\r\n\r\n'
        '$bizFile\r\n'
        '--$boundary--\r\n';
    final Map<String, dynamic>? initMap;
    try {
      final initResp = await _publicDio.post(
        initUrl,
        queryParameters: {
          'source': source,
          'size': '$size',
          'name': fileName,
          'type': 'video',
          'client': 'web',
          'session_id': sessionId,
        },
        data: utf8.encode(initBody),
        options: Options(
          contentType: DioMediaType('multipart', 'mixed', {'boundary': boundary}).toString(),
          headers: {'Origin': 'https://weibo.com', 'Referer': 'https://weibo.com/', 'Cookie': cookie},
        ),
      );
      initMap = asMap(initResp.data is String ? jsonDecode(initResp.data as String) : initResp.data);
    } on DioException catch (error) {
      throw _dioError(error);
    }
    final uploadId = textOf(initMap?['upload_id']);
    final mediaId = textOf(initMap?['media_id']);
    final auth = textOf(initMap?['auth']);
    if (uploadId == null || mediaId == null || auth == null) {
      throw ApiException(textOf(initMap?['error']) ?? textOf(initMap?['msg']) ?? '初始化视频上传失败');
    }
    final chunkKb = intOf(asMap(initMap?['strategy'])?['chunk_size']) ?? 4096;
    final chunkSize = (chunkKb > 0 ? chunkKb : 4096) * 1024;
    final totalChunks = (size + chunkSize - 1) ~/ chunkSize;

    // 3. Stream chunks sequentially with per-chunk MD5 verification.
    final raf = await file.open();
    try {
      for (var index = 0; index < totalChunks; index++) {
        final offset = index * chunkSize;
        final length = (size - offset) < chunkSize ? (size - offset) : chunkSize;
        await raf.setPosition(offset);
        final bytes = await raf.read(length);
        final chunkMd5 = md5.convert(bytes).toString();
        try {
          await _publicDio.post(
            uploadUrl,
            queryParameters: {
              'source': source,
              'upload_id': uploadId,
              'media_id': mediaId,
              'upload_protocol': 'binary',
              'type': 'video',
              'client': 'web',
              'check': chunkMd5,
              'index': '$index',
              'size': '$length',
              'start_loc': '$offset',
              'count': '$totalChunks',
            },
            data: bytes,
            options: Options(
              contentType: DioMediaType('application', 'octet-stream').mimeType,
              headers: {
                'Origin': 'https://weibo.com',
                'Referer': 'https://weibo.com/',
                'X-Up-Auth': auth,
              },
            ),
          );
        } on DioException catch (error) {
          throw _dioError(error);
        }
        onProgress?.call(0.05 + 0.85 * ((index + 1) / totalChunks));
      }
    } finally {
      await raf.close();
    }

    // 4. Finish check.
    try {
      final finishResp = await _publicDio.post(
        checkUrl,
        data: {
          'source': source,
          'upload_id': uploadId,
          'media_id': mediaId,
          'upload_protocol': 'binary',
          'count': '$totalChunks',
          'action': 'finish',
          'size': '$size',
          'client': 'web',
          'status': '',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Origin': 'https://weibo.com',
            'Referer': 'https://weibo.com/',
            'X-Up-Auth': auth,
          },
        ),
      );
      final finishMap = asMap(finishResp.data is String ? jsonDecode(finishResp.data as String) : finishResp.data);
      if (finishMap != null && finishMap['result'] == false) {
        throw ApiException(textOf(finishMap['error']) ?? textOf(finishMap['msg']) ?? '视频合并校验失败');
      }
    } on DioException catch (error) {
      throw _dioError(error);
    }
    onProgress?.call(0.95);

    // 5. Best-effort screenshot cover poll (does not fail the upload if not ready yet).
    String? coverPid;
    String? coverUrl;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final output = await _getWeiboCom(
          'multimedia/output',
          {'source': source, 'ids': mediaId, 'labels': 'screenshot'},
          referer: 'https://weibo.com/',
        );
        final first = asMap(asList(output).firstOrNull) ?? asMap(output);
        final shots = asList(first?['screenshot'] ?? asMap(first?['outputs'])?['screenshot']);
        final shot = asMap(shots.firstOrNull);
        final pid = textOf(shot?['pid']);
        final url = textOf(shot?['url']);
        if (pid != null && pid.isNotEmpty) {
          coverPid = pid;
          coverUrl = url;
          break;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    onProgress?.call(1.0);
    return VideoUploadResult(mediaId: mediaId, coverPid: coverPid, coverUrl: coverUrl);
  }

  Future<Comment?> comment(String statusId, String content, {String? picId}) async {
    final data = await _post('api/comments/create', {
      'content': content,
      'mid': statusId,
      // A comment with a picture is the same request with the uploaded id attached; the picture is
      // uploaded exactly as a post's is, so an account weibo.com refuses pictures to gets the same
      // refusal here and nowhere else.
      'picId': ?picId,
    }, referer: '${WeiboApi._web}/detail/$statusId');
    return toComment(data, statusId);
  }

  Future<Comment?> reply(
    String statusId,
    String content, {
    required String rootId,
    required String replyToId,
    String? picId,
  }) async {
    final data = await _post('api/comments/reply', {
      'id': statusId,
      'mid': statusId,
      'cid': rootId,
      'reply': replyToId,
      'content': content,
      'picId': ?picId,
    }, referer: '${WeiboApi._web}/detail/$statusId');
    return toComment(data, statusId);
  }

  // ---- plumbing -----------------------------------------------------------------------------
}

/// Pure form-field builder for `POST https://weibo.com/ajax/statuses/update`.
Map<String, String> buildWeiboComPostFields({
  required String content,
  List<String> picIds = const [],
  PostVisibility visibility = PostVisibility.public,
  ContentStatement statement = ContentStatement.none,
  VideoUploadResult? video,
  String? videoTitle,
}) {
  final fields = <String, String>{
    'content': content,
    'visible': '${visibility.code}',
  };
  if (statement != ContentStatement.none) {
    fields['mblog_statement'] = '${statement.code}';
  }
  if (video != null) {
    final title = (videoTitle?.trim().isNotEmpty ?? false)
        ? videoTitle!.trim()
        : (content.trim().isNotEmpty ? content.trim() : '视频微博');
    final media = <String, Object>{
      'type': 'video',
      'media_id': video.mediaId,
      'titles': [
        {'title': title, 'default': 'true'},
      ],
      if (video.coverPid != null && video.coverPid!.isNotEmpty)
        'covers': [
          {'pid': video.coverPid!},
        ],
      'resource': {'video_tail': false},
    };
    fields['media'] = jsonEncode(media);
  } else if (picIds.isNotEmpty) {
    fields['pic_id'] = jsonEncode([
      for (final pid in picIds) {'type': 'image/jpeg', 'pid': pid},
    ]);
    fields['need_transcode'] = '1';
  }
  return fields;
}

/// Pure form-field builder for `POST https://weibo.com/ajax/statuses/normal_repost`.
Map<String, String> buildWeiboComRepostFields({
  required String statusId,
  required String content,
  required bool alsoComment,
  List<String> picIds = const [],
  PostVisibility visibility = PostVisibility.public,
}) =>
    {
      'id': statusId,
      'comment': content,
      'is_comment': alsoComment ? '1' : '0',
      'comment_ori': '0',
      'is_repost': '0',
      'visible': '${visibility.code}',
      if (picIds.isNotEmpty) 'pic_id': picIds.join(','),
    };
