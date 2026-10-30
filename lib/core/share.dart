import 'package:share_plus/share_plus.dart';

import 'models.dart';

String statusLink(String id) => 'https://m.weibo.cn/detail/$id';

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

Future<void> shareText(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}
