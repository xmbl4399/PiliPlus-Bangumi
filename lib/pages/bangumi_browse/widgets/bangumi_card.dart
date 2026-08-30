import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_browse_item.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// bgm.tv 条目卡片（Bangumi_Integration_Guide §5.2）
/// - 评分徽章：右上角，score>=7 金色高亮，否则半透明；无评分隐藏
/// - 流派 tag：左上角最多 2 个（仅动画）
/// - 集数：左下角（仅 TV 动画）
/// - 点击 → B 站搜索 searchKeyword；长按 → 复制 searchKeyword
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
                                  padding: const EdgeInsets.only(bottom: 3),
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
                padding: const EdgeInsets.fromLTRB(4, 5, 2, 3),
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: const BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        score.toStringAsFixed(1),
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          color: highlight ? const Color(0xFFFFD54F) : Colors.white70,
          fontWeight: highlight ? FontWeight.bold : null,
        ),
      ),
    );
  }

  Widget _miniBadge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: const BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.all(Radius.circular(3)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        height: 1.2,
        color: Colors.white70,
      ),
    ),
  );

  void _copyKeyword() {
    Clipboard.setData(ClipboardData(text: item.searchKeyword));
    SmartDialog.showToast('已复制「${item.searchKeyword}」');
  }
}
