import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'failure.dart';
import 'haptics.dart';
import 'models.dart';
import 'session.dart';
import 'status_store.dart';
import 'temp_files.dart';
import 'weibo_com_session.dart';

/// Comments this device has sent, and the one place a comment or a reply is sent from.
///
/// Before this there were three ways to post a comment — the panel, [ComposePage] in its 评论 mode,
/// and the drafts page re-sending one — each calling the API itself and each deciding on its own
/// what to refresh afterwards. That is why the count went up on one screen and not another, and why
/// sending a comment threw the reader back to the top of the thread: the only way to make the new
/// comment appear was to reload the whole list.
///
/// Now the send happens once, in [send]. It answers with a message to show (null when the comment
/// went out), raises the post's comment count in [StatusStore] so every copy of the card agrees,
/// and keeps the comment as *pending* so the list can show it at once, marked as being sent. The
/// next refresh of that list brings the real one from the server and [settle] drops the copy.
class CommentStore extends ChangeNotifier {
  CommentStore._() {
    Session.instance.registerAccountReset(reset);
  }
  static final CommentStore instance = CommentStore._();

  /// Comments that are not on the server as far as any list knows: sent from here, and not yet
  /// picked up by a refresh. Keyed by the post they belong to, oldest first.
  final Map<String, List<Comment>> _pending = {};

  /// Replies sent from this device that have not yet appeared in a thread refresh, keyed by the
  /// top-level comment (`rootId`) they hang off.
  final Map<String, List<Comment>> _pendingReplies = {};

  /// Drops unsent/unconfirmed local comments on sign-out or account switch.
  void reset() {
    if (_pending.isEmpty && _pendingReplies.isEmpty) return;
    _pending.clear();
    _pendingReplies.clear();
    _changed();
  }

  /// Bumped when the whole set of pending comments changes, so a list can rebuild.
  final ValueNotifier<int> revision = ValueNotifier(0);

  List<Comment> pendingFor(String statusId) => List.unmodifiable(_pending[statusId] ?? const []);

  List<Comment> pendingRepliesFor(String rootId) => List.unmodifiable(_pendingReplies[rootId] ?? const []);

  /// Whether [comment] is a local placeholder without a server id yet.
  bool isPending(Comment comment) => comment.id.startsWith(_localPrefix);

  static const _localPrefix = 'local:';

  /// Sends [text] as a comment on [status], or as a reply when [rootId] is given.
  ///
  /// [replyToId] is the comment being answered, which is the root itself for a comment on a
  /// comment; the two ids are passed separately because Weibo files the reply under `cid` and names
  /// the answered comment in `reply`. Completes with the message to show the reader, or null.
  ///
  /// [crossPost] is 同时转发: post the comment and repost the post in one go, which is what Weibo's
  /// own box does with that box ticked. It goes through the repost endpoint, the only one that takes
  /// both — the comment endpoint has no such switch, so a ticked box used to do nothing at all.
  ///
  /// [countOnPost] is off where the caller does not have the post's real counts to compare against —
  /// a notification replying to a comment has the id but not the numbers, and a count based on zero
  /// would make a post with two hundred comments show one.
  Future<String?> send({
    required Status status,
    required String text,
    String? rootId,
    String? replyToId,
    String? replyToName,
    String? replyToText,
    String? picturePath,
    bool crossPost = false,
    bool countOnPost = true,
  }) async {
    final content = text.trim();
    if (content.isEmpty) return null;
    final (weiboCookie, _) = await WeiboComSession.instance.cookie();
    final hasWeiboCom = WeiboComSession.hasAuth(weiboCookie);
    // Top-level 同时转发 goes through weibo.com's `normal_repost` (which supports `pic_id` +
    // `is_comment=1`), or m.weibo.cn's `repost` when there is no picture.
    final doTopCrossPost = rootId == null && crossPost && (picturePath == null || hasWeiboCom);
    // Replying to a comment or floor reply with 同时转发 posts the reply in the thread first
    // (the repost endpoint has no `cid`/`reply` fields), then forwards the post with `is_comment=0`.
    final doReplyCrossPost = rootId != null && crossPost;
    try {
      String? picId;
      if (picturePath != null) {
        picId = await WeiboApi.instance.uploadCommentImage(status.id, File(picturePath));
      }
      Comment? created;
      if (doTopCrossPost) {
        await WeiboApi.instance.repost(
          status.id,
          content,
          true,
          picIds: picId == null ? const [] : [picId],
        );
      } else if (rootId == null) {
        created = await WeiboApi.instance.comment(status.id, content, picId: picId);
      } else {
        created = await WeiboApi.instance.reply(
          status.id,
          content,
          rootId: rootId,
          replyToId: replyToId ?? rootId,
          picId: picId,
        );
        if (doReplyCrossPost) {
          final quoted = (replyToName != null && replyToName.isNotEmpty)
              ? (replyToText != null && replyToText.trim().isNotEmpty
                  ? '//@$replyToName:${replyToText.trim()}'
                  : '//@$replyToName')
              : '';
          final repostText = quoted.isEmpty ? content : '$content $quoted';
          await WeiboApi.instance.repost(
            status.id,
            repostText,
            false,
            picIds: (picId != null && hasWeiboCom) ? [picId] : const [],
          );
        }
      }
      if (picturePath != null) await TempFiles.delete(picturePath);
      // Raised in the store, not on whatever copy of the post the caller holds: the card in the
      // list behind this page reads the same value.
      if (countOnPost) {
        StatusStore.instance.addComment(status);
        if (doTopCrossPost || doReplyCrossPost) StatusStore.instance.addRepost(status);
      }
      if (rootId == null) {
        if (created != null) {
          addPosted(status.id, created);
        } else {
          addPending(status, content);
        }
      } else {
        addPendingReply(
          rootId,
          status.id,
          content,
          created: created,
          replyToName: replyToName,
        );
      }
      return null;
    } catch (error) {
      Haptic.error.play();
      return _failure(error, hasPicture: picturePath != null);
    }
  }

  /// Inserts a server-confirmed comment returned by the create endpoint at the top of the list
  /// until a subsequent page refresh includes it.
  void addPosted(String statusId, Comment comment) {
    final bucket = _pending[statusId] ??= [];
    bucket.removeWhere((existing) => existing.id == comment.id);
    bucket.insert(0, comment);
    _changed();
  }

  /// Shows the comment in its list before a refresh has returned it from the server.
  void addPending(Status status, String text, [String? picturePath]) {
    final me = _self();
    final comment = Comment(
      id: '$_localPrefix${DateTime.now().microsecondsSinceEpoch}',
      statusId: status.id,
      author: me,
      text: text,
      createdAt: DateTime.now(),
    );
    (_pending[status.id] ??= []).insert(0, comment);
    _changed();
  }

  /// Shows a reply just sent under [rootId] without reloading the whole thread.
  void addPendingReply(
    String rootId,
    String statusId,
    String text, {
    Comment? created,
    String? replyToName,
  }) {
    final reply = created ??
        Comment(
          id: '$_localPrefix${DateTime.now().microsecondsSinceEpoch}',
          statusId: statusId,
          author: _self(),
          text: text,
          createdAt: DateTime.now(),
          replyTo: (replyToName != null && replyToName.isNotEmpty)
              ? User(id: '', screenName: replyToName)
              : null,
        );
    final bucket = _pendingReplies[rootId] ??= [];
    bucket.removeWhere((existing) => existing.id == reply.id);
    bucket.insert(0, reply);
    _changed();
  }

  /// The list has been refreshed: any pending copy whose comment the answer now contains is
  /// dropped, so it is not shown twice.
  ///
  /// Server-confirmed copies match by real id; local placeholders match on author and normalized
  /// text. Copies absent from the answer are kept because a hot-ordered first page often omits a
  /// comment that was just written. Entries older than [staleAfter] are evicted anyway.
  void settle(String statusId, {List<Comment> loaded = const [], Duration staleAfter = const Duration(minutes: 10)}) {
    _settleBucket(_pending, statusId, loaded: loaded, staleAfter: staleAfter);
  }

  /// Same as [settle], for the replies under one top-level comment [rootId].
  void settleReplies(
    String rootId, {
    List<Comment> loaded = const [],
    Duration staleAfter = const Duration(minutes: 10),
  }) {
    _settleBucket(_pendingReplies, rootId, loaded: loaded, staleAfter: staleAfter);
  }

  void _settleBucket(
    Map<String, List<Comment>> buckets,
    String key, {
    required List<Comment> loaded,
    required Duration staleAfter,
  }) {
    final pending = buckets[key];
    if (pending == null) return;
    final now = DateTime.now();
    pending.removeWhere((copy) {
      if (now.difference(copy.createdAt) > staleAfter) return true;
      if (!isPending(copy)) return loaded.any((comment) => comment.id == copy.id);
      final target = _normalizeText(copy.text);
      return loaded.any(
        (comment) => comment.author.id == copy.author.id && _normalizeText(comment.text) == target,
      );
    });
    if (pending.isEmpty) buckets.remove(key);
    _changed();
  }

  static final RegExp _replyPrefix = RegExp(r'^回复\s*@?[^:：\s]+[:：]\s*');
  static final RegExp _spaces = RegExp(r'\s+');

  static String _normalizeText(String text) =>
      text.trim().replaceFirst(_replyPrefix, '').replaceAll(_spaces, ' ').trim();

  void _changed() {
    revision.value++;
    notifyListeners();
  }

  /// Who the reader is, as far as a comment being written needs to know: the avatar and the name it
  /// is shown under while it waits.
  User _self() {
    final cached = WeiboApi.instance.cachedSelfProfile()?.user;
    if (cached != null) return cached;
    return User(id: Session.instance.uid ?? '', screenName: '我');
  }

  /// Why the comment did not go out. Pictures in a comment are a permission Weibo hands to some
  /// accounts and not others, and nothing in the response names it — a refused upload is all that
  /// can be seen from here — so the message says that is likely what happened instead of a bare
  /// 「图片上传失败」, which reads as an app fault and invites a retry that fails the same way.
  ///
  /// A failure that never reached Weibo is not a permission problem, though: an upload that timed
  /// out says nothing about what the account may do, and telling the reader it is a permission
  /// issue would stop them from simply trying again.
  String _failure(Object error, {required bool hasPicture}) {
    final failure = Failure.from(error);
    if (hasPicture && failure.retryable) return '图片没有传上去，网络好像断了，可以再试一次';
    if (hasPicture && failure is! AuthFailure) {
      // Only the picture can be blamed here: the words went out fine in the same request before.
      return '这条评论没有发出去。发图片评论需要微博的权限，不是所有账号都有';
    }
    return failure.message;
  }
}
