import 'package:PiliPlus/common/skeleton/skeleton.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:material_ui/material_ui.dart';

/// 占位块颜色
///
/// **不要用项目其他骨架屏惯用的 `onInverseSurface`**：那张卡片的底色是
/// surfaceContainer 系，720p 模拟器实测「卡片底 = rgb(243,244,239)」而
/// `onInverseSurface` = rgb(240,241,236) —— 只差 3 个色阶，封面勉强能看出、
/// 10dp 高的标题条基本看不见（第一版就是栽在这里）。
///
/// 改用 `onSurface` 的低透明度叠加：浅色主题下压暗、深色主题下提亮，
/// 与卡片底色稳定拉开约 20 个色阶，不用为两套主题各写一个硬编码灰。
Color _blockColor(BuildContext context) =>
    ColorScheme.of(context).onSurface.withValues(alpha: 0.1);

/// 番剧/影视卡片骨架屏（首屏加载占位）
///
/// 尺寸与真卡片 BangumiCard 完全对齐：Card(mdRadius) + 0.75 封面比例 +
/// grid 的 mainAxisExtent(38) 标题区（上下内边距 4 + 2 行文字）。
/// 因此骨架和真卡片占同一个格子，数据到达后原地替换不会跳版。
class BangumiCardSkeleton extends StatelessWidget {
  const BangumiCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = _blockColor(context);
    return Skeleton(
      child: Card(
        shape: const RoundedRectangleBorder(borderRadius: Style.mdRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.75,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    top: Style.imgRadius,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 10, width: double.infinity, color: color),
                    const SizedBox(height: 5),
                    Container(height: 10, width: 46, color: color),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 月份标题占位（真标题为 `{m}月 · N 部`）
///
/// 位置/内边距与页面的 _monthHeader 一致，保证骨架与真数据的首行基线相同。
class BangumiMonthHeaderSkeleton extends StatelessWidget {
  const BangumiMonthHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            height: 14,
            width: 88,
            color: _blockColor(context),
          ),
        ),
      ),
    );
  }
}
