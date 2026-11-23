import 'package:PiliPlus/models_new/bangumi/bangumi_calendar.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_subject.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';

/// Bangumi（bgm.tv）HTTP 客户端。
///
/// - 裸请求即可，不校验 UA、不需要鉴权；
/// - 官方源在国内可能被 DNS 污染，按「上次成功源 → 用户首选 → 官方 → 反代」兜底；
/// - 只对连接类错误 / 5xx / 404 / 408 / 429 重试换源，参数错误这类 4xx 直接抛出。
abstract final class BangumiHttp {
  /// Bangumi v0 API 官方根地址。
  static const String baseUrl = 'https://api.bgm.tv';

  /// 社区反代（非官方，官方被污染时备用）。
  static const List<String> mirrorBaseUrls = [
    'https://bgm.retr0.xyz/8d7db5cae',
    'https://bgmapi.anibt.net',
  ];

  /// 请求 UA（用于服务端侧识别，不影响鉴权）。
  static const String userAgent =
      'PiliPlus-HarmonyOS/0.1 (https://github.com/dev4harmony/PiliPlus)';

  /// 单页条数：v0 接口 limit 上限为 100，传 200 会 HTTP 400。
  static const int pageLimit = 100;

  /// 翻页偏移上限，避免异常数据导致无限翻页。
  static const int maxOffset = 500;

  static const int _maxAttemptsPerSource = 3;
  static const List<int> _retryableStatus = [404, 408, 429, 500, 502, 503, 504];
  static const List<int> _backoffMs = [300, 800];

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 25),
      headers: const {'user-agent': userAgent, 'accept': 'application/json'},
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );

  /// 上次成功的地址：官方挂掉时，同一月的后续翻页不必再从死源重试。
  static String? _lastGoodBaseUrl;

  static List<String> _candidates() {
    final preferred = Pref.bangumiApiBaseUrl.trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return <String>{
      ?_lastGoodBaseUrl,
      if (preferred.isNotEmpty) preferred,
      baseUrl,
      ...mirrorBaseUrls,
    }.toList();
  }

  static bool _retryable(Object error) {
    if (error is! DioException) return false;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        return code != null && _retryableStatus.contains(code);
      default:
        return false;
    }
  }

  static Future<T> _withFallback<T>(
    Future<T> Function(String base) request,
  ) async {
    Object? lastError;
    for (final base in _candidates()) {
      for (var attempt = 0; attempt < _maxAttemptsPerSource; attempt++) {
        try {
          final result = await request(base);
          _lastGoodBaseUrl = base;
          return result;
        } catch (error) {
          if (!_retryable(error)) rethrow;
          lastError = error;
          if (attempt + 1 < _maxAttemptsPerSource) {
            await Future<void>.delayed(
              Duration(milliseconds: _backoffMs[attempt]),
            );
          }
        }
      }
    }
    throw lastError ??
        DioException(
          requestOptions: RequestOptions(path: '/'),
          error: 'Bangumi 网络请求失败：没有可用的接口地址',
        );
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    throw const FormatException('Bangumi 响应不是 JSON 对象');
  }

  /// 按「年 + 月 + 分类」拉取一页条目。
  static Future<BangumiSubjectPage> getSubjects({
    required int type,
    required int cat,
    required int year,
    required int month,
    int limit = pageLimit,
    int offset = 0,
  }) => _withFallback((base) async {
    final res = await _dio.get<dynamic>(
      '$base/v0/subjects',
      queryParameters: {
        'type': type,
        'cat': cat,
        'year': year,
        'month': month,
        'limit': limit,
        'offset': offset,
      },
    );
    return BangumiSubjectPage.fromJson(_asMap(res.data));
  });

  /// 拉取全站周历（`GET /calendar`），返回接口原序（Mon → Sun）。
  static Future<List<BangumiCalendarDay>> getCalendar() =>
      _withFallback((base) async {
        final res = await _dio.get<dynamic>('$base/calendar');
        final data = res.data;
        if (data is! List) {
          throw const FormatException('Bangumi 周历响应不是数组');
        }
        return data
            .whereType<Map<String, dynamic>>()
            .map(BangumiCalendarDay.fromJson)
            .toList();
      });
}
