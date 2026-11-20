import 'package:flutter/material.dart';

import '../failure.dart';
import '../paging.dart';
import 'common.dart';

/// What sits under a paged list: a spinner while the next page comes, a button when it failed, and
/// 「没有更多了」 at the end.
///
/// Every list used to write this itself — six copies with slightly different paddings, and one of
/// them calling `loadMore` from the retry button, which could re-request the page the reader had
/// just scrolled past. There is one footer now, and its retry goes through [PagingController.retryMore].
///
/// A failed page that trying again cannot fix — a rate limit, a deleted post — says so instead of
/// offering a button. The footer is at the bottom of something the reader scrolled to on purpose, so
/// a button that fails identically is worse than no button: it reads as the app being broken rather
/// than the page being unavailable.
class PagerTail<T> extends StatelessWidget {
  const PagerTail(this.pager, {super.key, this.endText = '没有更多了', this.gap = 20});

  final PagingController<T> pager;

  /// What the end of the list says. Some lists say more than others.
  final String endText;

  /// Height held under the last row while there is more to come, so the list can still be pulled.
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (pager.loadingMore) return const LoadingFooter();
    final error = pager.moreError;
    if (error != null) {
      final failure = Failure.from(error);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: failure.retryable
              ? TextButton(onPressed: pager.retryMore, child: const Text('加载失败，点此重试'))
              : Text(
                  failure.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
        ),
      );
    }
    if (!pager.hasMore && pager.items.isNotEmpty) return LoadingFooter(text: endText);
    return SizedBox(height: gap);
  }
}
