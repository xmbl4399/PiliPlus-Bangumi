import 'package:PiliPlus/common/skeleton/skeleton.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:material_ui/material_ui.dart';

/// 番剧/影视卡片骨架屏（首屏加载占位）
///
/// 尺寸与真卡片 BangumiCard 完全对齐：Card(mdRadius) + 0.75 封面比例 +
/// grid 的 mainAxisExtent(38) 标题区（上下内边距 4 + 2 行文字）。
/// 因此骨架和真卡片占同一个格子，数据到达后原地替换不会跳版。
class BangumiCardSkeleton extends StatelessWidget {
  const BangumiCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = ColorScheme.of(context).onInverseSurface;
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
            color: ColorScheme.of(context).onInverseSurface,
          ),
        ),
      ),
    );
  }
}
