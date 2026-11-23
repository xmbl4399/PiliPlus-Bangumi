import 'package:PiliPlus/models_new/bangumi/bangumi_category.dart';

/// 归一化后的 Bangumi 条目，供 UI 直接消费。
///
/// 与接口原始形态的区别：
/// - 标题已做 `name_cn` 优先回退；
/// - 封面已固定选用 `common` 档；
/// - tag 已去重并按白名单分级过滤（≤2 个）。
class BangumiItem {
  const BangumiItem({
    required this.id,
    required this.title,
    required this.date,
    this.eps,
    this.score = 0,
    this.votes = 0,
    this.cover = '',
    this.tags = const [],
    this.metaTags = const [],
  });

  final int id;
  final String title;

  /// 放送日期 `yyyy-MM-dd`，空串表示未定档。
  final String date;

  /// 话数，null 表示接口未给出（日历条目恒为 null）。
  final int? eps;

  /// 评分，0 表示无评分。
  final double score;
  final int votes;
  final String cover;

  /// 卡片上展示的题材 tag（≤2 个，可能为空）。
  final List<String> tags;

  /// 原始 `meta_tags`，仅用于地区筛选（如韩剧），卡片不展示。
  final List<String> metaTags;

  bool get hasScore => score > 0;

  String get scoreText => score.toStringAsFixed(1);

  /// 从日期中取年份，解析失败返回 null。
  int? get year => date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;

  factory BangumiItem.fromJson(Map<String, dynamic> json) => BangumiItem(
    id: json['id'] as int? ?? 0,
    title: json['title'] as String? ?? '',
    date: json['date'] as String? ?? '',
    eps: json['eps'] as int?,
    score: (json['score'] as num?)?.toDouble() ?? 0,
    votes: json['votes'] as int? ?? 0,
    cover: json['cover'] as String? ?? '',
    tags:
        (json['tags'] as List<dynamic>?)?.whereType<String>().toList() ??
        const [],
    metaTags:
        (json['metaTags'] as List<dynamic>?)?.whereType<String>().toList() ??
        const [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date,
    'eps': eps,
    'score': score,
    'votes': votes,
    'cover': cover,
    'tags': tags,
    'metaTags': metaTags,
  };
}

/// 单个月份的加载结果，失败月不抛异常，用 [error] 标记。
class BangumiMonthResult {
  const BangumiMonthResult({
    required this.year,
    required this.month,
    this.items = const [],
    this.error,
  });

  final int year;
  final int month;
  final List<BangumiItem> items;
  final Object? error;

  bool get isSuccess => error == null;
}

/// 已按「今日优先、向前回溯」排好的单日分组。
class BangumiCalendarGroup {
  const BangumiCalendarGroup({
    required this.weekday,
    this.items = const [],
    this.isToday = false,
  });

  final BangumiWeekday weekday;
  final List<BangumiItem> items;
  final bool isToday;

  /// 形如「周一 · 今天 · 12部」。
  String get title {
    final buffer = StringBuffer(weekday.shortCn);
    if (isToday) buffer.write(' · 今天');
    buffer
      ..write(' · ')
      ..write(items.length)
      ..write('部');
    return buffer.toString();
  }
}
