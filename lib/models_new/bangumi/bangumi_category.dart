import 'package:PiliPlus/models/common/enum_with_label.dart';

/// Bangumi 条目大类：动画。
const int bangumiTypeAnime = 2;

/// Bangumi 条目大类：三次元（剧集 / 电影）。
const int bangumiTypeReal = 6;

/// Bangumi 浏览分类（`type` + `cat` 组合）。
///
/// `type=6` 的 `cat` 划分没有公开文档，6001 / 6002 取自实际接口验证：
/// - [tvAnime] / [webAnime] / [ovaAnime] / [animeMovie]：动画的四个子分类；
/// - [koreanDrama]：`cat=6001`，再按 `meta_tags` 含「韩国」二次过滤。
enum BangumiCategory implements EnumWithLabel {
  tvAnime(bangumiTypeAnime, 1, 'TV'),
  webAnime(bangumiTypeAnime, 5, 'WEB'),
  ovaAnime(bangumiTypeAnime, 2, 'OVA'),
  animeMovie(bangumiTypeAnime, 3, '剧场版'),
  jpDrama(bangumiTypeReal, 1, '日剧'),
  westernDrama(bangumiTypeReal, 2, '欧美剧'),
  chineseDrama(bangumiTypeReal, 3, '华语剧'),
  koreanDrama(bangumiTypeReal, 6001, '韩剧', korean: true),
  movie(bangumiTypeReal, 6002, '电影');

  const BangumiCategory(this.type, this.cat, this.label, {this.korean = false});

  final int type;
  final int cat;

  @override
  final String label;

  /// 是否需要按 `meta_tags` 含「韩国」二次过滤。
  final bool korean;

  /// 番剧页（一级 Tab「番剧」）下的分类。
  static const List<BangumiCategory> animeTabs = [
    BangumiCategory.tvAnime,
    BangumiCategory.webAnime,
    BangumiCategory.ovaAnime,
    BangumiCategory.animeMovie,
  ];

  /// 影视页（一级 Tab「影视」）下的分类。
  static const List<BangumiCategory> realTabs = [
    BangumiCategory.jpDrama,
    BangumiCategory.westernDrama,
    BangumiCategory.chineseDrama,
    BangumiCategory.koreanDrama,
    BangumiCategory.movie,
  ];
}

/// 星期枚举，`id` 与接口 `weekday.id` 一致（1 = 周一 … 7 = 周日）。
enum BangumiWeekday {
  monday(1, '星期一', '周一'),
  tuesday(2, '星期二', '周二'),
  wednesday(3, '星期三', '周三'),
  thursday(4, '星期四', '周四'),
  friday(5, '星期五', '周五'),
  saturday(6, '星期六', '周六'),
  sunday(7, '星期日', '周日');

  const BangumiWeekday(this.id, this.cn, this.shortCn);

  final int id;
  final String cn;
  final String shortCn;

  static BangumiWeekday fromId(int id) => BangumiWeekday.values.firstWhere(
    (e) => e.id == id,
    orElse: () => BangumiWeekday.monday,
  );

  /// 今天对应的星期（Dart 的 `weekday` 为 1=周一…7=周日，与 [id] 对齐）。
  static BangumiWeekday get today => fromId(DateTime.now().weekday);

  /// 按「今天 → 向前回溯」排序 7 天，首元素恒为 [today]。
  ///
  /// 用循环减法而不是简单倒序：今天为周一时，正确结果是
  /// 周一、周日、周六……而不是把周日排到最后。
  static List<BangumiWeekday> orderFrom(BangumiWeekday today) => [
    for (var offset = 0; offset < 7; offset++)
      fromId(((today.id - 1 - offset) % 7 + 7) % 7 + 1),
  ];
}

/// 接口根地址选项（设置页「BGM 接口源」）。
///
/// 官方 `api.bgm.tv` 在国内偶发 DNS 污染，社区反代可作首选；
/// 这里只决定**首选**，实际请求仍会自动在官方 / 反代之间兜底换源。
enum BangumiApiSource implements EnumWithLabel {
  official('', '官方优先'),
  retr0('https://bgm.retr0.xyz/8d7db5cae', '社区反代 retr0'),
  anibt('https://bgmapi.anibt.net', '社区反代 anibt');

  const BangumiApiSource(this.baseUrl, this.label);

  final String baseUrl;

  @override
  final String label;

  static BangumiApiSource fromBaseUrl(String baseUrl) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return BangumiApiSource.values.firstWhere(
      (e) => e.baseUrl == normalized,
      orElse: () => BangumiApiSource.official,
    );
  }
}
