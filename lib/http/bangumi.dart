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
  static const _officialBaseUrl = 'https://api.bgm.tv';

  /// 社区反代（非官方，见 bgm.tv 官方论坛镜像/反代帖）。
  ///
  /// ⚠️ 旧的 `https://api.bangumi.lol` 已于 2026-09 停服（连根路径都 404），**勿再启用** ——
  /// 它曾导致"官方被墙 → 轮到死镜像 → DNS 也解析不出 → 整页报错"。
  ///
  /// 以下两个为 2026-09-26 实测可用，且返回字段与官方**逐字一致**
  /// （tags / meta_tags / eps / summary / date / rating 全在），
  /// 封面 URL 会被反代改写成自己的图片域名，但**路径结构不变**
  /// （`/r/200/pic/cover/...`），故 `bangumiCoverUrl` 的挡位改写照常适用。
  static const mirrorBaseUrls = <String>[
    'https://bgm.retr0.xyz/8d7db5cae', // 反代（带路径前缀），实测 ~3.7s
    'https://bgmapi.anibt.net', // 反代，实测 ~3.6s
  ];

  /// 单源最多尝试次数（首次 + 2 次重试）。
  /// 偶发 DNS/连接失败多为瞬时，退避后重试同一源往往就能过。
  static const _maxAttemptsPerSource = 3;
  static const _retryBackoff = <Duration>[
    Duration(milliseconds: 300),
    Duration(milliseconds: 800),
  ];

  static const _cacheVersion = 'v6';
  static const _userAgent =
      'PiliPlus/2.1 (https://github.com/bggRGjQaUbCoE/PiliPlus; bangumi)';

  /// 候选基地址（按顺序尝试）：设置里的自建反代优先，其次官方，最后社区反代
  static List<String> get _candidates {
    final custom = Pref.bangumiApiBaseUrl.trim();
    return <String>{
      if (custom.isNotEmpty) custom,
      _officialBaseUrl,
      ...mirrorBaseUrls,
    }.toList();
  }

  static Dio? _dio;

  static Dio get _client =>
      _dio ??= Dio(
          BaseOptions(
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
  ///
  /// [ignoreTtl] 为 true 时忽略时效直接返回（用于网络全挂时的兜底，
  /// 宁可显示旧数据也别把技术栈报错甩给用户）。
  static List<dynamic>? _readCache(
    String file,
    int year, {
    bool ignoreTtl = false,
  }) {
    try {
      final f = File(file);
      if (!f.existsSync()) return null;
      if (!ignoreTtl) {
        final age = DateTime.now().difference(f.lastModifiedSync());
        if (age > _cacheTtl(year)) return null;
      }
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

  /// 拉全某年某月条目（缓存优先；失败自动「同源重试 → 换源」三级兜底）
  ///
  /// 兜底链：同一源退避重试 2 次 → 换下一个候选源（官方 ⇄ 反代）
  /// → 全部失败时退回过期缓存 → 仍无缓存才抛 [BangumiNetworkException]。
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

    final candidates = _candidates;
    Object? lastError;
    for (final base in candidates) {
      for (var attempt = 0; attempt < _maxAttemptsPerSource; attempt++) {
        try {
          final rawList = await _fetchAllPages(
            base: base,
            mode: mode,
            year: year,
            month: month,
          );
          _writeCache(file, rawList);
          return _parse(rawList);
        } on DioException catch (e) {
          // 仅「重试/换源有意义」的错误才继续；业务类错误直接抛出
          if (!_isRetryable(e)) rethrow;
          lastError = e;
          if (attempt + 1 < _maxAttemptsPerSource) {
            await Future.delayed(_retryBackoff[attempt]);
          }
        }
      }
    }

    // 全线失败：退回过期缓存（stale-while-error），别把 DioException 原文甩给用户
    final stale = _readCache(file, year, ignoreTtl: true);
    if (stale != null) return _parse(stale);

    throw BangumiNetworkException(
      _describeNetworkFailure(lastError, candidates.length),
    );
  }

  /// 该错误是否值得重试 / 换源
  ///
  /// - 连接类（含 DNS 解析失败，dio 多归为 `connectionError` 或 `unknown`）⇒ 是
  /// - HTTP 5xx / 404 / 429 / 408 ⇒ 是（镜像、反代挂掉的典型响应）
  /// - 其余 4xx（参数错误等）⇒ 否，重试与换源都无意义
  static bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return code >= 500 || code == 404 || code == 408 || code == 429;
      case DioExceptionType.transformTimeout:
        return true;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
        return false;
    }
  }

  /// DNS 解析失败（`Failed host lookup` / errno 7）
  static bool _isDnsFailure(Object? e) {
    if (e is! DioException) return false;
    final err = e.error;
    if (err is! SocketException) return false;
    final text = '${err.osError?.message ?? ''} ${err.message}'.toLowerCase();
    return text.contains('host lookup') ||
        text.contains('no address associated');
  }

  /// 面向用户的失败文案（不暴露 DioException 技术栈）
  static String _describeNetworkFailure(Object? lastError, int sourceCount) {
    if (_isDnsFailure(lastError)) {
      return '域名解析失败（DNS），已尝试 $sourceCount 个接口源\n请检查网络 / DNS / 代理后重试';
    }
    return '网络请求失败，已尝试 $sourceCount 个接口源\n请检查网络后重试';
  }

  /// 用指定基地址分页拉全一个月（limit=100，offset 翻页）
  ///
  /// ⚠️ v0 的 `total` 是**总条数**（p1 的 total 是**总页数**，语义相反，用错会翻页死循环）。
  /// `limit` 上限就是 100，传 200 会 HTTP 400。
  static Future<List<dynamic>> _fetchAllPages({
    required String base,
    required BangumiBrowseMode mode,
    required int year,
    required int month,
  }) async {
    const pageSize = 100;
    const maxOffset = 500; // 安全上限（单月条目远小于此）
    final rawList = <dynamic>[];
    final seenIds = <int>{};
    var offset = 0;
    var received = 0;
    while (true) {
      final res = await _client.getUri<dynamic>(
        Uri.parse('$base/v0/subjects').replace(
          queryParameters: {
            // 注意：Uri.replace 的 queryParameters 值必须是 String/Iterable，
            // Dart 3.13 传 int 会抛 "int is not a subtype of Iterable"
            'type': '${mode.type}',
            'cat': '${mode.cat}',
            'year': '$year',
            'month': '$month',
            'limit': '$pageSize',
            'offset': '$offset',
          },
        ),
      );
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      if (data is! List) break;
      received += data.length;
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
      if (data.length < pageSize) break;
      final total = body is Map ? body['total'] : null;
      if (total is num && received >= total.toInt()) break;
      offset += pageSize;
      if (offset >= maxOffset) break;
    }
    return rawList;
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

/// Bangumi 接口**全部候选源**都不可达时抛出。
///
/// `toString()` 直接是面向用户的中文短句 —— 调用方 `Error(e.toString())`
/// 会原样渲染到页面，故这里不能带 DioException 技术栈。
class BangumiNetworkException implements Exception {
  const BangumiNetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}
