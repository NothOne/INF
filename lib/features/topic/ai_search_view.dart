import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/chrome.dart';
import '../../core/error_text.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/smart_image.dart';

/// Starts the 智搜 tab's answer again, from the page that owns the tab.
///
/// The view keeps its answer alive across tab switches (and is not rebuilt by a pull), so a refresh
/// has to reach into it rather than rebuild it: [HotTopicPage] holds one controller, hands it to
/// [AiSearchView], and calls [reload] for its pull-to-refresh and its bar's 刷新 button.
class AiSearchController {
  Object? _owner;
  Future<bool> Function()? _reload;

  /// Called by the view when it mounts. [owner] lets a replaced view detach itself without
  /// clearing a newer one's registration.
  void attach(Object owner, Future<bool> Function() reload) {
    _owner = owner;
    _reload = reload;
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _reload = null;
  }

  /// Asks from the first loop again. False when the 智搜 tab has never been shown, so there is
  /// nothing to restart and nothing went wrong.
  Future<bool> reload() async {
    final reload = _reload;
    if (reload == null) return false;
    return reload();
  }

  void dispose() {
    _owner = null;
    _reload = null;
  }
}

/// 微博智搜 for one topic: the answer `ai.s.weibo.com` writes about it, drawn natively.
///
/// The answer arrives in loops — the same `request_id` asked again with a bigger `loop_num` —
/// so it is polled while `status == 1` and each loop's partial text is shown as it comes. Nothing
/// is requested until [active] says the tab is on screen: opening a topic on 综合 must not spend a
/// request nobody is going to read.
class AiSearchView extends StatefulWidget {
  const AiSearchView({super.key, required this.query, required this.active, this.controller});

  /// The topic's words without surrounding `#`s: the AI endpoint reads keywords, not hashtags.
  final String query;

  /// Whether the 智搜 tab is the one being read.
  final bool active;

  final AiSearchController? controller;

  @override
  State<AiSearchView> createState() => _AiSearchViewState();
}

class _AiSearchViewState extends State<AiSearchView> with AutomaticKeepAliveClientMixin {
  /// How long Weibo is given to write the next stretch of the answer.
  static const _pollGap = Duration(milliseconds: 900);

  /// Weibo's own page stops looping at 25; an answer still "generating" after that is not going to
  /// finish, and asking again only spends requests.
  static const _maxLoops = 25;

  AiSearchResult? _result;
  Object? _error;
  bool _loading = false;

  /// A poll is scheduled, i.e. the answer is expected to keep growing.
  bool _polling = false;

  /// Null follows the answer ([_thinkingExpanded]); a tap pins the reader's choice.
  bool? _thinkingOpen;

  Timer? _poll;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this, _reload);
    if (widget.active) _run();
  }

  @override
  void didUpdateWidget(AiSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(this);
      widget.controller?.attach(this, _reload);
    }
    if (oldWidget.query != widget.query) {
      _generation++;
      _poll?.cancel();
      _polling = false;
      _result = null;
      _error = null;
      _loading = false;
      _thinkingOpen = null;
      if (widget.active) _run();
    } else if (widget.active && !oldWidget.active && _result == null && !_loading) {
      // Swiped onto 智搜 with nothing to show — the first time, or after a failure. Now the request
      // is worth making; an answer already on screen stays as it is.
      _run();
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    _poll?.cancel();
    // A response that lands after this must find nothing to write to.
    _generation++;
    super.dispose();
  }

  Future<bool> _reload() {
    if (!mounted) return Future.value(false);
    final first = _run();
    setState(() {});
    return first;
  }

  /// A fresh `request_id` is a new answer; the one on screen is dropped so a slow first loop from
  /// the previous run cannot land on top of it. The returned future completes with the first loop,
  /// not the whole answer, so a pull does not hang for twenty seconds.
  Future<bool> _run() {
    final generation = ++_generation;
    _poll?.cancel();
    _polling = false;
    _result = null;
    _error = null;
    _loading = true;
    _thinkingOpen = null;
    return _ask(
      generation: generation,
      requestId: '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      loopNum: 1,
      model: null,
    );
  }

  Future<bool> _ask({
    required int generation,
    required String requestId,
    required int loopNum,
    String? model,
  }) async {
    final AiSearchResult result;
    try {
      result = await WeiboApi.instance.aiSearch(
        widget.query,
        requestId: requestId,
        loopNum: loopNum,
        model: model,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return false;
      setState(() {
        _error = error;
        _loading = false;
        _polling = false;
      });
      return false;
    }
    if (!mounted || generation != _generation) return false;
    final more = result.isGenerating && loopNum < _maxLoops;
    setState(() {
      _result = result;
      _error = null;
      _loading = false;
      _polling = more;
    });
    if (more) {
      _poll = Timer(
        _pollGap,
        () => _ask(
          generation: generation,
          requestId: requestId,
          loopNum: loopNum + 1,
          // The model Weibo picked on the first loop is the one that keeps answering.
          model: result.model ?? model,
        ),
      );
    }
    return true;
  }

  /// Expanded while there is nothing to read but the thinking, collapsed once the answer is there
  /// — unless the reader opened or closed it themselves.
  bool _thinkingExpanded(AiSearchResult result) =>
      _thinkingOpen ?? (result.isGenerating && result.blocks.isEmpty);

  void _openWeb() => openWeb(context, 'https://s.weibo.com/aisearch?q=${Uri.encodeComponent(widget.query)}');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final error = _error;
    final thinking = result?.thinking;
    final hasThinking = thinking != null && thinking.isNotEmpty;
    // `_polling` rather than `isGenerating`: a loop that gave up at [_maxLoops] is not going to
    // add anything more, and an answer that never arrived has to offer its retry.
    final empty = result != null && !_polling && result.blocks.isEmpty && !hasThinking;
    final gutter = contentGutter(context);
    return ListView(
      // The pull belongs to the page's InfRefreshIndicator; this only has to report it.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        gutter + 16,
        10,
        gutter + 16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _Header(
          model: result?.model,
          busy: _loading,
          onReload: _reload,
          onWeb: _openWeb,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 56),
            child: ErrorView(error: error, onRetry: _reload),
          )
        else if (result == null)
          const Padding(padding: EdgeInsets.only(top: 10), child: _AnswerSkeleton())
        else ...[
          if (hasThinking)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 12),
              child: AiSearchThinking(
                text: thinking,
                expanded: _thinkingExpanded(result),
                generating: result.isGenerating && result.blocks.isEmpty,
                onToggle: () => setState(() => _thinkingOpen = !_thinkingExpanded(result)),
              ),
            ),
          if (empty)
            _EmptyAnswer(onRetry: _reload, onWeb: _openWeb)
          else
            AiSearchBody(result: result),
          if (_polling)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(
                    '正在整理最新微博观点…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// The strip above the answer: what wrote it, and the ways to ask again or to read it on the web.
class _Header extends StatelessWidget {
  const _Header({required this.model, required this.busy, required this.onReload, required this.onWeb});

  final String? model;
  final bool busy;
  final VoidCallback onReload;
  final VoidCallback onWeb;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = Theme.of(context).textTheme;
    final model = this.model;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                '微博智搜',
                style: styles.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        if (model != null && model.isNotEmpty) ...[
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Tooltip(
              message: model,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHighest, 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
        const Spacer(),
        IconButton(
          onPressed: onReload,
          tooltip: '刷新',
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          icon: busy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded),
        ),
        TextButton(
          onPressed: onWeb,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('网页版'),
        ),
      ],
    );
  }
}

/// The stretch of the answer that is the model talking to itself, behind a tap.
///
/// Open while it is the only thing to read (the answer has not started), closed once there is an
/// answer, and the reader's own tap wins over both.
class AiSearchThinking extends StatelessWidget {
  const AiSearchThinking({
    super.key,
    required this.text,
    required this.expanded,
    required this.onToggle,
    this.generating = false,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  /// Nothing has been written yet, so the card says the model is still thinking.
  final bool generating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = Theme.of(context).textTheme;
    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerLow, 0.75),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onToggle,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55), width: 0.8),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_alt_outlined, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '思考过程',
                    style: styles.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (generating) ...[
                    const SizedBox(width: 8),
                    Text('正在思考…', style: styles.labelSmall?.copyWith(color: scheme.primary)),
                  ],
                  const Spacer(),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: InfMotion.feedback,
                    curve: InfMotion.emphasized,
                    child: Icon(Icons.expand_more_rounded, size: 20, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              AnimatedSize(
                duration: InfMotion.feedback,
                curve: InfMotion.emphasized,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6, right: 6),
                        child: Text(
                          text,
                          style: styles.bodySmall?.copyWith(height: 1.6, color: scheme.onSurfaceVariant),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The answer itself: headings, paragraphs, bullets and their pictures, rendered from a parsed
/// [AiSearchResult]. Public so it can be drawn (and tested) without a request.
class AiSearchBody extends StatelessWidget {
  const AiSearchBody({super.key, required this.result});

  final AiSearchResult result;

  @override
  Widget build(BuildContext context) {
    final blocks = result.blocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) _block(context, blocks[i], first: i == 0),
      ],
    );
  }

  Widget _block(BuildContext context, AiSearchBlock block, {required bool first}) {
    final scheme = Theme.of(context).colorScheme;
    final styles = Theme.of(context).textTheme;
    final body = styles.bodyMedium?.copyWith(height: 1.65);
    final quotes = block.quotes.isEmpty
        ? null
        : Padding(padding: const EdgeInsets.only(top: 8), child: _Quotes(quotes: block.quotes));
    switch (block.kind) {
      case AiSearchBlockKind.heading:
        final style = block.level <= 1
            ? styles.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.3)
            : styles.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.35);
        return Padding(
          padding: EdgeInsets.only(top: first ? 2 : 18, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.text.isNotEmpty) _RichLine(text: block.text, style: style),
              ?quotes,
            ],
          ),
        );
      case AiSearchBlockKind.paragraph:
        return Padding(
          padding: EdgeInsets.only(top: first ? 2 : 0, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.text.isNotEmpty) _RichLine(text: block.text, style: body),
              ?quotes,
            ],
          ),
        );
      case AiSearchBlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '•',
                style: body?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (block.text.isNotEmpty) _RichLine(text: block.text, style: body),
                    ?quotes,
                  ],
                ),
              ),
            ],
          ),
        );
      case AiSearchBlockKind.media:
        return Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: block.media.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final media = block.media[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openMedia(context, media),
                  child: SmartImage(
                    url: media.imageUrl,
                    width: 124,
                    height: 124,
                    radius: 12,
                    cacheWidth: 372,
                  ),
                );
              },
            ),
          ),
        );
    }
  }
}

/// A cited post: 智搜 links each claim to the posts it read.
class _Quotes extends StatelessWidget {
  const _Quotes({required this.quotes});

  final List<AiSearchQuote> quotes;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final quote in quotes) _QuoteChip(quote: quote)],
    );
  }
}

class _QuoteChip extends StatelessWidget {
  const _QuoteChip({required this.quote});

  final AiSearchQuote quote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = Theme.of(context).textTheme;
    final chip = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_rounded, size: 13, color: scheme.primary),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              quote.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    final label = quote.label;
    return Tooltip(
      message: label != null && label.isNotEmpty ? label : quote.name,
      child: Material(
        color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHighest, 0.6),
        borderRadius: BorderRadius.circular(20),
        child: quote.scheme.isEmpty
            ? chip
            : InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => openLink(context, quote.scheme),
                child: chip,
              ),
      ),
    );
  }
}

class _AnswerSkeleton extends StatelessWidget {
  const _AnswerSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 160, height: 14),
          SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 12),
          SizedBox(height: 9),
          SkeletonBox(width: double.infinity, height: 12),
          SizedBox(height: 9),
          SkeletonBox(width: 240, height: 12),
          SizedBox(height: 18),
          SkeletonBox(width: double.infinity, height: 72, radius: 10),
        ],
      ),
    );
  }
}

class _EmptyAnswer extends StatelessWidget {
  const _EmptyAnswer({required this.onRetry, required this.onWeb});

  final VoidCallback onRetry;
  final VoidCallback onWeb;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 36, color: scheme.onSurfaceVariant.withValues(alpha: 0.45)),
          const SizedBox(height: 10),
          Text(
            '智搜还没有整理出内容',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton(onPressed: onRetry, child: const Text('重新生成')),
              TextButton(onPressed: onWeb, child: const Text('在网页版查看')),
            ],
          ),
        ],
      ),
    );
  }
}

/// One paragraph of the answer. Markup is not shown as markup: `**bold**` is bold,
/// `<hl>…</hl>` is the accent colour, and `[text](url)` is a tappable link.
class _RichLine extends StatefulWidget {
  const _RichLine({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_RichLine> createState() => _RichLineState();
}

class _RichLineState extends State<_RichLine> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.style ?? Theme.of(context).textTheme.bodyMedium;
    _clear();
    final spans = <InlineSpan>[];
    for (final run in parseAiSearchRuns(widget.text)) {
      switch (run.kind) {
        case AiSearchRunKind.plain:
          spans.add(TextSpan(text: run.text));
        case AiSearchRunKind.bold:
          spans.add(TextSpan(text: run.text, style: const TextStyle(fontWeight: FontWeight.w700)));
        case AiSearchRunKind.highlight:
          spans.add(TextSpan(
            text: run.text,
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
              backgroundColor: scheme.primary.withValues(alpha: 0.10),
            ),
          ));
        case AiSearchRunKind.link:
          final url = run.url!;
          final recognizer = TapGestureRecognizer()..onTap = () => openLink(context, url);
          _recognizers.add(recognizer);
          spans.add(TextSpan(
            text: run.text,
            style: TextStyle(
              color: scheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary.withValues(alpha: 0.4),
            ),
            recognizer: recognizer,
          ));
      }
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

enum AiSearchRunKind { plain, bold, highlight, link }

/// One run of a 智搜 paragraph once its inline markup is off.
class AiSearchRun {
  final AiSearchRunKind kind;
  final String text;

  /// Where a [AiSearchRunKind.link] goes.
  final String? url;

  const AiSearchRun(this.kind, this.text, {this.url});
}

final _aiRunPattern = RegExp(r'\*\*(.+?)\*\*|<hl>([\s\S]*?)</hl>|\[([^\]\n]+)\]\((https?:\/\/[^)\s]+)\)');

/// Splits a paragraph into plain, bold, highlighted and linked runs.
List<AiSearchRun> parseAiSearchRuns(String text) {
  final runs = <AiSearchRun>[];
  void plain(String value) {
    if (value.isEmpty) return;
    // Neighbouring plain text is one run, so a paragraph does not turn into a span per character.
    if (runs.isNotEmpty && runs.last.kind == AiSearchRunKind.plain) {
      runs[runs.length - 1] = AiSearchRun(AiSearchRunKind.plain, runs.last.text + value);
    } else {
      runs.add(AiSearchRun(AiSearchRunKind.plain, value));
    }
  }

  var cursor = 0;
  for (final match in _aiRunPattern.allMatches(text)) {
    if (match.start > cursor) plain(text.substring(cursor, match.start));
    cursor = match.end;
    final bold = match.group(1);
    final highlight = match.group(2);
    final label = match.group(3);
    final url = match.group(4);
    if (bold != null) {
      runs.add(AiSearchRun(AiSearchRunKind.bold, bold));
    } else if (highlight != null) {
      runs.add(AiSearchRun(AiSearchRunKind.highlight, highlight));
    } else if (label != null && url != null) {
      runs.add(AiSearchRun(AiSearchRunKind.link, label, url: url));
    }
  }
  if (cursor < text.length) plain(text.substring(cursor));
  return runs;
}

void _openMedia(BuildContext context, AiSearchMedia media) {
  final statusId = media.statusId;
  if (statusId != null && statusId.isNotEmpty) {
    openStatus(context, statusId: statusId);
    return;
  }
  openImage(context, media: [Media.image(media.imageUrl)]);
}
