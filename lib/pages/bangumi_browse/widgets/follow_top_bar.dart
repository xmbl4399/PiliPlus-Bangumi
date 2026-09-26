import 'package:PiliPlus/common/widgets/custom_height_widget.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 让页面内的二级/三级顶栏跟随首页搜索栏一起收起/展开。
///
/// 复用首页搜索栏（`_HomePageState.customAppBar`）的**同一批信号 + 同一套动画参数**，
/// 保证多层顶栏同步，不会出现"搜索栏收起了、下面两栏还杵在那"的割裂感。
///
/// | 首页状态 | 信号源 | 表现 |
/// |---|---|---|
/// | 未开「首页顶栏收起」/ 侧边栏 / 非竖屏 | — | 固定高度 |
/// | 顶栏收起 = 同步（默认） | `MainController.barOffset` | 与搜索栏同速线性上移并压高度 |
/// | 顶栏收起 = 即时 | `HomeController.showTopBar` | 500ms 收起 + 300ms 淡出 |
class FollowTopBar extends StatelessWidget {
  const FollowTopBar({super.key, required this.height, required this.child});

  /// 展开状态下的高度（应与 child 的实际高度一致）
  final double height;

  final Widget child;

  /// 与 `_HomePageState.customAppBar` 中的参数保持一致
  static const _opacityDuration = Duration(milliseconds: 300);
  static const _sizeDuration = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    final home = Get.isRegistered<HomeController>()
        ? Get.find<HomeController>()
        : null;
    // 复刻首页搜索栏的渲染条件：只有首页真的会显示搜索栏时才联动，
    // 否则横屏/侧边栏下会出现"顶栏自己缩、上面却没有搜索栏"的怪表现
    if (home == null ||
        !home.hideTopBar ||
        !MediaQuery.sizeOf(context).isPortrait) {
      return _fixed();
    }

    final main = Get.isRegistered<MainController>()
        ? Get.find<MainController>()
        : null;

    // 同步模式：与搜索栏同速上移（高度同步压缩，偏移量一致）
    if (main?.barOffset case final offset?) {
      return Obx(() {
        final value = offset.value;
        return CustomHeightWidget(
          offset: Offset(0, -value),
          // 超过自身高度后由 RenderCustomHeightWidget 内部 clamp 到 0
          height: height - value,
          child: _fixed(),
        );
      });
    }

    // 即时模式：与搜索栏同参数收起
    if (home.showTopBar case final showTopBar?) {
      return Obx(() {
        final show = showTopBar.value;
        return AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: _opacityDuration,
          child: ClipRect(
            child: AnimatedContainer(
              curve: Curves.easeInOutCubicEmphasized,
              duration: _sizeDuration,
              height: show ? height : 0,
              // 高度收缩时保持内容原尺寸（否则 Tab 文字会被压扁变形），
              // 溢出部分交给外层 ClipRect 裁掉
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: height,
                maxHeight: height,
                child: _fixed(),
              ),
            ),
          ),
        );
      });
    }

    return _fixed();
  }

  Widget _fixed() =>
      SizedBox(width: double.infinity, height: height, child: child);
}
