import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_item.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Bangumi 条目卡片（竖版）。
///
/// 点击后跳 B 站搜索结果：bgm 条目本身不可播放，与 newBV 行为一致。
class BangumiCardV extends StatelessWidget {
  const BangumiCardV({
    super.key,
    required this.item,
    this.showTags = true,
    this.showEpisodes = true,
    this.coverTags = false,
  });

  final BangumiItem item;
  final bool showTags;
  final bool showEpisodes;

  /// 是否把白名单筛出的题材 tag 贴到封面左上角（TV 番剧用）。
  final bool coverTags;

  void _onTap() {
    if (item.title.isEmpty) return;
    Get.toNamed('/searchResult', parameters: {'keyword': item.title});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: Style.mdRadius),
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: _onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: Style.aspectRatio3x4,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkImgLayer(
                      src: item.cover,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      borderRadius: BorderRadius.zero,
                    ),
                    if (item.hasScore)
                      PBadge(
                        text: item.scoreText,
                        top: 6,
                        right: 6,
                        bottom: null,
                        left: null,
                      ),
                    if (coverTags && item.tags.isNotEmpty)
                      Positioned(
                        left: 6,
                        top: 6,
                        right: 44,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final tag in item.tags) _CoverTag(tag),
                          ],
                        ),
                      ),
                    if (showEpisodes && item.eps != null)
                      PBadge(
                        text: '${item.eps}话',
                        top: null,
                        right: null,
                        bottom: 6,
                        left: 6,
                        type: PBadgeType.gray,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.2),
                  ),
                  if (showTags && !coverTags && item.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        item.tags.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面左上角的题材 tag 徽章（白名单筛出的 ≤2 个词）。
class _CoverTag extends StatelessWidget {
  const _CoverTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
