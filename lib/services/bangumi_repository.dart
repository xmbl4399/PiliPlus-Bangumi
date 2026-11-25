import 'dart:async';

import 'package:PiliPlus/http/bangumi.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_calendar.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_category.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_item.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_subject.dart';
import 'package:PiliPlus/services/bangumi_cache.dart';
import 'package:PiliPlus/utils/bangumi_tag.dart';

/// Bangumi 条目数据仓库。
///
/// 取数口径：
/// - 按年月浏览不带 `sort` 参数（`sort=rank` 与 year+month 组合在服务端不稳定）；
/// - 拉全月后在本地按评分降序（无评分按日期垫底）；
/// - 不做详情补拉（详情接口的 tags 与列表项逐字节一致）。
abstract final class BangumiRepository {
  /// 韩剧判定用的 `meta_tags` 词。
  static const String koreanMetaTag = '韩国';

  static const int _defaultConcurrency = 4;
  static const List<int> _defaultMonths = [
    12,
    11,
    10,
    9,
    8,
    7,
    6,
    5,
    4,
    3,
    2,
    1,
  ];

  /// 拉取全站周历并按「今日优先、向前回溯」排好。
  static Future<LoadingState<List<BangumiCalendarGroup>>> loadCalendar({
    BangumiWeekday? today,
    bool hideNoScore = false,
  }) async {
    try {
      var byWeekday = BangumiCache.getCalendar();
      if (byWeekday == null) {
        final days = await BangumiHttp.getCalendar();
        byWeekday = <int, List<BangumiItem>>{
          for (final day in days)
            day.weekday.id: [
              for (final subject in day.items)
                if (subject.id > 0) _normalizeCalendar(subject),
            ],
        };
        BangumiCache.putCalendar(byWeekday);
      }
      final target = today ?? BangumiWeekday.today;
      final groups = [
        for (final weekday in BangumiWeekday.orderFrom(target))
          BangumiCalendarGroup(
            weekday: weekday,
            items: _hideNoScore(byWeekday[weekday.id] ?? const [], hideNoScore),
            isToday: weekday == target,
          ),
      ];
      return Success(groups);
    } catch (error) {
      return Error(_errorMessage(error));
    }
  }

  /// 拉取某分类某年某月的全部条目（自动翻页）。
  static Future<LoadingState<List<BangumiItem>>> browseYearMonth({
    required BangumiCategory category,
    required int year,
    required int month,
    bool hideNoScore = false,
  }) async {
    try {
      final raw = await _fetchMonth(
        category.type,
        category.cat,
        year,
        month,
      );

      final scoped = category.korean
          ? raw.where((e) => e.metaTags.contains(koreanMetaTag)).toList()
          : raw;
      return Success(_hideNoScore(scoped, hideNoScore));
    } catch (error) {
      return Error(_errorMessage(error));
    }
  }

  /// 加载某分类某年的全年条目，每完成一个月就推一条结果。
  ///
  /// 单月失败不影响其他月份；默认月份倒序（当季优先返回），
  /// 但推送顺序按完成先后，需要稳定顺序请按 [BangumiMonthResult.month] 自行排序。
  static Stream<BangumiMonthResult> loadYear({
    required BangumiCategory category,
    required int year,
    List<int>? months,
    bool hideNoScore = false,
    int concurrency = _defaultConcurrency,
  }) async* {
    final targetMonths = months ?? _defaultMonths;
    final batchSize = concurrency < 1 ? 1 : concurrency;
    for (var start = 0; start < targetMonths.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, targetMonths.length);
      final batch = targetMonths.sublist(start, end);
      // Stream.fromFutures 按完成顺序产出，先返回的月份先渲染。
      yield* Stream.fromFutures(
        batch.map(
          (month) => _loadMonth(
            category: category,
            year: year,
            month: month,
            hideNoScore: hideNoScore,
          ),
        ),
      );
    }
  }

  static Future<BangumiMonthResult> _loadMonth({
    required BangumiCategory category,
    required int year,
    required int month,
    required bool hideNoScore,
  }) async {
    try {
      final items = await _fetchMonth(
        category.type,
        category.cat,
        year,
        month,
      );
      final scoped = category.korean
          ? items.where((e) => e.metaTags.contains(koreanMetaTag)).toList()
          : items;
      return BangumiMonthResult(
        year: year,
        month: month,
        items: _hideNoScore(scoped, hideNoScore),
      );
    } catch (error) {
      return BangumiMonthResult(year: year, month: month, error: error);
    }
  }

  /// 拉取单个 `type + cat` 的整月条目，并写入 / 读取缓存。
  static Future<List<BangumiItem>> _fetchMonth(
    int type,
    int cat,
    int year,
    int month,
  ) async {
    final cached = BangumiCache.get(
      type: type,
      cat: cat,
      year: year,
      month: month,
    );
    if (cached != null) return cached;

    final collected = <int, BangumiItem>{};
    var offset = 0;
    while (true) {
      final page = await BangumiHttp.getSubjects(
        type: type,
        cat: cat,
        year: year,
        month: month,
        limit: BangumiHttp.pageLimit,
        offset: offset,
      );
      for (final subject in page.data) {
        if (subject.id > 0) {
          collected[subject.id] = _normalize(subject);
        }
      }
      if (page.data.length < BangumiHttp.pageLimit) break;
      offset += BangumiHttp.pageLimit;
      if (offset > BangumiHttp.maxOffset) break;
    }
    final sorted = collected.values.toList()..sort(_itemOrder);
    BangumiCache.put(
      type: type,
      cat: cat,
      year: year,
      month: month,
      items: sorted,
    );
    return sorted;
  }

  static List<BangumiItem> _hideNoScore(
    List<BangumiItem> items,
    bool hideNoScore,
  ) => hideNoScore ? items.where((e) => e.hasScore).toList() : items;

  static BangumiItem _normalize(BangumiSubject subject) => BangumiItem(
    id: subject.id,
    title: subject.nameCn.trim().isNotEmpty ? subject.nameCn : subject.name,
    date: subject.date,
    eps: subject.eps > 0 ? subject.eps : null,
    score: subject.rating.score,
    votes: subject.rating.total,
    cover: subject.images.cover,
    tags: BangumiTag.pick(BangumiTag.buildPool(subject)),
    metaTags: <String>{
      for (final tag in subject.metaTags)
        if (tag.trim().isNotEmpty) tag,
    }.toList(),
  );

  /// 日历条目没有集数 / 投票词 / meta_tags，只保留标题、封面、评分与日期。
  static BangumiItem _normalizeCalendar(BangumiCalendarSubject subject) =>
      BangumiItem(
        id: subject.id,
        title: subject.nameCn.trim().isNotEmpty ? subject.nameCn : subject.name,
        date: subject.airDate,
        score: subject.rating.score,
        votes: subject.rating.total,
        cover: subject.images.cover,
      );

  /// 评分降序，无评分沉底，同分按放送日期升序。
  static int _itemOrder(BangumiItem a, BangumiItem b) {
    final aKey = a.hasScore ? a.score : -1.0;
    final bKey = b.hasScore ? b.score : -1.0;
    final byScore = bKey.compareTo(aKey);
    if (byScore != 0) return byScore;
    return a.date.compareTo(b.date);
  }

  static String _errorMessage(Object error) {
    final text = error.toString();
    return text.isEmpty ? 'Bangumi 请求失败' : text;
  }
}
