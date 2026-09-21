import 'package:PiliPlus/http/bangumi.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// # tag 双层词表（Tier1 题材 / Tier2 来源·受众）
///
/// 依据两份可移植文档（bili-bgm-overlay 项目，未随本仓库分发）：
/// - `docs/bangumi-v0-api-guide.md` —— v0 列表接口取 tag 的完整方案（**怎么用**）
/// - `docs/tier-whitelist-design.md` —— 二级白名单设计（**词表怎么来的**）
///
/// **前提事实**：`api.bgm.tv/v0/subjects` 的列表项**同时**返回
/// `tags`（用户投票全量词，≤30，按票数降序）与 `meta_tags`（服务端结构化摘要）。
/// 所以"列表没有内容词、必须逐条拉详情"只对 `next.bgm.tv/p1/subjects` 成立；
/// **v0 通路上零额外请求就拿到全部 tag**，详情补拉是纯浪费
/// （实测详情 `tags` 与列表 `tags` 逐字节一致，且一个空卡都救不了）。
///
/// bgm.tv 的 tag 是**受控小词表**（四年 937 条去重后仅 53 词），所以白名单是从这张
/// 小表里做取舍 —— 但**不要凭直觉写词**：旧版就是凭直觉写的 47 词单层表单，
/// 其中 32 个词属"零边际贡献"（从不单独决定某条有没有 tag），纯占位置。
///
/// 分层后层号即显示优先级：
/// - **Tier1 题材** 首选显示；
/// - **Tier2 来源·受众** 只在 Tier1 没词时兜底，或 Tier1 只有 1 个词时补满槽位。
///
/// 覆盖率实测（口径 `tags ∪ meta_tags`；2023–2026 共 **2091** 条，四分类全覆盖）：
///
/// | 类型 | 条数 | 旧 47 词单层 | 仅 Tier1 | **Tier1 + Tier2** | + Tier3 |
/// |---|---|---|---|---|---|
/// | TV | 1150 | 87.1% | 83.0% | **90.4%** | 99.6% |
/// | WEB | 657 | 68.0% | 67.3% | **81.4%** | 97.9% |
/// | 剧场版 | 268 | 63.8% | 62.3% | **74.6%** | 98.9% |
/// | OVA | 16 | 87.5% | 87.5% | **100%** | 100% |
/// | **合计** | **2091** | 78.1% | 75.4% | **85.7%** | 98.9% |
///
/// 结论：**TV 类（主 tab）90.4%**，**全四类合计 85.7%**。
/// 注意别把 TV 单类的数字当成全局 —— 早期只测 TV 时算出的"99.6%"不能推广到四类。
/// 四类之间的差距来自**数据本身**而非词表：WEB/剧场版里大量欧美网络动画、短片在
/// bgm.tv 上没人投中文 tag，加词救不回来 —— 实测空卡里"池里有白名单外词"的只有个位数，
/// 且全是人名（`Albert.Birney` / `三浦莉希` / `山下清悟`）。
///
/// **不设 Tier3**（平台/地区）：加上它能到 98.9%，但填进去的是「WEB／剧场版／中国／日本」，
/// 比空着更没信息量。两份文档对此结论一致：宁可留空，Tier3 默认关。
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

/// # 封面挡位（bgm.tv 图片 CDN）
///
/// bgm 封面 URL 的宽度**直接写在路径里**，CDN 按需缩放：
///
/// ```
/// https://lain.bgm.tv/r/400/pic/cover/l/89/d9/484686_m5DT9.jpg
///                   ^^^^^^^
/// ```
///
/// 所以任意宽度都能靠改写这一段得到，**不必受接口给的 5 个预设键限制**。
/// 接口 `images` 只提供：`grid`=100 / `small`=200 / `common`=400 /
/// `medium`=800 / `large`=原图（无 `/r/N/` 段）。
/// 实测 CDN 认任意宽度（r100/r200/r400/r600/r800 逐一拉过，像素与文件名大小均符合预期）。
///
/// (宽度, 名称)；宽度 **0 = 原图**（去掉 `/r/N/` 段）
///
/// 括号内文件大小来自实测：`lain.bgm.tv` 上一张 640×905 的竖版海报，
/// 具体数值随原图大小浮动，仅供参考。
const List<(int, String)> kBangumiCoverQualities = [
  (100, '最低 r100（约 5 KB/张 · 1× 屏够用）'),
  (200, '低 r200（约 17 KB/张 · 2× 屏偏紧）'),
  (400, '标准 r400（约 55 KB/张 · 3× 屏清晰）'),
  (600, '高 r600（约 106 KB/张）'),
  (800, '很高 r800（约 113 KB/张）'),
  (0, '原图（约 130 KB/张 · 慎选）'),
];

/// 封面挡位默认值 **200**（省流量优先）
const int kBangumiCoverQualityDefault = 200;

/// 把 bgm 封面 URL 改写成指定宽度挡位（渲染时调用，所以改设置即时生效）。
///
/// - `width <= 0` → 原图：去掉 `/r/N/` 段
/// - URL 本来没有 `/r/N/` 段（即原图）→ 在域名后插入该段
/// - 既不改文件名也不改子路径，`pic/cover/l/…` 部分原样保留
String bangumiCoverUrl(String url, int width) {
  if (width <= 0) {
    // 用它换成 '/' 而不是删空：`/r/N/` 两端的斜杠都是分隔符，
    // 删空会让域名与 `pic` 粘成 `lain.bgm.tvpic`
    return url.replaceFirst(_reCoverWidth, '/');
  }
  if (_reCoverWidth.hasMatch(url)) {
    return url.replaceFirst(_reCoverWidth, '/r/$width/');
  }
  // 原图 URL 无 `/r/N/` 段：插到域名之后（用匹配位置，别手算下标，容易多一个斜杠）
  final host = _reHost.firstMatch(url);
  return host == null ? url : url.replaceRange(host.end, host.end, '/r/$width');
}

final RegExp _reCoverWidth = RegExp(r'/r/\d+/');
final RegExp _reHost = RegExp(r'^[a-z]+://[^/]+');

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

  /// 原图 URL（bgm CDN 上不带 `/r/N/` 挡位段的那个）；渲染请用 [coverUrl]
  final String? coverRaw;

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
    this.coverRaw,
    this.airDate,
    this.score,
    this.summary,
    this.tags = const [],
    this.metaTags = const [],
    this.totalEpisodes,
  });

  /// 按「设置 → 封面画质」输出的封面 URL。
  ///
  /// 挡位在**渲染时**才拼进 URL，所以改设置不必清缓存、不必重拉网络，回页面即生效。
  String? get coverUrl => coverRaw == null
      ? null
      : bangumiCoverUrl(coverRaw!, Pref.bangumiCoverQuality);

  factory BangumiBrowseItem.fromJson(Map<String, dynamic> json) {
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

    final String? cover = _pickImage(json['images']);

    int? eps;
    if (json['eps'] is num) eps = (json['eps'] as num).toInt();

    // ⚠️ meta_tags 服务端会带重复（实测 60 条里 21 条中招，如
    // ["TV","TV","日本","日本","奇幻","奇幻"]，倍数 2~6 不定且不保证相邻成对）
    // ⇒ 解析时就去重，下游才不用再防
    final metaTags = <String>[];
    if (json['meta_tags'] is List) {
      for (final t in json['meta_tags'] as List) {
        if (t is String && !metaTags.contains(t)) metaTags.add(t);
      }
    }

    // 候选词池 = tags（用户投票全量词）+ meta_tags（服务端结构化摘要），**取并集**
    //
    // - tags 显式按 count 降序，不赌接口已排好序（顺序即"票数高者优先"的依据）
    // - 为什么要并集：meta_tags 是服务端为塞平台/地区/来源而精挑的摘要，会把题材词挤掉。
    //   实例 [276787] 梅比乌斯之尘：meta_tags 只有「TV 日本 原创」，
    //   题材词 科幻(54票)/战斗(29票) 全在 tags 里 —— 只吃 meta_tags 就全丢了
    // - 反过来 meta_tags 里也有票数不高的词（服务端认定重要），所以两边都要
    // - 两个字段都随 v0 列表接口 `/v0/subjects` 一次返回 ⇒ **零额外请求**，
    //   也**不需要详情补拉**（实测详情 tags 与列表 tags 逐字节一致，一个空卡都救不了）
    final voted = <Map>[];
    if (json['tags'] is List) {
      for (final t in json['tags'] as List) {
        if (t is Map && t['name'] is String) voted.add(t);
      }
    }
    voted.sort((a, b) => _voteCount(b).compareTo(_voteCount(a)));

    final tags = pickBangumiTags([
      for (final t in voted) t['name'] as String,
      ...metaTags,
    ]);

    return BangumiBrowseItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] is String ? json['name'] : '',
      nameCn: json['name_cn'] is String ? json['name_cn'] : '',
      coverRaw: cover,
      airDate: json['date'] is String ? json['date'] : null,
      score: score,
      summary: json['summary'] is String ? json['summary'] : null,
      tags: tags,
      metaTags: metaTags,
      totalEpisodes: eps,
    );
  }

  /// tags[].count 票数（缺失/非数值按 0 处理）
  static int _voteCount(Map t) {
    final c = t['count'];
    return c is num ? c.toInt() : 0;
  }

  /// 取**源图** URL：优先原图 `large`，逐级降级（P1-1：任一变体可能缺失）
  ///
  /// 这里只挑"源"，不定挡位 —— 挡位由 [coverUrl] 在渲染时按设置改写（见 [bangumiCoverUrl]）。
  /// 取 large 作源的好处：它与 small/grid/common/medium 只是同一路径多一个 `/r/N/` 段，
  /// 所以任意挡位都能从中得到，不会因为选了某个预设键就丢掉更清晰的源。
  static String? _pickImage(dynamic images) {
    if (images is! Map) return null;
    for (final k in const ['large', 'medium', 'common', 'small', 'grid']) {
      final v = images[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
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
