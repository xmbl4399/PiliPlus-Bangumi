import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/bangumi/bangumi_browse_item.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

/// bgm.tv 数据层（Bangumi_Integration_Guide §2）
///
/// - 独立 Dio 实例（§2.8）：不带 B 站 UA/Referer/cookie 拦截器，与 B 站风控隔离
/// - 分页拉全（§2.4）：limit=100 一次拉全，offset 翻页，安全上限 500
/// - 不带 sort=rank（P0-1 服务端截断丢数据），本地按 score 降序（P0-2 browse 无 rank）
/// - 文件缓存（§2.5）：browse_{type}_{cat}_{year}_{month}_v5.json，
///   当年 12h / 历史年份 30d；存过滤后的原始 JSON
abstract final class BangumiHttp {
  static const _baseUrl = 'https://api.bgm.tv';
  static const _cacheVersion = 'v6';
  static const _userAgent =
      'PiliPlus/2.1 (https://github.com/bggRGjQaUbCoE/PiliPlus; bangumi)';

  static Dio? _dio;

  static Dio get _client =>
      _dio ??= Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 60),
            headers: {'user-agent': _userAgent},
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
        )
        ..transformer = BackgroundTransformer();

  static String get _cacheDir {
    final dir = Directory(path.join(appSupportDirPath, 'bangumi_cache'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static String _cacheFile(
    BangumiBrowseMode mode,
    int year,
    int month,
  ) => path.join(
    _cacheDir,
    '${mode.cacheKeyPrefix}_${year}_${month}_$_cacheVersion.json',
  );

  /// 缓存时效：当年 12h / 历史年份 30d（历史数据固定）
  static Duration _cacheTtl(int year) =>
      year == DateTime.now().year
      ? const Duration(hours: 12)
      : const Duration(days: 30);

  /// 读缓存，返回原始条目 JSON 列表；过期/缺失返回 null
  static List<dynamic>? _readCache(String file, int year) {
    try {
      final f = File(file);
      if (!f.existsSync()) return null;
      final age = DateTime.now().difference(f.lastModifiedSync());
      if (age > _cacheTtl(year)) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is List) return raw;
    } catch (_) {}
    return null;
  }

  static void _writeCache(String file, List<dynamic> rawList) {
    try {
      File(file).writeAsStringSync(jsonEncode(rawList), flush: true);
    } catch (_) {}
  }

  /// 遍历删 browse_* 前缀缓存文件（排序/过滤/开关变更时调用）
  static void clearAllBrowseCache() {
    try {
      final dir = Directory(_cacheDir);
      if (!dir.existsSync()) return;
      for (final e in dir.listSync()) {
        if (e is File && path.basename(e.path).startsWith('browse_')) {
          e.deleteSync();
        }
      }
    } catch (_) {}
  }

  static int _compare(BangumiBrowseItem a, BangumiBrowseItem b) {
    final sa = a.score ?? -1.0;
    final sb = b.score ?? -1.0;
    if (sa != sb) return sb.compareTo(sa); // 评分降序，无评分垫底
    return (a.airDate ?? '').compareTo(b.airDate ?? ''); // 同分按日期
  }

  /// 原始 JSON 的评分有效性（与解析逻辑一致：NaN/<=0 视为无评分）
  static bool _rawHasScore(Map e) {
    final rating = e['rating'];
    if (rating is! Map) return false;
    final raw = rating['score'];
    if (raw is! num) return false;
    final v = raw.toDouble();
    return !v.isNaN && v > 0;
  }

  /// 同步读缓存并解析（用于年份流式加载的「先显缓存」步骤）
  static List<BangumiBrowseItem>? peekCache(
    BangumiBrowseMode mode,
    int year,
    int month,
  ) {
    final cached = _readCache(_cacheFile(mode, year, month), year);
    if (cached == null) return null;
    try {
      return _parse(cached);
    } catch (_) {
      return null;
    }
  }

  /// 拉全某年某月条目（缓存优先）
  static Future<List<BangumiBrowseItem>> fetchYearMonth({
    required BangumiBrowseMode mode,
    required int year,
    required int month,
    bool force = false,
  }) async {
    final file = _cacheFile(mode, year, month);
    final cached = _readCache(file, year);
    if (!force && cached != null) {
      return _parse(cached);
    }

    final rawList = <dynamic>[];
    final seenIds = <int>{};
    var offset = 0;
    while (true) {
      final res = await _client.get<dynamic>(
        '/v0/subjects',
        queryParameters: {
          'type': mode.type,
          'cat': mode.cat,
          'year': year,
          'month': month,
          'limit': 100,
          'offset': offset,
        },
      );
      final data = res.data is Map ? res.data['data'] : null;
      if (data is! List) break;
      for (final e in data) {
        if (e is! Map) continue;
        // 韩剧：cat=6001 按 meta_tags 含「韩国」过滤（写缓存前过滤，P0-5）
        if (mode.korean) {
          final metas = e['meta_tags'];
          if (metas is! List || !metas.contains('韩国')) continue;
        }
        // 隐藏无评分条目（§2.7）：开关开启时写缓存前就过滤，缓存只存有评分
        if (Pref.hideNoScoreMedia && !_rawHasScore(e)) continue;
        final id = (e['id'] as num?)?.toInt();
        if (id == null || !seenIds.add(id)) continue;
        rawList.add(e);
      }
      if (data.length < 100) break;
      offset += 100;
      if (offset > 500) break; // 安全上限
    }

    _writeCache(file, rawList);
    return _parse(rawList);
  }

  static List<BangumiBrowseItem> _parse(List<dynamic> rawList) {
    final items = rawList
        .whereType<Map>()
        .map((e) => BangumiBrowseItem.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort(_compare);
    return items;
  }
}
