import 'package:PiliPlus/common/skeleton/skeleton.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:material_ui/material_ui.dart';

/// Bangumi 竖版卡片骨架屏。
///
/// 复用 PiliPlus 的 [Skeleton] shimmer 动画，尺寸与真实卡片共用同一套
/// grid delegate，加载完成后不会发生布局跳动。
class BangumiCardSkeleton extends StatelessWidget {
  const BangumiCardSkeleton({super.key, this.lines = 2});

  /// 标题占位行数（1~2）。
  final int lines;

  @override
  Widget build(BuildContext context) {
    final bgColor = ColorScheme.of(context).onInverseSurface;
    return Skeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: Style.aspectRatio3x4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Container(width: double.infinity, height: 12, color: bgColor),
          if (lines > 1) ...[
            const SizedBox(height: 5),
            Container(width: 84, height: 12, color: bgColor),
          ],
        ],
      ),
    );
  }
}
