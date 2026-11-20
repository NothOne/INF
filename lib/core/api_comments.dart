part of 'api.dart';

/// A post's comments, the replies under one comment, and its reposts.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiComments on WeiboApi {

  Future<PageResult<Status>> reposts(String statusId, String? cursor) {
    return _numberedPage(cursor, (page) async {
      final data = await _get(
        'api/statuses/repostTimeline',
        query: {'id': statusId, 'page': page},
        emptyIsOk: true,
        referer: '${WeiboApi._web}/detail/$statusId',
      );
      return parseReposts(data);
    });
  }

  /// [byTime] asks the first page to come back newest-first: the hot flow with
  /// `max_id_type=1` and no cursor is the same list in reverse chronological order, and its own
  /// cursor continues paging it. Later pages follow the cursor either way.
  Future<PageResult<Comment>> comments(String statusId, String? cursor, {bool byTime = false}) async {
    final parts = cursor?.split(':');
    final maxId = (parts != null && parts.length == 2) ? parts[0] : null;
    final maxIdType = (parts != null && parts.length == 2) ? parts[1] : (byTime ? '1' : '0');
    final data = await _get(
      'comments/hotflow',
      query: {
        'id': statusId,
        'mid': statusId,
        'max_id': maxId,
        'max_id_type': maxIdType,
      },
      emptyIsOk: true,
    );
    return _commentsPage(statusId, byTime: byTime, maxIdType: maxIdType)
        .accept(data, isFirstPage: maxId == null);
  }

  /// The cache the comments list is kept under: one per post and sort order.
  CachedPage<Comment> _commentsPage(String statusId, {required bool byTime, String? maxIdType}) => CachedPage<Comment>(
        key: 'comments-$statusId-${byTime ? 1 : 0}',
        parse: (data) => parseCommentPage(asMap(data), statusId, maxIdType: maxIdType ?? (byTime ? '1' : '0')),
      );

  PageResult<Comment>? cachedComments(String statusId, {bool byTime = false}) =>
      _commentsPage(statusId, byTime: byTime).read();

  Future<PageResult<Comment>> replies(String statusId, String commentId, String? cursor) async =>
      (await replyThread(statusId, commentId, cursor)).$1;

  /// A page of replies, and the comment they answer.
  Future<(PageResult<Comment>, Comment?)> replyThread(String statusId, String commentId, String? cursor) async {
    final parts = cursor?.split(':');
    final maxId = (parts != null && parts.length == 2) ? parts[0] : '0';
    final maxIdType = (parts != null && parts.length == 2) ? parts[1] : '0';
    final root = await _get(
      'comments/hotFlowChild',
      returnRoot: true,
      query: {
        'cid': commentId,
        'max_id': maxId,
        'max_id_type': maxIdType,
      },
      emptyIsOk: true,
    );
    final map = asMap(root);
    return (parseCommentPage(map, statusId, maxIdType: maxIdType), parseRootComment(map, statusId));
  }

  // ---- writes -------------------------------------------------------------------------------
}
