import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'page_cache.dart';
import 'session.dart';

/// Whether a list is worth keeping on disk, and what it means to read it back.
///
/// The decision used to be an `if (cursor == null)` written beside each endpoint — six times, in
/// four files, with a different key spelled by hand in each. Adding a list meant remembering to
/// write it again, and a page could seed from a key the writer had stopped writing without anything
/// failing loudly.
///
/// This does not take over the fetching. [WeiboApi] still builds the request, still names the
/// parameters, still knows which cursor is first; what moved here is only the caching half — the
/// key, the policy, and reading the answer back through the parser that produced it.
enum CachePolicy {
  /// The first page is written and handed back on the next launch, then refreshed in place.
  /// A list a reader opens expecting to see something has this.
  cacheFirst,

  /// Nothing is kept. For a page whose content is only meaningful in the moment — a search, a
  /// topic's posts, anything addressed by what the reader typed.
  networkOnly,
}

/// A cached first page: what to store, and how to read it back.
///
/// One instance per list, built where the list's key is known (the post id, the account, which sort
/// order). [read] and [write] are the only two things a caller needs; both are no-ops for
/// [CachePolicy.networkOnly], so an API method reads the same either way.
@immutable
class CachedPage<T> {
  const CachedPage({
    required this.key,
    required this.parse,
    this.policy = CachePolicy.cacheFirst,
    this.wrap,
    this.unwrap,
  });

  /// What the answer is stored under, e.g. `comments-<statusId>-0`. The account is not part of it:
  /// [PageCache] puts that in front, so two accounts do not see each other's pages.
  final String key;

  final CachePolicy policy;

  /// Parses the body as it came off the wire. Used for a fresh answer too, so a cached page and a
  /// live one go through the same code — that is the point of putting parse here rather than
  /// letting each caller keep its own.
  final PageResult<T> Function(dynamic data) parse;

  /// Turns the answer into what is stored, when storing it whole would be wrong. The feed keeps the
  /// source it came from beside the body; everything else stores the body as it arrived.
  final dynamic Function(dynamic data)? wrap;

  /// Reads the stored form back out before [parse]. Null means the stored form _is_ the body.
  final dynamic Function(dynamic stored)? unwrap;

  /// The stored first page, or null when there is none, it does not parse, or it has no rows.
  ///
  /// A cache that has gone stale in a way the parser cannot read is treated as no cache: the page
  /// then shows its skeleton and asks again, which is the same state it would be in on a first
  /// launch. Letting the exception out would show 加载失败 before a request had even been sent.
  PageResult<T>? read() {
    if (policy == CachePolicy.networkOnly) return null;
    final stored = PageCache.instance.read(Session.instance.cacheScope, key);
    return decode(stored);
  }

  /// Parses an already-read raw cache payload through [unwrap] and [parse], avoiding a second
  /// decode when the caller inspected wrapper metadata first.
  PageResult<T>? decode(dynamic stored) {
    if (policy == CachePolicy.networkOnly || stored == null) return null;
    try {
      final page = parse(unwrap == null ? stored : unwrap!(stored));
      return page.items.isEmpty ? null : page;
    } catch (error) {
      if (kDebugMode) debugPrint('cached $key could not be read: $error');
      return null;
    }
  }

  /// Stores [data] as this list's first page. [isFirstPage] is the caller's answer to "was this the
  /// page a reader would see first", which every pager already knows: it is the one with no cursor.
  void write(dynamic data, {required bool isFirstPage}) {
    if (policy == CachePolicy.networkOnly || !isFirstPage || data == null) return;
    PageCache.instance.write(Session.instance.cacheScope, key, wrap == null ? data : wrap!(data));
  }

  /// Parses a live answer and stores it when it is the first page.
  PageResult<T> accept(dynamic data, {required bool isFirstPage}) {
    write(data, isFirstPage: isFirstPage);
    return parse(data);
  }
}

/// A single cached object (non-list) such as the signed-in user's own profile, sharing the same
/// account scope and corrupt-cache tolerance as [CachedPage].
@immutable
class CachedValue<T> {
  const CachedValue({
    required this.key,
    required this.parse,
    this.wrap,
  });

  final String key;
  final T? Function(dynamic data) parse;
  final dynamic Function(dynamic data)? wrap;

  T? read() {
    final stored = PageCache.instance.read(Session.instance.cacheScope, key);
    if (stored == null) return null;
    try {
      return parse(stored);
    } catch (error) {
      if (kDebugMode) debugPrint('cached $key could not be read: $error');
      return null;
    }
  }

  void write(dynamic data) {
    if (data == null) return;
    PageCache.instance.write(Session.instance.cacheScope, key, wrap == null ? data : wrap!(data));
  }
}

/// Reads the raw stored value under [key] for the current session scope, for caches whose wrapper
/// carries metadata needed to choose the parser (such as the feed's saved [FeedSource]).
dynamic readRawCached(String key) => PageCache.instance.read(Session.instance.cacheScope, key);

/// JSON, for the few lists whose stored form is not the answer itself.
///
/// Exposed rather than inlined so a `wrap`/`unwrap` pair cannot disagree about the encoding: both
/// sides of the feed's cache go through here.
dynamic decodeStored(dynamic stored) {
  if (stored is String) {
    try {
      return jsonDecode(stored);
    } on FormatException {
      return null;
    }
  }
  return stored;
}
