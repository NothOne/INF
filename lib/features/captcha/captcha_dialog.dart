import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/widgets/web_view.dart';

/// Weibo's own captcha step, as m.weibo.cn runs it when a write answers `error_type: captcha`:
/// its validate loader shows the NetEase Yidun puzzle, and the fields it hands back are added to
/// the refused request. Completes with those fields, or null when closed or failed.
Future<Map<String, String>?> showCaptchaDialog(BuildContext context, String captchaId) {
  return showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CaptchaDialog(captchaId: captchaId),
  );
}

String _page(String captchaId) => '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>html,body{margin:0;height:100%;background:transparent;}</style>
<script src="https://cstaticdun.126.net/load.min.js"></script>
<script src="https://js.t.sinajs.cn/static/validate-loader.umd.cjs"></script>
</head>
<body>
<script>
function send(value) { INFCaptcha.postMessage(JSON.stringify(value)); }
window.onload = function () {
  if (!window.ValidateLoader || !window.initNECaptcha) {
    send({status: 'error', message: '验证组件没有加载出来'});
    return;
  }
  ValidateLoader.handleCaptchaVerification('yidun', {captcha_id: ${jsonEncode(captchaId)}, element: document.body})
    .then(function (result) {
      var data = result && result.data;
      send({
        status: result ? result.status : 'error',
        data: result && result.status === 'success' ? data : null,
        message: data && data.message ? String(data.message) : null
      });
    }, function (error) {
      send({status: 'error', message: String(error)});
    });
};
</script>
</body>
</html>
''';

class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog({required this.captchaId});

  final String captchaId;

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.transparent)
    ..addJavaScriptChannel('INFCaptcha', onMessageReceived: _onMessage)
    // Yidun checks the page it runs on against the site the captcha was issued for.
    ..loadHtmlString(_page(widget.captchaId), baseUrl: 'https://m.weibo.cn/');

  String? _error;
  bool _done = false;

  void _onMessage(JavaScriptMessage message) {
    if (_done || !mounted) return;
    final decoded = jsonDecode(message.message);
    if (decoded is! Map) return;
    final status = decoded['status'];
    if (status == 'success' && decoded['data'] is Map) {
      _done = true;
      final fields = <String, String>{
        for (final entry in (decoded['data'] as Map).entries)
          if (entry.value != null) entry.key.toString(): entry.value.toString(),
      };
      Navigator.of(context).pop(fields);
    } else if (status == 'close') {
      _done = true;
      Navigator.of(context).pop();
    } else {
      final detail = decoded['message'] as String?;
      setState(() => _error = detail == null ? '验证没有完成，可以关闭后重试' : '验证出错：$detail');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('安全验证', style: text.titleMedium)),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () {
                      _done = true;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _error ?? '微博要求先完成验证，完成后会自动继续刚才的操作',
                style: text.bodySmall?.copyWith(color: _error == null ? scheme.onSurfaceVariant : scheme.error),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 440, child: InfWebView(controller: _web)),
          ],
        ),
      ),
    );
  }
}
