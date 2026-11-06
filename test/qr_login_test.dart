import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';

void main() {
  test('QR code carries its scan URL in the image link', () {
    final qr = parseQrLogin({
      'retcode': 20000000,
      'data': {
        'qrid': 'abc',
        'image': 'https://v2.qr.weibo.cn/inf/gen?api_key=x&data=https%3A%2F%2Fpassport.weibo.cn%2Fsignin%2Fqrcode%2Fscan%3Fqr%3Dabc',
      },
    });
    expect(qr?.qrid, 'abc');
    expect(qr?.scanUrl, 'https://passport.weibo.cn/signin/qrcode/scan?qr=abc');
  });

  test('QR code without a usable scan URL is rejected', () {
    expect(parseQrLogin({'retcode': 50000000, 'data': {}}), isNull);
    expect(
      parseQrLogin({
        'retcode': 20000000,
        'data': {'qrid': 'abc', 'image': 'https://v2.qr.weibo.cn/inf/gen?data=javascript%3Aalert(1)'},
      }),
      isNull,
    );
  });

  test('QR status follows passport retcodes', () {
    expect(parseQrLoginStatus({'retcode': 50114001}).state, QrLoginState.waiting);
    expect(parseQrLoginStatus({'retcode': 50114002}).state, QrLoginState.scanned);
    expect(parseQrLoginStatus({'retcode': 50114004}).state, QrLoginState.failed);
    expect(parseQrLoginStatus({'retcode': 1}).state, QrLoginState.waiting);
    final done = parseQrLoginStatus({
      'retcode': 20000000,
      'data': {'url': 'https://login.sina.com.cn/sso/login.php?alt=x'},
    });
    expect(done.state, QrLoginState.confirmed);
    expect(done.url, 'https://login.sina.com.cn/sso/login.php?alt=x');
  });
}
