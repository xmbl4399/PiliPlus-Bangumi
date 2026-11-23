import 'package:PiliPlus/models_new/bangumi/bangumi_subject.dart';

/// Bangumi tag 双层白名单与挑选逻辑。
///
/// 不能按票数取 Top N：票数最高的是「2026年1月」「TV」「日本」这类元信息，
/// 题材词票数天然偏低。因此先按品类筛，再在同品类内按票数排。
abstract final class BangumiTag {
  /// 卡片上最多展示的 tag 数量。
  static const int maxTagCount = 2;

  /// Tier1 · 题材词。
  static const Set<String> tier1 = {
    '奇幻',
    '战斗',
    '恋爱',
    '日常',
    '校园',
    '科幻',
    '喜剧',
    '玄幻',
    '冒险',
    '悬疑',
    '百合',
    '穿越',
    '运动',
    '音乐',
    '历史',
    '剧情',
    '后宫',
    '武侠',
    '推理',
    '职场',
    '机战',
    '美食',
    '萌系',
    'BL',
    '恐怖',
    '惊悚',
    '耽美',
  };

  /// Tier2 · 来源 / 受众词。
  static const Set<String> tier2 = {
    '漫画改',
    '原创',
    '小说改',
    '游戏改',
    '少年向',
    '青年向',
    '子供向',
    '女性向',
    '少女向',
    '同人',
    '影视改',
    '乙女',
  };

  /// 构造候选词池：投票词（票数降序）在前，`meta_tags` 在后。
  static List<String> buildPool(BangumiSubject subject) {
    final voted = subject.tags.where((e) => e.name.trim().isNotEmpty).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final meta = subject.metaTags.where((e) => e.trim().isNotEmpty);
    return <String>{for (final tag in voted) tag.name, ...meta}.toList();
  }

  /// 从候选词池中分级挑选，题材优先、来源/受众补位。
  static List<String> pick(List<String> pool) {
    final first = pool.where(tier1.contains);
    final second = pool.where(tier2.contains);
    return [...first, ...second].take(maxTagCount).toList();
  }
}
