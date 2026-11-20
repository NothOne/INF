import 'dart:convert';
import 'dart:io';

/// A real response from one of Weibo's endpoints, kept under `test/fixtures/`.
///
/// The point of these is that they are not written by hand: every field a parser reads was in an
/// answer the service actually sent, so a golden test built on one fails when Weibo renames a field
/// rather than when this repository's idea of a field drifts from itself. What was taken out is
/// only how many rows a list holds, and each account's `user_token`; never a key inside a row.
/// `README.md` next to the files says which endpoint produced each one and when.
class Fixture {
  const Fixture._(this.name, this.data);

  factory Fixture.load(String name) {
    final file = File('test/fixtures/$name.json');
    if (!file.existsSync()) {
      throw StateError('missing fixture test/fixtures/$name.json — see test/fixtures/README.md');
    }
    return Fixture._(name, jsonDecode(file.readAsStringSync()));
  }

  /// The file's name without `.json`, which is also the endpoint's name in `core/endpoints.dart`.
  final String name;

  /// The decoded body as `_decodeEnvelope` would have handed it to a parser.
  final dynamic data;

  /// The envelope's whole body; most endpoints answer `{ok: 1, data: …}`.
  Map<String, dynamic> get root => Map<String, dynamic>.from(data as Map);

  /// The envelope's `data` member, which is what most API methods pass to a parser.
  dynamic get payload => (data as Map)['data'];

  @override
  String toString() => 'Fixture($name)';
}
