import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/api.dart';
import 'package:inf_flutter/core/error_text.dart';
import 'package:inf_flutter/core/failure.dart';

/// What every failure means, and what the reader is offered because of it.
///
/// Three places used to answer this by matching on text — `error.code == 20000` twice and
/// `message.contains('图片上传失败')` once — because [ApiException] carried nothing but a string.
/// Now the meaning is decided once, here, so a page can ask whether to offer 重试 instead of
/// re-reading the wording and hoping it is still the same.
void main() {
  group('the transport says what it already knows', () {
    test('a request that never reached Weibo is retryable', () {
      for (final message in ['网络连接超时', '网络连接失败', '连接被重置']) {
        final failure = Failure.from(ApiException(message, kind: FailureKind.network));
        expect(failure, isA<NetworkFailure>(), reason: message);
        expect(failure.retryable, isTrue);
        expect(failure.message, message);
      }
    });

    test('an answer in an unreadable shape is not', () {
      final failure = Failure.from(ApiException('接口返回格式错误', kind: FailureKind.parse));
      expect(failure, isA<ParseDriftFailure>());
      expect(failure.retryable, isFalse);
    });
  });

  group('a refusal is not a retry', () {
    test('errno 20000 is a rate limit, whatever its wording', () {
      final failure = Failure.from(ApiException('操作频繁', code: 20000));
      expect(failure, isA<RiskControlFailure>());
      expect(failure.retryable, isFalse);
      // Weibo's own wording is replaced: the reader needs to know whose limit it is.
      expect(failure.message, contains('限制了操作频率'));
    });

    test('20000 is recognised even when the message says nothing about it', () {
      // The code is the fact; the message is what changes between endpoints.
      expect(Failure.from(ApiException('', code: 20000)), isA<RiskControlFailure>());
      expect(Failure.from(ApiException('系统错误', code: 20000)), isA<RiskControlFailure>());
    });

    test('a captcha is what it is, and closing the dialog does not mean try again', () {
      final failure = Failure.from(CaptchaRequiredException('需要完成安全验证', captchaId: 'c1'));
      expect(failure, isA<RiskControlFailure>());
      expect(failure.retryable, isFalse);
      expect(failure.message, '需要完成安全验证');
    });

    test('a refused upload is a business failure, not a parse one', () {
      // The service took the request and answered without a picture id. Nothing about the answer's
      // shape is wrong; the account simply was not given the id.
      final failure = Failure.from(ApiException('图片上传失败'));
      expect(failure, isA<BusinessFailure>());
      expect(failure.retryable, isFalse);
    });

    test('a signed-out client is not offered a retry either', () {
      final failure = Failure.from(LoginRequiredException());
      expect(failure, isA<AuthFailure>());
      expect(failure.retryable, isFalse);
      expect(failure.message, contains('登录'));
    });
  });

  group('anything else still has something to say', () {
    test('a message with no code is passed through', () {
      final failure = Failure.from(ApiException('这条微博不存在或已被删除'));
      expect(failure, isA<BusinessFailure>());
      expect(failure.message, '这条微博不存在或已被删除');
    });

    test('an empty message becomes a sentence rather than a blank', () {
      expect(Failure.from(ApiException('  ')).message, '加载失败');
      expect(Failure.from(const BusinessFailure('')).message, isEmpty);
    });

    test('null and a bare object never reach the reader as a toString', () {
      expect(Failure.from(null).message, '加载失败');
      expect(Failure.from(StateError('boom')).message, '加载失败');
      expect(Failure.from('已经是文案').message, '已经是文案');
    });

    test('a Failure handed back in is itself, not re-wrapped', () {
      const original = NetworkFailure('断网了');
      expect(identical(Failure.from(original), original), isTrue);
    });

    test('a String that is not one of our exceptions is treated as the message', () {
      // `friendlyError` used to return it as-is, and callers still pass message strings.
      expect(Failure.from('加载失败').message, '加载失败');
    });
  });

  group('ErrorView actions follow Failure classification', () {
    testWidgets('network failure shows the retry button while a plain string does not', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              error: ApiException('网络连接超时', kind: FailureKind.network),
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(error: '网络连接超时', onRetry: () {}),
          ),
        ),
      );
      expect(find.text('重试'), findsNothing);
    });
  });
}
