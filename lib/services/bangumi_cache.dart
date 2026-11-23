import 'package:PiliPlus/models_new/bangumi/bangumi_item.dart';
import 'package:PiliPlus/utils/storage.dart';

/// Bangumi 月列表缓存。
///
/// 键为「大类 + 子分类 + 年 + 月」；当季 / 未来月份 6 小时，历史月份 30 天。
/// 「隐藏无评分」「韩剧过滤」不参与缓存键，过滤在调用方做。
///
/// 内存命中最快；未命中时回落到 Hive（`GStorage.localCache`），
/// 因此冷启动也能秒开已看过的月份。
abstract final class BangumiCache {
  static final Map<String, _CacheEntry> _memory = {};

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
        expireAt: DateTime.now().add(ttl(year: year, month: month)),
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
    final expireAt = DateTime.now().add(ttl(year: year, month: month));
    _memory[key] = _CacheEntry(items: items, expireAt: expireAt);
    _writeDisk(key, items, expireAt);
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
