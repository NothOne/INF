import 'dart:io';

import 'api.dart';
import 'failure.dart';
import 'group_chat_api.dart';
import 'haptics.dart';
import 'models.dart';
import 'temp_files.dart';
import 'weibo_com_session.dart';

/// Sending a message, in one place.
///
/// Two screens send messages — the chat page (文字, 图片, 视频) and the 分享 sheet's "send this post
/// to someone" row — and each used to call `sendMessage` / `sendGroupMessage` / `uploadChatImage` /
/// `sendChatImage` itself, decide its own failure text and pick its own temp-file handling. That is
/// the same shape of bug the comment path had: four call sites, four slightly different answers.
///
/// What is left here is the decision of which endpoint a target uses; the screens keep their own
/// busy marks and scroll behaviour, which are about them.
class MessageSender {
  MessageSender._();

  /// Sends [text] and completes with the message to show — null when it went out.
  static Future<String?> text(ChatTarget target, String text) async {
    final content = text.trim();
    if (content.isEmpty) return null;
    try {
      if (target.isGroup) {
        await WeiboApi.instance.sendGroupMessage(target.id, content);
      } else {
        await WeiboApi.instance.sendMessage(target.id, content);
      }
      Haptic.success.play();
      return null;
    } catch (error) {
      Haptic.error.play();
      return _failure(error, '发送失败');
    }
  }

  /// Uploads [file] and sends it as a picture, then removes the copy it was given.
  ///
  /// For group chats with a weibo.com session, prefers `api.weibo.com/webim/uploadx.json` so the
  /// resulting message carries the full MSS attachment; falls back to m.weibo.cn otherwise.
  static Future<String?> image(
    ChatTarget target,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      if (target.isGroup) {
        final (cookie, _) = await WeiboComSession.instance.cookie();
        if (WeiboComSession.hasAuth(cookie)) {
          await GroupChatApi.instance.uploadAndSendImage(target.id, file, onProgress: onProgress);
          Haptic.success.play();
          return null;
        }
      }
      final fids = await WeiboApi.instance.uploadChatImage(file, target);
      await WeiboApi.instance.sendChatImage(target, fids);
      Haptic.success.play();
      return null;
    } catch (error) {
      Haptic.error.play();
      return _failure(error, '图片发送失败');
    } finally {
      await TempFiles.delete(file.path);
    }
  }

  /// Uploads [file] and sends it as a video in a group chat, then removes the temporary copy.
  static Future<String?> video(
    ChatTarget target,
    File file, {
    int width = 0,
    int height = 0,
    int durationSec = 0,
    void Function(double progress)? onProgress,
  }) async {
    try {
      await GroupChatApi.instance.uploadAndSendVideo(
        target.id,
        file,
        width: width,
        height: height,
        durationSec: durationSec,
        onProgress: onProgress,
      );
      Haptic.success.play();
      return null;
    } catch (error) {
      Haptic.error.play();
      return _failure(error, '视频发送失败');
    } finally {
      await TempFiles.delete(file.path);
    }
  }

  static String _failure(Object error, String fallback) {
    final message = Failure.from(error).message;
    return message == '加载失败' ? fallback : message;
  }
}
