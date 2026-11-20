import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/paging.dart';

PagingController<String> pagerOver(Map<String?, PageResult<String>> pages) => PagingController<String>(
      fetch: (cursor) async {
        final page = pages[cursor];
        if (page == null) throw StateError('no page for $cursor');
        return page;
      },
      id: (item) => item,
    );

void main() {
  test('refresh loads the first page and loadMore appends without duplicates', () async {
    final pager = pagerOver({
      null: const PageResult(['a', 'b', 'c'], '2'),
      '2': const PageResult(['c', 'd'], '3'),
      '3': const PageResult([], null),
    });
    expect(await pager.refresh(), isTrue);
    expect(pager.items, ['a', 'b', 'c']);
    expect(pager.hasMore, isTrue);

    await pager.loadMore();
    expect(pager.items, ['a', 'b', 'c', 'd']);
    expect(pager.cursor, '3');

    await pager.loadMore();
    expect(pager.hasMore, isFalse);
    pager.dispose();
  });

  test('loadMore stops when the server repeats the cursor', () async {
    final pager = pagerOver({
      null: const PageResult(['a'], '2'),
      '2': const PageResult(['b'], '2'),
    });
    await pager.refresh();
    await pager.loadMore();
    expect(pager.items, ['a', 'b']);
    expect(pager.hasMore, isFalse);
    pager.dispose();
  });

  test('a seeded page is stale until the first refresh, which marks new items fresh', () async {
    final pager = pagerOver({null: const PageResult(['new', 'a', 'b'], null)});
    pager.seed(const PageResult(['a', 'b'], '2'));
    expect(pager.stale, isTrue);
    expect(pager.items, ['a', 'b']);

    expect(await pager.refresh(), isTrue);
    expect(pager.stale, isFalse);
    expect(pager.items, ['new', 'a', 'b']);
    expect(pager.fresh, {'new'});
    pager.dispose();
  });

  test('a failed refresh keeps what is on screen and only reports when the user pulled', () async {
    var fail = false;
    final pager = PagingController<String>(
      fetch: (cursor) async {
        if (fail) throw StateError('offline');
        return const PageResult(['a'], null);
      },
      id: (item) => item,
    );
    await pager.refresh();
    fail = true;

    expect(await pager.refresh(background: true), isFalse);
    expect(pager.items, ['a']);
    expect(pager.error, isNull);

    expect(await pager.refresh(), isFalse);
    expect(pager.items, ['a']);
    expect(pager.error, isA<StateError>());
    pager.dispose();
  });

  test('a failed first load shows the error and stops paging', () async {
    final pager = pagerOver({});
    expect(await pager.refresh(), isFalse);
    expect(pager.items, isEmpty);
    expect(pager.error, isA<StateError>());
    expect(pager.hasMore, isFalse);
    pager.dispose();
  });

  test('a failed append is not retried by scrolling, only by the footer button', () async {
    // A list left at the bottom sends a scroll notification on every frame of the fling, so a
    // failed page used to be asked for again and again — which Weibo answers with 「操作频繁」.
    var attempts = 0;
    final pager = PagingController<String>(
      fetch: (cursor) async {
        if (cursor == null) return const PageResult(['a'], '2');
        attempts++;
        throw StateError('offline');
      },
      id: (item) => item,
    );
    await pager.refresh();
    await pager.loadMore();
    expect(attempts, 1);
    expect(pager.moreError, isA<StateError>());

    await pager.loadMore();
    expect(attempts, 1, reason: 'a scroll must not be the thing that retries');

    await pager.retryMore();
    expect(attempts, 2);
    pager.dispose();
  });

  test('a successful refresh makes the next append possible again', () async {
    var fail = true;
    final pager = PagingController<String>(
      fetch: (cursor) async {
        if (cursor == null) return const PageResult(['a'], '2');
        if (fail) throw StateError('offline');
        return const PageResult(['b'], null);
      },
      id: (item) => item,
    );
    await pager.refresh();
    await pager.loadMore();
    expect(pager.moreError, isA<StateError>());

    fail = false;
    await pager.refresh();
    expect(pager.moreError, isNull);
    await pager.loadMore();
    expect(pager.items, ['a', 'b']);
    pager.dispose();
  });

  test('a user-pulled refresh preempts an in-flight loadMore and ignores its late result', () async {
    final moreGate = Completer<PageResult<String>>();
    var refreshes = 0;
    final pager = PagingController<String>(
      fetch: (cursor) async {
        if (cursor == null) {
          refreshes++;
          return refreshes == 1
              ? const PageResult(['a', 'b'], '2')
              : const PageResult(['fresh', 'a'], '2');
        }
        return moreGate.future;
      },
      id: (item) => item,
    );
    await pager.refresh();
    final loadingMore = pager.loadMore();
    expect(pager.loadingMore, isTrue);

    expect(await pager.refresh(), isTrue);
    expect(pager.items, ['fresh', 'a']);

    // The superseded loadMore finishes late and must not pollute the fresh list.
    moreGate.complete(const PageResult(['stale-c'], '3'));
    await loadingMore;
    expect(pager.items, ['fresh', 'a']);
    pager.dispose();
  });

  test('a user-pulled refresh preempts an in-flight background refresh', () async {
    final bgGate = Completer<PageResult<String>>();
    var call = 0;
    final pager = PagingController<String>(
      fetch: (cursor) async {
        call++;
        if (call == 1) return const PageResult(['a'], '2');
        if (call == 2) return bgGate.future;
        return const PageResult(['newest', 'a'], '2');
      },
      id: (item) => item,
    );
    await pager.refresh();
    final bg = pager.refresh(background: true);

    expect(await pager.refresh(), isTrue);
    expect(pager.items, ['newest', 'a']);

    bgGate.complete(const PageResult(['old-bg'], null));
    expect(await bg, isFalse);
    expect(pager.items, ['newest', 'a']);
    pager.dispose();
  });

  test('a bridge failure during background refresh still keeps the fresh first page', () async {
    var first = true;
    final pager = PagingController<String>(
      keepTailOnRefresh: true,
      fetch: (cursor) async {
        if (cursor == null) {
          if (first) {
            first = false;
            return const PageResult(['old1', 'old2'], 'old-next');
          }
          return const PageResult(['new1', 'new2'], 'bridge-1');
        }
        throw StateError('bridge failed');
      },
      id: (item) => item,
    );
    await pager.refresh();
    expect(await pager.refresh(background: true), isTrue);
    expect(pager.items, ['new1', 'new2']);
    expect(pager.cursor, 'bridge-1');
    pager.dispose();
  });
}
