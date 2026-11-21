import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../haptics.dart';
import '../models.dart';
import '../motion.dart';

/// The cities weibo.com has a 同城 feed for, as `80086` + the four-digit GB/T 2260 prefix of the
/// prefecture. `CityChoice.hotCities` are the same cities, so a code added here is worth adding
/// there too when it is a major one; `searchWeiboCities` reads this table only.
const List<CityChoice> kWeiboCities = [
  // 直辖市
  CityChoice(code: '800861100', name: '北京'),
  CityChoice(code: '800861200', name: '天津'),
  CityChoice(code: '800863100', name: '上海'),
  CityChoice(code: '800865000', name: '重庆'),
  // 河北
  CityChoice(code: '800861301', name: '石家庄'),
  CityChoice(code: '800861302', name: '唐山'),
  CityChoice(code: '800861303', name: '秦皇岛'),
  CityChoice(code: '800861304', name: '邯郸'),
  CityChoice(code: '800861306', name: '保定'),
  CityChoice(code: '800861310', name: '廊坊'),
  // 山西
  CityChoice(code: '800861401', name: '太原'),
  CityChoice(code: '800861402', name: '大同'),
  CityChoice(code: '800861410', name: '临汾'),
  // 内蒙古
  CityChoice(code: '800861501', name: '呼和浩特'),
  CityChoice(code: '800861502', name: '包头'),
  CityChoice(code: '800861506', name: '鄂尔多斯'),
  // 辽宁
  CityChoice(code: '800862101', name: '沈阳'),
  CityChoice(code: '800862102', name: '大连'),
  CityChoice(code: '800862103', name: '鞍山'),
  CityChoice(code: '800862107', name: '锦州'),
  // 吉林
  CityChoice(code: '800862201', name: '长春'),
  CityChoice(code: '800862202', name: '吉林'),
  // 黑龙江
  CityChoice(code: '800862301', name: '哈尔滨'),
  CityChoice(code: '800862302', name: '齐齐哈尔'),
  CityChoice(code: '800862306', name: '大庆'),
  // 江苏
  CityChoice(code: '800863201', name: '南京'),
  CityChoice(code: '800863202', name: '无锡'),
  CityChoice(code: '800863203', name: '徐州'),
  CityChoice(code: '800863204', name: '常州'),
  CityChoice(code: '800863205', name: '苏州'),
  CityChoice(code: '800863206', name: '南通'),
  CityChoice(code: '800863210', name: '扬州'),
  // 浙江
  CityChoice(code: '800863301', name: '杭州'),
  CityChoice(code: '800863302', name: '宁波'),
  CityChoice(code: '800863303', name: '温州'),
  CityChoice(code: '800863304', name: '嘉兴'),
  CityChoice(code: '800863306', name: '绍兴'),
  CityChoice(code: '800863307', name: '金华'),
  CityChoice(code: '800863310', name: '台州'),
  // 安徽
  CityChoice(code: '800863401', name: '合肥'),
  CityChoice(code: '800863402', name: '芜湖'),
  CityChoice(code: '800863403', name: '蚌埠'),
  CityChoice(code: '800863408', name: '安庆'),
  CityChoice(code: '800863410', name: '黄山'),
  // 福建
  CityChoice(code: '800863501', name: '福州'),
  CityChoice(code: '800863502', name: '厦门'),
  CityChoice(code: '800863503', name: '莆田'),
  CityChoice(code: '800863505', name: '泉州'),
  CityChoice(code: '800863506', name: '漳州'),
  // 江西
  CityChoice(code: '800863601', name: '南昌'),
  CityChoice(code: '800863602', name: '景德镇'),
  CityChoice(code: '800863604', name: '九江'),
  CityChoice(code: '800863607', name: '赣州'),
  // 山东
  CityChoice(code: '800863701', name: '济南'),
  CityChoice(code: '800863702', name: '青岛'),
  CityChoice(code: '800863703', name: '淄博'),
  CityChoice(code: '800863706', name: '烟台'),
  CityChoice(code: '800863707', name: '潍坊'),
  CityChoice(code: '800863710', name: '威海'),
  CityChoice(code: '800863713', name: '临沂'),
  // 河南
  CityChoice(code: '800864101', name: '郑州'),
  CityChoice(code: '800864102', name: '开封'),
  CityChoice(code: '800864103', name: '洛阳'),
  CityChoice(code: '800864107', name: '新乡'),
  CityChoice(code: '800864113', name: '南阳'),
  // 湖北
  CityChoice(code: '800864201', name: '武汉'),
  CityChoice(code: '800864205', name: '宜昌'),
  CityChoice(code: '800864206', name: '襄阳'),
  CityChoice(code: '800864210', name: '荆州'),
  // 湖南
  CityChoice(code: '800864301', name: '长沙'),
  CityChoice(code: '800864302', name: '株洲'),
  CityChoice(code: '800864303', name: '湘潭'),
  CityChoice(code: '800864304', name: '衡阳'),
  CityChoice(code: '800864306', name: '岳阳'),
  CityChoice(code: '800864308', name: '张家界'),
  // 广东
  CityChoice(code: '800864401', name: '广州'),
  CityChoice(code: '800864403', name: '深圳'),
  CityChoice(code: '800864404', name: '珠海'),
  CityChoice(code: '800864405', name: '汕头'),
  CityChoice(code: '800864406', name: '佛山'),
  CityChoice(code: '800864407', name: '江门'),
  CityChoice(code: '800864408', name: '湛江'),
  CityChoice(code: '800864413', name: '惠州'),
  CityChoice(code: '800864419', name: '东莞'),
  CityChoice(code: '800864420', name: '中山'),
  // 广西
  CityChoice(code: '800864501', name: '南宁'),
  CityChoice(code: '800864502', name: '柳州'),
  CityChoice(code: '800864503', name: '桂林'),
  CityChoice(code: '800864505', name: '北海'),
  // 海南
  CityChoice(code: '800864601', name: '海口'),
  CityChoice(code: '800864602', name: '三亚'),
  // 四川
  CityChoice(code: '800865101', name: '成都'),
  CityChoice(code: '800865107', name: '绵阳'),
  CityChoice(code: '800865111', name: '乐山'),
  CityChoice(code: '800865113', name: '南充'),
  CityChoice(code: '800865115', name: '宜宾'),
  // 贵州
  CityChoice(code: '800865201', name: '贵阳'),
  CityChoice(code: '800865203', name: '遵义'),
  // 云南
  CityChoice(code: '800865301', name: '昆明'),
  CityChoice(code: '800865307', name: '丽江'),
  CityChoice(code: '800865329', name: '大理'),
  // 西藏
  CityChoice(code: '800865401', name: '拉萨'),
  // 陕西
  CityChoice(code: '800866101', name: '西安'),
  CityChoice(code: '800866103', name: '宝鸡'),
  CityChoice(code: '800866104', name: '咸阳'),
  CityChoice(code: '800866106', name: '延安'),
  // 甘肃
  CityChoice(code: '800866201', name: '兰州'),
  CityChoice(code: '800866205', name: '天水'),
  // 青海
  CityChoice(code: '800866301', name: '西宁'),
  // 宁夏
  CityChoice(code: '800866401', name: '银川'),
  CityChoice(code: '800866402', name: '石嘴山'),
  // 新疆
  CityChoice(code: '800866501', name: '乌鲁木齐'),
  CityChoice(code: '800866502', name: '克拉玛依'),
];

/// [query] against the table, in the order weibo.com's own city search returns them: the city whose
/// name is exactly the query, then the names starting with it, then the ones merely containing it.
/// An empty query has no matches — the sheet shows the hot cities instead.
List<CityChoice> searchWeiboCities(String query) {
  final text = query.trim();
  if (text.isEmpty) return const [];
  final exact = <CityChoice>[];
  final prefix = <CityChoice>[];
  final inside = <CityChoice>[];
  for (final city in kWeiboCities) {
    if (city.name == text) {
      exact.add(city);
    } else if (city.name.startsWith(text)) {
      prefix.add(city);
    } else if (city.name.contains(text)) {
      inside.add(city);
    }
  }
  return [...exact, ...prefix, ...inside];
}

/// Picks the city 同城微博 and 同城热搜 share. [current] is the one already chosen, highlighted on
/// its chip and row; [onLocate] adds a 重新定位 button that resolves the device's own city (see
/// `Native.currentLocation` and the reverse geocoding that follows it) and answers null when that
/// failed, which leaves the manual list in place.
///
/// Solid in every style: a picker that is typed in is not frosted, and the liquid sheet's motion is
/// left off with it.
Future<CityChoice?> showCityPickerSheet(
  BuildContext context, {
  CityChoice? current,
  Future<CityChoice?> Function()? onLocate,
}) {
  return showActionSheet<CityChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    frosted: false,
    builder: (sheetContext) => _CityPickerSheet(current: current, onLocate: onLocate),
  );
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({this.current, this.onLocate});

  final CityChoice? current;
  final Future<CityChoice?> Function()? onLocate;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final TextEditingController _query = TextEditingController();
  bool _locating = false;
  bool _locateFailed = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _pick(String code, String name) {
    Haptic.selection.play();
    Navigator.pop(context, CityChoice(code: code, name: name, manual: true));
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locateFailed = false;
    });
    final city = await widget.onLocate!();
    if (!mounted) return;
    if (city != null) {
      Haptic.success.play();
      Navigator.pop(context, city);
      return;
    }
    // Said in the sheet rather than with a snackbar: the bar would sit on the page behind this
    // panel, where it cannot be read.
    Haptic.error.play();
    setState(() {
      _locating = false;
      _locateFailed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final insets = MediaQuery.viewInsetsOf(context);
    final query = _query.text.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(240, MediaQuery.sizeOf(context).height * 0.75 - insets.bottom)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('选择城市', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (widget.onLocate != null)
                    TextButton.icon(
                      onPressed: _locating ? null : _locate,
                      icon: _locating
                          ? const SizedBox.square(dimension: 15, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded, size: 18),
                      label: Text(_locating ? '定位中…' : '重新定位'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索城市',
                  isDense: true,
                  filled: true,
                  // The sheet is solid in every style, so the ambient surface colour is its colour.
                  fillColor: scheme.surfaceContainerHighest,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => setState(_query.clear),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: '清除',
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (_locateFailed)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    Icon(Icons.location_off_rounded, size: 15, color: scheme.error),
                    const SizedBox(width: 6),
                    Text('定位失败，请手动选择城市', style: text.bodySmall?.copyWith(color: scheme.error)),
                  ],
                ),
              ),
            Flexible(child: query.isEmpty ? _hot(context) : _matches(context, query)),
          ],
        ),
      ),
    );
  }

  Widget _hot(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('热门城市', style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final city in CityChoice.hotCities)
                ChoiceChip(
                  label: Text(city.name),
                  selected: city.code == widget.current?.code,
                  onSelected: (_) => _pick(city.code, city.name),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _matches(BuildContext context, String query) {
    final scheme = Theme.of(context).colorScheme;
    final matches = searchWeiboCities(query);
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Text(
          '没有找到「$query」，试试别的写法',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final city = matches[index];
        final selected = city.code == widget.current?.code;
        return ListTile(
          dense: true,
          selected: selected,
          title: Text(city.name),
          trailing: selected ? Icon(Icons.check_rounded, size: 20, color: scheme.primary) : null,
          onTap: () => _pick(city.code, city.name),
        );
      },
    );
  }
}
