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

  Future<void> postStatus(String content, List<String> picIds) async {
    await _post('api/statuses/update', {
      'content': content,
      if (picIds.isNotEmpty) 'picId': picIds.join(','),
    }, referer: '${WeiboApi._web}/compose/');
  }

  Future<void> repost(String statusId, String content, bool alsoComment) async {
    await _post('api/statuses/repost', {
      'id': statusId,
      'mid': statusId,
      'content': content,
      if (alsoComment) 'dualPost': '1',
    }, referer: '${WeiboApi._web}/compose/');
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
