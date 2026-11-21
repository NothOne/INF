import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../hot_search_store.dart';
import '../motion.dart';

/// Opens a solid (non-frosted) sheet for picking or typing a Weibo `#话题#`.
///
/// Completes with the bare topic name (without surrounding `#`s), or `null` if dismissed.
/// An empty string `''` means the caller should insert an empty `##` pair and put the cursor
/// between them for free typing.
Future<String?> showTopicPicker(BuildContext context) {
  return showActionSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    frosted: false,
    builder: (context) => const TopicPicker(),
  );
}

class TopicPicker extends StatefulWidget {
  const TopicPicker({super.key});

  @override
  State<TopicPicker> createState() => _TopicPickerState();
}

class _TopicPickerState extends State<TopicPicker> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<String> _suggestions = const [];
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    HotSearchStore.instance.addListener(_onHotChanged);
    if (HotSearchStore.instance.entries == null) {
      HotSearchStore.instance.load();
    }
  }

  @override
  void dispose() {
    HotSearchStore.instance.removeListener(_onHotChanged);
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onHotChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final clean = value.replaceAll('#', '').trim();
    if (clean.isEmpty) {
      _generation++;
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 240), () => _search(clean));
  }

  Future<void> _search(String query) async {
    final gen = ++_generation;
    try {
      final list = await WeiboApi.instance.topicSuggestions(query);
      if (!mounted || gen != _generation) return;
      setState(() {
        _suggestions = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() => _loading = false);
    }
  }

  void _submit(String raw) {
    final clean = raw.replaceAll('#', '').trim();
    Navigator.pop(context, clean);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final clean = _query.text.replaceAll('#', '').trim();
    final hot = HotSearchStore.instance.entries ?? const [];

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: TextField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: _onChanged,
                onSubmitted: (value) => _submit(value),
                decoration: InputDecoration(
                  hintText: '搜索话题，或输入自定义话题',
                  prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                  suffixIcon: clean.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _query.clear();
                            _onChanged('');
                          },
                        ),
                ),
              ),
            ),
            if (clean.isNotEmpty)
              ListTile(
                leading: Icon(Icons.tag_rounded, color: scheme.primary),
                title: Text('#$clean#'),
                subtitle: const Text('直接插入这个话题'),
                onTap: () => _submit(clean),
              )
            else
              ListTile(
                leading: Icon(Icons.edit_outlined, color: scheme.primary),
                title: const Text('自己输入 #话题#'),
                subtitle: const Text('插入 ## 并直接手打话题内容'),
                onTap: () => Navigator.pop(context, ''),
              ),
            if (clean.isEmpty && hot.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Text(
                  '热门话题',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: clean.isNotEmpty
                  ? _loading && _suggestions.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _suggestions.isEmpty
                          ? Center(
                              child: Text(
                                '没有匹配的话题，可直接点上方插入 #$clean#',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _suggestions.length,
                              itemBuilder: (context, index) {
                                final topic = _suggestions[index];
                                return ListTile(
                                  leading: Icon(Icons.tag_rounded, size: 20, color: scheme.onSurfaceVariant),
                                  title: Text('#$topic#', maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onTap: () => _submit(topic),
                                );
                              },
                            )
                  : ListView.builder(
                      itemCount: hot.length.clamp(0, 20),
                      itemBuilder: (context, index) {
                        final entry = hot[index];
                        final name = entry.word.replaceAll('#', '').trim();
                        return ListTile(
                          leading: Icon(Icons.local_fire_department_outlined, size: 20, color: scheme.onSurfaceVariant),
                          title: Text('#$name#', maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _submit(name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
