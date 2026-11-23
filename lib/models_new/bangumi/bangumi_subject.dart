/// Bangumi（bgm.tv）接口原始实体。
///
/// 只描述 `GET /v0/subjects` 与 `GET /calendar` 用到的字段，
/// 其余字段由接口自由返回，这里不关心。
library;

class BangumiImages {
  const BangumiImages({
    this.large = '',
    this.common = '',
    this.medium = '',
    this.small = '',
    this.grid = '',
  });

  final String large;
  final String common;
  final String medium;
  final String small;
  final String grid;

  factory BangumiImages.fromJson(Map<String, dynamic> json) => BangumiImages(
    large: json['large'] as String? ?? '',
    common: json['common'] as String? ?? '',
    medium: json['medium'] as String? ?? '',
    small: json['small'] as String? ?? '',
    grid: json['grid'] as String? ?? '',
  );

  /// 列表封面统一取 `common`（r/400）：
  /// v0 与 p1 两条通路只有该档位行为一致，换通路时清晰度不会突变。
  String get cover => common.isNotEmpty ? common : large;
}

class BangumiRating {
  const BangumiRating({this.score = 0, this.rank = 0, this.total = 0});

  /// 无评分时接口返回 0，展示前需判断 `> 0`。
  final double score;
  final int rank;
  final int total;

  factory BangumiRating.fromJson(Map<String, dynamic> json) => BangumiRating(
    score: (json['score'] as num?)?.toDouble() ?? 0,
    rank: json['rank'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
  );
}

class BangumiTagVote {
  const BangumiTagVote({this.name = '', this.count = 0});

  final String name;
  final int count;

  factory BangumiTagVote.fromJson(Map<String, dynamic> json) => BangumiTagVote(
    name: json['name'] as String? ?? '',
    count: json['count'] as int? ?? 0,
  );
}

/// `GET /v0/subjects` 的 `data[]` 元素。
class BangumiSubject {
  const BangumiSubject({
    this.id = 0,
    this.name = '',
    this.nameCn = '',
    this.date = '',
    this.eps = 0,
    this.images = const BangumiImages(),
    this.rating = const BangumiRating(),
    this.tags = const [],
    this.metaTags = const [],
  });

  final int id;
  final String name;
  final String nameCn;
  final String date;
  final int eps;
  final BangumiImages images;
  final BangumiRating rating;
  final List<BangumiTagVote> tags;

  /// 服务端结构化摘要，存在重复元素（如 `["TV","TV","日本","日本"]`）。
  final List<String> metaTags;

  factory BangumiSubject.fromJson(Map<String, dynamic> json) => BangumiSubject(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    nameCn: json['name_cn'] as String? ?? '',
    date: json['date'] as String? ?? '',
    eps: json['eps'] as int? ?? 0,
    images: json['images'] is Map<String, dynamic>
        ? BangumiImages.fromJson(json['images'] as Map<String, dynamic>)
        : const BangumiImages(),
    rating: json['rating'] is Map<String, dynamic>
        ? BangumiRating.fromJson(json['rating'] as Map<String, dynamic>)
        : const BangumiRating(),
    tags:
        (json['tags'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(BangumiTagVote.fromJson)
            .toList() ??
        const [],
    metaTags:
        (json['meta_tags'] as List<dynamic>?)?.whereType<String>().toList() ??
        const [],
  );
}

/// `GET /v0/subjects` 的分页响应体。
class BangumiSubjectPage {
  const BangumiSubjectPage({
    this.total = 0,
    this.limit = 0,
    this.offset = 0,
    this.data = const [],
  });

  /// 总条数（不是总页数）。
  final int total;
  final int limit;
  final int offset;
  final List<BangumiSubject> data;

  factory BangumiSubjectPage.fromJson(Map<String, dynamic> json) =>
      BangumiSubjectPage(
        total: json['total'] as int? ?? 0,
        limit: json['limit'] as int? ?? 0,
        offset: json['offset'] as int? ?? 0,
        data:
            (json['data'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(BangumiSubject.fromJson)
                .toList() ??
            const [],
      );
}
