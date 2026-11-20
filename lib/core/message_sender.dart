import 'dart:io';

import 'api.dart';
import 'failure.dart';
import 'haptics.dart';
import 'models.dart';
import 'temp_files.dart';

/// Sending a message, in one place.
///
/// Two screens send messages — the chat page (文字 and 图片) and the 分享 sheet's "send this post to
/// someone" row — and each used to call `sendMessage` / `sendGroupMessage` / `uploadChatImage` /
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
  /// The upload and the send are two requests and both can fail; the picture is only deleted after
  /// both, and also when they fail, because the caller's copy is a scratch file that nothing else
  /// refers to.
  static Future<String?> image(ChatTarget target, File file) async {
    try {
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

  static String _failure(Object error, String fallback) {
    final message = Failure.from(error).message;
    return message == '加载失败' ? fallback : message;
  }
}
