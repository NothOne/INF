import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/features/feed/feed_reading_position.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the reader is in a feed, which used to be a dozen fields inside the feed's widget state.
///
/// The three things it is responsible for, each of which has been a bug at some point: staying on
/// the post being read through a refresh, counting what arrived above it, and offering a way back
/// when the refresh could not keep the place.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  Status post(String id, {DateTime? at}) => Status(
        id: id,
        author: const User(id: 'u', screenName: '某人'),
        text: '正文 $id',
        createdAt: at ?? DateTime(2026, 11, 19, 10),
      );

  FeedReadingPosition position() => FeedReadingPosition('test-source');

  /// Runs [FeedReadingPosition.update] and records what it asked to scroll to.
  ({bool moved, String? id, double? dy}) update(
    FeedReadingPosition reading,
    List<Status> items,
    DateTime? refreshedAt,
  ) {
    String? id;
    double? dy;
    final moved = reading.update(items, refreshedAt, onRecenter: (nextId, nextDy) {
      id = nextId;
      dy = nextDy;
    });
    return (moved: moved, id: id, dy: dy);
  }

  test('the first page lays the list out from its first post', () {
    final reading = position();
    final result = update(reading, [post('a'), post('b')], DateTime(1));

    expect(result.id, 'a');
    expect(reading.centerId, 'a');
  });

  test('a refresh that brought new posts counts them and keeps the post being read', () {
    final reading = position();
    update(reading, [post('a'), post('b')], DateTime(1));

    // Three new posts arrived above 'a'.
    final result = update(reading, [post('n3'), post('n2'), post('n1'), post('a'), post('b')], DateTime(2));

    expect(result.moved, isFalse, reason: 'the post being read is still there');
    expect(reading.centerId, 'a');
    expect(reading.unread, 3);
    expect(reading.unreadOpen, isFalse);
    expect(reading.markerId, 'a');
  });

  test('the same refresh is not counted twice', () {
    final reading = position();
    update(reading, [post('a')], DateTime(1));
    update(reading, [post('n'), post('a')], DateTime(2));
    expect(reading.unread, 1);

    // The pager notifies again for the same landed refresh.
    update(reading, [post('n'), post('a')], DateTime(2));
    expect(reading.unread, 1);
  });

  test('when the post being read is gone, the list moves to the top and offers the way back', () {
    final reading = position();
    update(reading, [post('a'), post('b')], DateTime(1));

    final result = update(reading, [post('x'), post('y')], DateTime(2));

    expect(result.moved, isTrue);
    expect(result.id, 'x');
    expect(reading.unreadOpen, isTrue, reason: 'more arrived than one page, so the count is not known');
  });

  test('scrolling up into the new posts leaves only the ones above the fold counted', () {
    final reading = position();
    update(reading, [post('a'), post('b'), post('c')], DateTime(1));
    update(reading, [post('n1'), post('n2'), post('a'), post('b'), post('c')], DateTime(2));
    expect(reading.unread, 2);

    // The top-most visible post is n2, so one new post (n1) is still above the fold.
    expect(reading.record(id: 'n2', index: 1, dy: 0), isTrue);
    expect(reading.unread, 1);

    // Back down among the posts that were already read: the count does not go on falling, because
    // what it counts is what is above the fold, and that has not changed.
    expect(reading.record(id: 'b', index: 3, dy: 0), isFalse);
    expect(reading.unread, 1);

    // Tapping the pill is what clears it.
    reading.toTop();
    expect(reading.unread, 0);
  });

  test('a pull to refresh clears the count', () {
    final reading = position();
    update(reading, [post('a')], DateTime(1));
    update(reading, [post('n'), post('a')], DateTime(2));
    expect(reading.unread, 1);

    reading.toTop();
    expect(reading.unread, 0);
    expect(reading.unreadOpen, isFalse);
  });

  test('a position saved last time is where the first page opens', () async {
    await Prefs.instance.setFeedPosition(
      'test-source',
      FeedPosition(id: 'b', dy: 40, head: 'a', headAt: DateTime(2026, 11, 19, 9)),
    );

    final reading = position();
    final result = update(reading, [post('a'), post('b')], DateTime(1));

    expect(result.id, 'b');
    expect(result.dy, 40);
    expect(reading.centerId, 'b');
  });

  test('a saved post that the first page does not hold leaves the way back', () async {
    await Prefs.instance.setFeedPosition('test-source', FeedPosition(id: 'deep', dy: 0));

    final reading = position();
    final result = update(reading, [post('a')], DateTime(1));

    expect(result.id, 'a');
    expect(reading.canResume, isTrue);
  });

  test('what was read is written down, and the saved place is cleared of it', () async {
    final reading = position();
    update(reading, [post('a'), post('b'), post('c')], DateTime(1));
    reading.record(id: 'b', index: 1, dy: 12);

    reading.save([post('a'), post('b'), post('c')]);

    final saved = Prefs.instance.feedPosition('test-source');
    expect(saved?.id, 'b');
    expect(saved?.dy, 12);
    // Nothing above the post being read is new, so the newest post seen is the top of the list.
    expect(saved?.head, 'a', reason: 'the newest post actually seen is the one above the centre');
  });

  test('nothing is saved while the way back is still on offer', () {
    final reading = position();
    update(reading, [post('a'), post('b')], DateTime(1));
    reading.record(id: 'b', index: 1, dy: 0);
    reading.canResume = true;

    reading.save([post('a'), post('b')]);
    expect(Prefs.instance.feedPosition('test-source'), isNull);
  });

  test('consecutive background refreshes accumulate unread counts and keep the original marker', () {
    final reading = position();
    update(reading, [post('a'), post('b')], DateTime(1));

    // First background refresh brings 2 posts above 'a'.
    update(reading, [post('n2'), post('n1'), post('a'), post('b')], DateTime(2));
    expect(reading.unread, 2);
    expect(reading.markerId, 'a');

    // Second background refresh brings 1 more post before the reader scrolled up.
    update(reading, [post('n3'), post('n2'), post('n1'), post('a'), post('b')], DateTime(3));
    expect(reading.unread, 3);
    expect(reading.markerId, 'a');
    expect(reading.unreadOpen, isFalse);
  });

  test('a deleted top post does not trigger an unknown-gap unread count when later posts still match', () {
    final reading = position();
    update(reading, [post('deleted'), post('a'), post('b')], DateTime(1));

    update(reading, [post('n1'), post('a'), post('b')], DateTime(2));
    expect(reading.unread, 1);
    expect(reading.unreadOpen, isFalse);
    expect(reading.markerId, 'a');
  });

  test('toTop(id) updates centerId, keeps the read marker, and resumeAt(id, dy) restores the anchor', () {
    final reading = position();
    update(reading, [post('a'), post('b')], DateTime(1));
    update(reading, [post('n1'), post('a'), post('b')], DateTime(2));
    expect(reading.centerId, 'a');
    expect(reading.markerId, 'a');

    reading.toTop('n1');
    expect(reading.centerId, 'n1');
    expect(reading.unread, 0);
    expect(reading.markerId, 'a', reason: 'pull-to-refresh still shows 上次看到这里 above the old head');
    expect(reading.canResume, isFalse);

    reading.canResume = true;
    reading.resumeAt('b', 24);
    expect(reading.centerId, 'b');
    expect(reading.position, (id: 'b', dy: 24.0));
    expect(reading.canResume, isFalse);
  });

  test('the 上次读到 pill fades out as the reader scrolls up or down and then clears', () async {
    await Prefs.instance.setFeedPosition('test-source', FeedPosition(id: 'deep', dy: 0));
    final reading = position();
    update(reading, [post('a'), post('b')], DateTime(1));
    expect(reading.canResume, isTrue);
    expect(reading.resumeOpacity, 1.0);

    // Scrolling down halfway fades it to 0.5 without dismissing yet.
    expect(reading.trackResumeScroll(FeedReadingPosition.resumeFadeDistance / 2), isFalse);
    expect(reading.canResume, isTrue);
    expect(reading.resumeOpacity, closeTo(0.5, 0.001));

    // Scrolling back up also accumulates distance until it finishes fading out.
    expect(reading.trackResumeScroll(-FeedReadingPosition.resumeFadeDistance / 2), isTrue);
    expect(reading.canResume, isFalse);
    expect(reading.resumeOpacity, 0.0);
  });
}
