import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/relation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Following and blocking, which used to be held separately by every list that showed a person.
///
/// The store keeps only what this session changed; the server's answer is the baseline, so a page
/// that has not been refreshed still draws the right state.
///
/// A tap on 关注 also sends a request, and there is no HTTP here, so the tests cover the part that
/// does not need one: which answer wins, and the block list that never leaves this device.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  User user({String id = 'u1', bool following = false}) => User(
        id: id,
        screenName: '某人',
        following: following,
      );

  test('with nothing changed here, the answer decides', () {
    expect(RelationStore.instance.following(user(following: true)), isTrue);
    expect(RelationStore.instance.following(user(following: false)), isFalse);
  });

  test('the baseline is per person, not one flag for the session', () {
    final followed = user(id: 'a', following: true);
    final notFollowed = user(id: 'b', following: false);

    expect(RelationStore.instance.following(followed), isTrue);
    expect(RelationStore.instance.following(notFollowed), isFalse);
  });

  test('a block is remembered for this device and reported for that person', () async {
    final person = user(id: 'blocked-one');
    expect(RelationStore.instance.isBlocked(person.id), isFalse);

    await RelationStore.instance.setBlocked(person, true);
    expect(RelationStore.instance.isBlocked(person.id), isTrue);

    await RelationStore.instance.setBlocked(person, false);
    expect(RelationStore.instance.isBlocked(person.id), isFalse);
  });

  test('blocking one person leaves another alone', () async {
    await RelationStore.instance.setBlocked(user(id: 'x'), true);
    expect(RelationStore.instance.isBlocked('x'), isTrue);
    expect(RelationStore.instance.isBlocked('y'), isFalse);
  });
}
