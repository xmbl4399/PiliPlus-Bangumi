import 'package:PiliPlus/http/bangumi.dart';

/// # tag 双层词表（Tier1 题材 / Tier2 来源·受众）
///
/// 依据可移植设计文档《二级白名单设计方案》（bili-bgm-overlay 项目
/// `docs/tier-whitelist-design.md`，未随本仓库分发）：
/// bgm.tv 列表接口的 tag 是一个**受控小词表**（四年 937 条去重后仅 53 词），
/// 所以不是"从无限词汇里挑"，而是从这个表里做取舍。
///
/// 旧版是凭直觉写的 47 词单层白名单，问题有两个：
/// 1. 词表里 32 个词属"零边际贡献"（从不单独决定某条有没有 tag），占着位置；
/// 2. 单层无法表达"题材优先、来源/受众补位"，卡片槽位利用率低。
///
/// 分层后层号即显示优先级：
/// - **Tier1 题材** 首选显示；
/// - **Tier2 来源·受众** 只在 Tier1 没词时兜底，或 Tier1 只有 1 个词时补满槽位。
///
/// 词表来源：列表接口 `meta_tags` + `tags` 字段实测词频（无需逐条拉详情）。
///
/// 覆盖率实测（2023–2026 各 4 个月，共 **1119** 条动画）：
///
/// | 口径 | 覆盖率 |
/// |---|---|
/// | 旧 47 词单层 | 88.0% |
/// | 仅 Tier1 | 83.7% |
/// | **Tier1 + Tier2** | **90.9%** |
/// | Tier1 + Tier2 + Tier3（平台/地区） | 99.6% |
///
/// 本实现**只做到 Tier1+Tier2 ≈ 90%**，不设 Tier3：补上 Tier3 虽然能到 99.6%，
/// 但代价是卡片上会出现「TV／日本」这种零信息量的标签。剩下约 9% 拿不到词的条目，
/// 其 tag 本身就只给了平台+地区（如 `TV/日本`、`TV/欧美`），属预期内空白。
const Set<String> kBangumiTagTier1 = {
  // Tier1 题材（27）
  '奇幻', '战斗', '恋爱', '日常', '校园', '科幻', '喜剧', '玄幻', '冒险', '悬疑', '百合',
  '穿越', '运动', '音乐', '历史', '剧情', '后宫', '武侠', '推理', '职场', '机战', '美食',
  '萌系', 'BL', '恐怖', '惊悚', '耽美',
};

/// Tier2 来源 + 受众（12）——Tier1 无词时兜底，或补满槽位
const Set<String> kBangumiTagTier2 = {
  '漫画改', '原创', '小说改', '游戏改', '少年向', '青年向', '子供向', '女性向', '少女向',
  '同人', '影视改', '乙女',
};

/// 双层分级挑词：题材永远排在前面，来源/受众用于补满槽位。
///
/// 注意**不要**写成"只取最高层命中的那一层"——那样 `[奇幻, 漫画改]` 只剩 1 个词，
/// 白白浪费槽位；正确做法是两层拼接后截断。
///
/// ```dart
/// pickBangumiTags(['TV', '日本', '小说改']) // => ['小说改']  Tier1 无词 → Tier2 兜底
/// pickBangumiTags(['奇幻', '漫画改'])        // => ['奇幻', '漫画改']  题材在前 + 补满
/// pickBangumiTags(['TV', '日本'])            // => []  无 Tier3，预期内空白
/// ```
List<String> pickBangumiTags(Iterable<String> names, {int max = 2}) {
  final seen = <String>{};
  final tier1 = <String>[];
  final tier2 = <String>[];
  for (final name in names) {
    if (!seen.add(name)) continue; // 去重，保留首次出现顺序
    if (kBangumiTagTier1.contains(name)) {
      tier1.add(name);
    } else if (kBangumiTagTier2.contains(name)) {
      tier2.add(name);
    }
  }
  return [...tier1, ...tier2].take(max).toList(growable: false);
}

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

    final metaTags = <String>[];
    if (json['meta_tags'] is List) {
      for (final t in json['meta_tags'] as List) {
        if (t is String) metaTags.add(t);
      }
    }

    // 双层挑词：候选 = meta_tags（平台人工摘要，受控词表，置前）
    //            + tags（全量投票词，按票数降序，作补充）
    // 两个字段都随列表接口一起返回，**无需额外请求详情**（P1-2）
    final voted = <String>[];
    if (json['tags'] is List) {
      for (final t in json['tags'] as List) {
        if (t is Map) {
          final name = t['name'];
          if (name is String) voted.add(name);
        }
      }
    }
    final tags = pickBangumiTags([...metaTags, ...voted]);

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
