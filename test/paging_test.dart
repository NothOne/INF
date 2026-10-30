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
}
