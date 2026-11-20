import 'api.dart';

/// Why a request did not produce what was asked for, in the one form the UI needs: what to tell the
/// reader, and whether asking again could help.
///
/// Before this, `retryable` was decided by matching on the message — `error.code == 20000` in two
/// places, `message.contains('图片上传失败')` in a third. Those are the same question asked three
/// ways, and each new wording risked a fourth. A failure is now classified once, here, and the pages
/// that offer a 重试 button ask it rather than re-reading the text.
///
/// [ApiException] stays as it is: it is thrown from about fifty places and carried through a dozen
/// callers, and replacing it wholesale is a change with no benefit to the reader. This wraps it.
sealed class Failure {
  const Failure(this.message);

  /// What to show the reader. Never empty; [Failure.from] substitutes a sentence for anything that
  /// would otherwise be a bare `toString`.
  final String message;

  /// Whether the same request, sent again, has a chance of working. False for anything the reader
  /// has to change first — signing in, finishing a captcha, waiting out a rate limit — and for
  /// anything that will fail the same way however many times it is sent.
  bool get retryable;

  /// Classifies whatever a request threw.
  factory Failure.from(Object? error) {
    if (error == null) return const BusinessFailure('加载失败');
    if (error is Failure) return error;
    if (error is LoginRequiredException) return AuthFailure('需要登录微博才能查看');
    if (error is CaptchaRequiredException) {
      return RiskControlFailure(error.message.isEmpty ? '需要先完成一次安全验证' : error.message);
    }
    if (error is ApiException) {
      // The transport already knows when it never reached Weibo or got an answer it cannot read;
      // those two are marked at the throw site rather than re-derived from the wording here.
      switch (error.kind) {
        case FailureKind.network:
          return NetworkFailure(error.message);
        case FailureKind.parse:
          return ParseDriftFailure(error.message);
        case null:
          break;
      }
      // 20000 is Weibo's own code for 「操作频繁」: the account is being held back, and the only
      // thing that helps is time.
      if (error.code == 20000) return RiskControlFailure('微博暂时限制了操作频率，请稍后再试');
      final message = error.message.trim();
      return BusinessFailure(message.isEmpty ? '加载失败' : message);
    }
    if (error is String) return BusinessFailure(error.trim().isEmpty ? '加载失败' : error);
    return const BusinessFailure('加载失败');
  }
}

/// The request never reached Weibo, or the answer never came back. Nothing about the reader's
/// account or the request is wrong, so trying again is the right thing to offer.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);

  @override
  bool get retryable => true;
}

/// The session is missing or has ended. Retrying fails the same way until the reader signs in.
final class AuthFailure extends Failure {
  const AuthFailure(super.message);

  @override
  bool get retryable => false;
}

/// Weibo is holding the account back: a captcha, or 「操作频繁」. Waiting or finishing the captcha
/// is what changes the answer; sending the request again immediately cannot.
final class RiskControlFailure extends Failure {
  const RiskControlFailure(super.message);

  @override
  bool get retryable => false;
}

/// Weibo answered something this app does not understand — a field renamed, a shape changed. Sent
/// again, it will not answer differently.
final class ParseDriftFailure extends Failure {
  const ParseDriftFailure(super.message);

  @override
  bool get retryable => false;
}

/// Weibo understood the request and declined it, for a reason of its own. The message is its own
/// wording and is passed through; a retry sends the same refusal.
final class BusinessFailure extends Failure {
  const BusinessFailure(super.message);

  @override
  bool get retryable => false;
}
