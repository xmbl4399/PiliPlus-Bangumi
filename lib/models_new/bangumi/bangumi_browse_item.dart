import 'package:PiliPlus/http/bangumi.dart';

/// tag 白名单（动画向 47 词，来自 Bangumi_Integration_Guide §3）
const List<String> kBangumiTagWhitelist = [
  '奇幻',
  '冒险',
  '战斗',
  '校园',
  '日常',
  '科幻',
  '恋爱',
  '喜剧',
  '热血',
  '悬疑',
  '推理',
  '机战',
  '运动',
  '音乐',
  '美食',
  '治愈',
  '恐怖',
  '历史',
  '偶像',
  '百合',
  '耽美',
  '竞技',
  '动作',
  '剧情',
  '搞笑',
  '催泪',
  '致郁',
  '魔法',
  '机甲',
  '战争',
  '体育',
  '侦探',
  '后宫',
  '穿越',
  '异世界',
  '职场',
  '青春',
  '家庭',
  '童话',
  '歌舞',
  '泡面番',
  '群像',
  '智斗',
  '犯罪',
  '末世',
  '科幻悬疑',
  '恋爱喜剧',
];

/// bgm.tv /v0/subjects 浏览模式（Bangumi_Integration_Guide §2.2/§4）
enum BangumiBrowseMode {
  tvAnime('TV', 2, 1, showTags: true, showEpisodes: true),
  webAnime('WEB', 2, 5, showTags: true),
  ovaAnime('OVA', 2, 2, showTags: true),
  animeMovie('剧场版', 2, 3, showTags: true),
  jpDrama('日剧', 6, 1),
  westernDrama('欧美剧', 6, 2),
  cnDrama('华语剧', 6, 3),
  kdrama('韩剧', 6, 6001, korean: true),
  movie('电影', 6, 6002);

  final String label;
  final int type;
  final int cat;

  /// 动画显示流派 tag（三次元 tags 命中率极低，不显示，P0-3）
  final bool showTags;

  /// 仅 TV 动画显示集数
  final bool showEpisodes;

  /// 韩剧：cat=6001 按 meta_tags 含「韩国」过滤（P0-5）
  final bool korean;

  const BangumiBrowseMode(
    this.label,
    this.type,
    this.cat, {
    this.showTags = false,
    this.showEpisodes = false,
    this.korean = false,
  });

  /// 缓存键带语义版本 v5（P1-3：排序/过滤语义变更必须升版本）
  String get cacheKeyPrefix => 'browse_${type}_$cat';

  Future<List<BangumiBrowseItem>> fetch({
    required int year,
    required int month,
    bool force = false,
  }) => BangumiHttp.fetchYearMonth(
    mode: this,
    year: year,
    month: month,
    force: force,
  );

  /// 同步读缓存（年份流式加载「先显缓存」步骤用）
  List<BangumiBrowseItem>? peekCache({required int year, required int month}) =>
      BangumiHttp.peekCache(this, year, month);
}

class BangumiBrowseItem {
  final int id;
  final String name;
  final String nameCn;
  final String? coverUrl;
  final String? airDate;
  final double? score;
  final String? summary;
  final List<String> tags;
  final List<String> metaTags;
  final int? totalEpisodes;

  const BangumiBrowseItem({
    required this.id,
    required this.name,
    required this.nameCn,
    this.coverUrl,
    this.airDate,
    this.score,
    this.summary,
    this.tags = const [],
    this.metaTags = const [],
    this.totalEpisodes,
  });

  factory BangumiBrowseItem.fromJson(
    Map<String, dynamic> json, {
    String imageQuality = 'medium',
  }) {
    double? score;
    final rating = json['rating'];
    if (rating is Map) {
      final raw = rating['score'];
      if (raw is num) {
        final v = raw.toDouble();
        // NaN/0 视为无评分
        score = v.isNaN || v <= 0 ? null : v;
      }
    }

    String? cover = _pickImage(json['images'], imageQuality);

    int? eps;
    if (json['eps'] is num) eps = (json['eps'] as num).toInt();

    final tags = <String>[];
    if (json['tags'] is List) {
      for (final t in json['tags'] as List) {
        if (t is Map) {
          final name = t['name'];
          if (name is String && kBangumiTagWhitelist.contains(name)) {
            tags.add(name);
            if (tags.length >= 2) break;
          }
        }
      }
    }

    final metaTags = <String>[];
    if (json['meta_tags'] is List) {
      for (final t in json['meta_tags'] as List) {
        if (t is String) metaTags.add(t);
      }
    }

    return BangumiBrowseItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] is String ? json['name'] : '',
      nameCn: json['name_cn'] is String ? json['name_cn'] : '',
      coverUrl: cover,
      airDate: json['date'] is String ? json['date'] : null,
      score: score,
      summary: json['summary'] is String ? json['summary'] : null,
      tags: tags,
      metaTags: metaTags,
      totalEpisodes: eps,
    );
  }

  /// 图片质量变体 fallback 链（P1-1：任一变体可能缺失）
  static String? _pickImage(dynamic images, String quality) {
    if (images is! Map) return null;
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = images[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    return switch (quality) {
      'small' => pick(['small', 'common', 'medium']),
      'large' => pick(['medium', 'large', 'common']),
      _ => pick(['common', 'medium', 'large']),
    };
  }

  /// 优先 name_cn，否则 name（P0-4：56% 日剧无 name_cn，必须容错）
  String get searchKeyword => nameCn.isNotEmpty ? nameCn : name;

  /// 标题截断（P3-1）：name 含 " - " 只显主标题；复制/搜索仍用 searchKeyword
  String get displayTitle {
    final source = nameCn.isNotEmpty ? nameCn : name;
    if (nameCn.isEmpty && source.contains(' - ')) {
      return source.substring(0, source.indexOf(' - '));
    }
    return source;
  }

  String? get episodeText =>
      totalEpisodes != null && totalEpisodes! > 0 ? '$totalEpisodes集' : null;
}
