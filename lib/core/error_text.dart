import 'package:flutter/material.dart';

import 'failure.dart';
import 'navigation.dart';
import 'session.dart';
import 'widgets/common.dart';

/// What to put in front of the reader for a failed request.
///
/// Every list printed `error.toString()` — which is the whole `ApiException` message, or `Dio`
/// noise, or `Instance of 'StateError'` — so a signed-out client showed 「需要登录微博」 in a red
/// paragraph with nothing to do about it. Errors now say the same thing everywhere, and signing in
/// is offered where the reason was that.
String friendlyError(Object? error) => Failure.from(error).message;

/// [friendlyError], plus the action the failure actually calls for.
///
/// A 去登录 button when the session is what is missing, a 重试 button when sending the request again
/// could work, and neither when it could not: a rate limit or a refusal is not a retry, and offering
/// one there invites the reader to press a button that fails the same way.
///
/// The two are not exclusive in principle, but in practice a failure is one or the other — a
/// refusal that also needs a session is still a refusal — so this shows at most one.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.error, required this.onRetry, this.compact = false});

  final Object? error;
  final VoidCallback onRetry;

  /// For a footer under content that is already showing: no title, no icon.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final failure = Failure.from(error);
    final needsLogin = failure is AuthFailure || Session.instance.state == SessionState.loggedOut;
    if (!needsLogin && !failure.retryable) {
      return compact ? ErrorRetry(message: null, onRetry: null) : _refused(context, failure);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ErrorRetry(
          message: compact ? null : failure.message,
          onRetry: needsLogin ? null : onRetry,
        ),
        if (!compact && needsLogin)
          TextButton(onPressed: () => openLogin(context), child: const Text('去登录')),
      ],
    );
  }

  /// A failure that saying 「重试」 would not fix: the message, without a button that cannot help.
  Widget _refused(BuildContext context, Failure failure) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('加载失败', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              failure.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      );
}
