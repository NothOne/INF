import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'native.dart';

String statusLink(String id) => 'https://m.weibo.cn/detail/$id';

/// Weibo's report form for a post, the one m.weibo.cn's own 举报 opens.
String statusReportLink(String id) => 'https://service.account.weibo.com/reportspamobile?rid=$id&type=1&from=20000';

String statusShareText(Status status) {
  final author = status.author.screenName.isEmpty ? status.author.id : status.author.screenName;
  final body = status.text.trim();
  final buffer = StringBuffer('@')..write(author);
  if (body.isNotEmpty) buffer..write('：')..write(body);
  buffer..write(' ')..write(statusLink(status.id));
  return buffer.toString();
}

String userLink(String uid) => 'https://m.weibo.cn/u/$uid';

String userShareText(User user) {
  final name = user.screenName.isEmpty ? user.id : user.screenName;
  return '@$name ' + userLink(user.id);
}

/// share_plus has no HarmonyOS implementation; there the system share panel is opened natively.
Future<void> shareText(String text) async {
  if (Native.isOhos) return Native.share(text: text);
  await SharePlus.instance.share(ShareParams(text: text));
}

Future<void> shareFile(String path, {String? mime, String? name}) async {
  if (Native.isOhos) return Native.share(path: path, mime: mime);
  await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: mime, name: name)]));
}
