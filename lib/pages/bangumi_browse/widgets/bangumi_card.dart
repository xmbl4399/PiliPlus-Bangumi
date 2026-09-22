import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_browse_item.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 徽章底色：黑 70%（原来只有 54%，压在亮封面上会糊）
const _kBadgeBg = Color(0xB3000000);

/// 徽章描边：白 24% 发丝线 —— 封面偏暗时靠它把徽章边缘勾出来
const _kBadgeBorder = Border.fromBorderSide(
  BorderSide(color: Color(0x3DFFFFFF), width: 0.5),
);

/// bgm.tv 条目卡片（Bangumi_Integration_Guide §5.2）
/// - 评分徽章：右上角，score>=7 金色高亮；无评分隐藏
/// - 流派 tag：左上角最多 2 个（仅动画）
/// - 集数：左下角（仅 TV 动画）
/// - 点击 → B 站搜索 searchKeyword；长按 → 复制 searchKeyword
///
/// 徽章可读性：封面色彩不可控（有亮有暗），所以统一用「黑底 0.7 + 白色细描边」，
/// 文字一律纯白加粗（评分 >=7 用金色），字号 11.5/12.5。
class BangumiCard extends StatelessWidget {
  const BangumiCard({super.key, required this.item, required this.mode});

  final BangumiBrowseItem item;
  final BangumiBrowseMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: Style.mdRadius),
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () => Get.toNamed(
          '/searchResult',
          parameters: {'keyword': item.searchKeyword},
        ),
        onLongPress: _copyKeyword,
        onSecondaryTap: PlatformUtils.isMobile ? null : _copyKeyword,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.75,
              child: LayoutBuilder(
                builder: (context, boxConstraints) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      NetworkImgLayer(
                        src: item.coverUrl,
                        width: boxConstraints.maxWidth,
                        height: boxConstraints.maxHeight,
                        // bgm.tv 封面不支持 B 站 @1q.webp 后缀，跳过处理
                        skipThumbnail: true,
                      ),
                      if (item.score != null)
                        Positioned(top: 6, right: 6, child: _scoreBadge()),
                      if (mode.showTags && item.tags.isNotEmpty)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final tag in item.tags.take(2))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: _miniBadge(tag),
                                ),
                            ],
                          ),
                        ),
                      if (mode.showEpisodes && item.episodeText != null)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: _miniBadge(item.episodeText!),
                        ),
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: Padding(
                // 上下对称 4，配合 grid 的 mainAxisExtent 38（4 + 2×15 + 4）
                padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
                child: Text(
                  item.displayTitle,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: theme.textTheme.bodySmall!.fontSize,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 评分徽章：>=7 金色高亮
  Widget _scoreBadge() {
    final score = item.score!;
    final highlight = score >= 7;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const BoxDecoration(
        color: _kBadgeBg,
        border: _kBadgeBorder,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(
        score.toStringAsFixed(1),
        style: TextStyle(
          fontSize: 12.5,
          height: 1.2,
          color: highlight ? const Color(0xFFFFD54F) : Colors.white,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _miniBadge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    decoration: const BoxDecoration(
      color: _kBadgeBg,
      border: _kBadgeBorder,
      borderRadius: BorderRadius.all(Radius.circular(5)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        height: 1.2,
        color: Colors.white,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
  );

  void _copyKeyword() {
    Clipboard.setData(ClipboardData(text: item.searchKeyword));
    SmartDialog.showToast('已复制「${item.searchKeyword}」');
  }
}
