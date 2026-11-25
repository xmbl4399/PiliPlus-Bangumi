import 'package:PiliPlus/models_new/bangumi/bangumi_item.dart';
import 'package:PiliPlus/utils/storage.dart';

/// Bangumi 列表缓存。
///
/// 两类数据：
/// - 月份列表：键为「大类 + 子分类 + 年 + 月」，当季 / 未来月份 6 小时，
///   历史月份 30 天；**空结果只缓存 30 分钟**，避免刚开播的新番被长期钉住。
/// - 新番表（`/calendar`）：整份周历缓存 60 分钟，对齐接口的 `max-age`。
///
/// 「隐藏无评分」「韩剧过滤」不参与缓存键，过滤在调用方做。
/// 内存命中最快；未命中时回落到 Hive（`GStorage.localCache`）。
abstract final class BangumiCache {
  static const String _calendarKey = 'bangumi.calendar';

  /// 空月份结果的短缓存时间。
  static const Duration emptyTtl = Duration(minutes: 30);

  /// 新番表缓存时间。
  static const Duration calendarTtl = Duration(minutes: 60);

  static final Map<String, _CacheEntry> _memory = {};
  static _CalendarEntry? _calendarMemory;

  static String _key({
    required int type,
    required int cat,
    required int year,
    required int month,
  }) => 'bangumi.$type.$cat.$year.$month';

  static Duration ttl({required int year, required int month}) {
    final now = DateTime.now();
    final isRecent = year > now.year || (year == now.year && month >= now.month);
    return Duration(hours: isRecent ? 6 : 24 * 30);
  }

  static List<BangumiItem>? get({
    required int type,
    required int cat,
    required int year,
    required int month,
  }) {
    final key = _key(type: type, cat: cat, year: year, month: month);
    final entry = _memory[key];
    if (entry != null) {
      if (entry.expireAt.isBefore(DateTime.now())) {
        _memory.remove(key);
        return null;
      }
      return entry.items;
    }
    final disk = _readDisk(key);
    if (disk != null) {
      _memory[key] = _CacheEntry(
        items: disk,
        expireAt: DateTime.now().add(
          disk.isEmpty ? emptyTtl : ttl(year: year, month: month),
        ),
      );
    }
    return disk;
  }

  static void put({
    required int type,
    required int cat,
    required int year,
    required int month,
    required List<BangumiItem> items,
  }) {
    final key = _key(type: type, cat: cat, year: year, month: month);
    final expireAt = DateTime.now().add(
      items.isEmpty ? emptyTtl : ttl(year: year, month: month),
    );
    _memory[key] = _CacheEntry(items: items, expireAt: expireAt);
    _writeDisk(key, items, expireAt);
  }

  /// 读取新番表：返回「星期 id -> 条目」；未缓存或过期返回 null。
  static Map<int, List<BangumiItem>>? getCalendar() {
    final memory = _calendarMemory;
    if (memory != null) {
      if (memory.expireAt.isBefore(DateTime.now())) {
        _calendarMemory = null;
      } else {
        return memory.days;
      }
    }
    try {
      final data = GStorage.localCache.get(_calendarKey);
      if (data is! Map) return null;
      final expireAt = data['expireAt'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch >= expireAt) return null;
      final days = <int, List<BangumiItem>>{};
      final rawDays = data['days'];
      if (rawDays is List) {
        for (final day in rawDays) {
          if (day is! Map) continue;
          final weekday = day['weekday'] as int? ?? 0;
          if (weekday <= 0) continue;
          days[weekday] =
              (day['items'] as List?)
                  ?.whereType<Map>()
                  .map((e) => BangumiItem.fromJson(e.cast<String, dynamic>()))
                  .toList() ??
              const [];
        }
      }
      _calendarMemory = _CalendarEntry(
        days: days,
        expireAt: DateTime.fromMillisecondsSinceEpoch(expireAt),
      );
      return days;
    } catch (_) {
      return null;
    }
  }

  /// 写入新番表（未做「隐藏无评分」过滤的原始分组）。
  static void putCalendar(Map<int, List<BangumiItem>> days) {
    final expireAt = DateTime.now().add(calendarTtl);
    _calendarMemory = _CalendarEntry(days: days, expireAt: expireAt);
    try {
      GStorage.localCache.put(_calendarKey, {
        'expireAt': expireAt.millisecondsSinceEpoch,
        'days': [
          for (final entry in days.entries)
            {
              'weekday': entry.key,
              'items': [for (final item in entry.value) item.toJson()],
            },
        ],
      });
    } catch (_) {
      // 缓存写失败不影响主流程
    }
  }

  static List<BangumiItem>? _readDisk(String key) {
    try {
      final data = GStorage.localCache.get(key);
      if (data is! Map) return null;
      final expireAt = data['expireAt'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch >= expireAt) return null;
      final items = (data['items'] as List?)
          ?.whereType<Map>()
          .map((e) => BangumiItem.fromJson(e.cast<String, dynamic>()))
          .toList();
      return items;
    } catch (_) {
      return null;
    }
  }

  static void _writeDisk(
    String key,
    List<BangumiItem> items,
    DateTime expireAt,
  ) {
    try {
      GStorage.localCache.put(key, {
        'expireAt': expireAt.millisecondsSinceEpoch,
        'items': [for (final item in items) item.toJson()],
      });
    } catch (_) {
      // 缓存写失败不影响主流程
    }
  }

  static void clear() {
    _memory.clear();
    _calendarMemory = null;
    try {
      for (final key in GStorage.localCache.keys.toList()) {
        if (key is String && key.startsWith('bangumi.')) {
          GStorage.localCache.delete(key);
        }
      }
    } catch (_) {}
  }
}

class _CacheEntry {
  const _CacheEntry({required this.items, required this.expireAt});

  final List<BangumiItem> items;
  final DateTime expireAt;
}

class _CalendarEntry {
  const _CalendarEntry({required this.days, required this.expireAt});

  final Map<int, List<BangumiItem>> days;
  final DateTime expireAt;
}
