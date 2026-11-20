import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/unread_monitor.dart';

/// When the unread counts are asked for.
///
/// Five call sites used to say `refresh(force: true)`, and `force` was never read: a screen that
/// rebuilt often turned into a poll, and one tab switch could send more than one request. The
/// policy is a pure function on the monitor now, so it can be tested without a clock or a network.
void main() {
  final at = DateTime(2026, 11, 19, 10);

  test('a quiet refresh waits out the quiet gap', () {
    expect(UnreadMonitor.shouldAsk(lastAsked: at, at: at.add(const Duration(seconds: 29)), immediately: false), isFalse);
    expect(UnreadMonitor.shouldAsk(lastAsked: at, at: at.add(const Duration(seconds: 31)), immediately: false), isTrue);
  });

  test('a refresh a screen asked for only skips the quiet gap, not the urgent one', () {
    // Two callers reacting to the same tap must join one request.
    expect(UnreadMonitor.shouldAsk(lastAsked: at, at: at.add(const Duration(seconds: 1)), immediately: true), isFalse);
    expect(UnreadMonitor.shouldAsk(lastAsked: at, at: at.add(const Duration(seconds: 6)), immediately: true), isTrue);
  });

  test('the first ask of a session is always made', () {
    expect(UnreadMonitor.shouldAsk(lastAsked: null, at: at, immediately: false), isTrue);
  });

  test('a count is only published when one of its parts changed', () {
    const before = UnreadCounts(mentionsInStatuses: 1, comments: 2, likes: 0, messages: 3);
    const same = UnreadCounts(mentionsInStatuses: 1, comments: 2, likes: 0, messages: 3);
    // A like that became a comment: the notification total is unchanged, so comparing totals alone
    // would miss it and the badge would keep the wrong count on its tab.
    const moved = UnreadCounts(mentionsInStatuses: 1, comments: 3, likes: 0, messages: 3);

    expect(UnreadMonitor.sameCounts(before, same), isTrue);
    expect(UnreadMonitor.sameCounts(before, moved), isFalse);
  });
}
