import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/button/more_btn.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_browse_item.dart';
import 'package:PiliPlus/pages/bangumi_browse/bangumi_browse_controller.dart';
import 'package:PiliPlus/pages/bangumi_browse/widgets/bangumi_card.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 番剧/影视容器页：二级子 tab（TV/WEB/OVA/剧场版 或 日剧/欧美剧/华语剧/韩剧/电影）
class BangumiSectionPage extends StatefulWidget {
  const BangumiSectionPage({super.key, required this.tag});

  /// HomeTabType.bangumi.name / HomeTabType.cinema.name
  final String tag;

  @override
  State<BangumiSectionPage> createState() => _BangumiSectionPageState();
}

class _BangumiSectionPageState extends State<BangumiSectionPage>
    with AutomaticKeepAliveClientMixin {
  late final BangumiSectionController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      BangumiSectionController(widget.tag),
      tag: widget.tag,
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: 40,
          width: double.infinity,
          child: TabBar(
            controller: controller.tabController,
            tabs: controller.modes.map((m) => Tab(text: m.label)).toList(),
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            splashBorderRadius: Style.mdRadius,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            indicator: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
            ),
            labelColor: theme.colorScheme.onSecondaryContainer,
            labelStyle: const TextStyle(fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
          ),
        ),
        Expanded(
          child: tabBarView(
            controller: controller.tabController,
            children: controller.modes
                .map((m) => BangumiBrowsePage(mode: m))
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// 单个模式浏览页：年份栏 + 月份倒序分组网格
class BangumiBrowsePage extends StatefulWidget {
  const BangumiBrowsePage({super.key, required this.mode});

  final BangumiBrowseMode mode;

  @override
  State<BangumiBrowsePage> createState() => _BangumiBrowsePageState();
}

class _BangumiBrowsePageState extends State<BangumiBrowsePage>
    with AutomaticKeepAliveClientMixin {
  late final BangumiBrowseController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      BangumiBrowseController(widget.mode),
      tag: widget.mode.name,
    );
  }

  @override
  bool get wantKeepAlive => true;

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: Grid.smallCardWidth * 0.6,
    childAspectRatio: 0.75,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(50),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildYearBar(context),
        Expanded(
          child: refreshIndicator(
            onRefresh: controller.onRefresh,
            child: Obx(() => _buildBody(context)),
          ),
        ),
      ],
    );
  }

  // ---------------- 年份栏 ----------------

  Widget _buildYearBar(BuildContext context) {
    final theme = Theme.of(context);
    final years = <int>[
      for (var y = controller.currentYear; y >= kBangumiEarliestYear; y--) y,
    ];
    return SizedBox(
      height: 42,
      width: double.infinity,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
        itemCount: years.length,
        itemBuilder: (context, index) {
          final year = years[index];
          return Obx(() {
            final selected = year == controller.selectedYear.value;
            return Padding(
              padding: const EdgeInsets.only(right: 8, top: 7, bottom: 7),
              child: Material(
                color: selected
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.onSecondaryContainer.withValues(
                        alpha: 0.05,
                      ),
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                child: InkWell(
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  onTap: () => controller.selectYear(year),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        '$year',
                        style: TextStyle(
                          fontSize: 13,
                          color: selected
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.outline,
                          fontWeight: selected ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          });
        },
      ),
    );
  }

  // ---------------- 列表主体 ----------------

  Widget _buildBody(BuildContext context) {
    final segments = controller.segments;
    if (segments.isEmpty) {
      if (controller.yearLoading.value) {
        return CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: const [SliverFillRemaining(child: m3eLoading)],
        );
      }
      return _emptyView('暂无数据，下拉刷新重试');
    }
    return CustomScrollView(
      controller: controller.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final seg in segments) ..._buildMonthSection(context, seg),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _emptyView(String text) {
    return CustomScrollView(
      controller: controller.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.loadYear,
            child: Center(child: Text(text)),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMonthSection(
    BuildContext context,
    BangumiMonthSegment seg,
  ) => [
    // header：{m}月 · N 部
    SliverToBoxAdapter(
      child: Obx(() {
        final state = seg.state.value;
        return switch (state) {
          Success(:final response) when response?.isNotEmpty == true =>
            _monthHeader('${seg.month}月 · ${response!.length} 部'),
          _ => const SizedBox.shrink(),
        };
      }),
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
      sliver: Obx(() {
        final state = seg.state.value;
        return switch (state) {
          Success(:final response) when response?.isNotEmpty == true =>
            SliverGrid.builder(
              gridDelegate: gridDelegate,
              itemCount: response!.length,
              itemBuilder: (context, index) =>
                  BangumiCard(item: response[index], mode: widget.mode),
            ),
          Error(:final errMsg) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(
                    '${seg.month}月加载失败：${errMsg ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  moreTextButton(
                    text: '重试',
                    onTap: () => controller.retryMonth(seg.month),
                  ),
                ],
              ),
            ),
          ),
          _ => const SliverToBoxAdapter(child: SizedBox.shrink()),
        };
      }),
    ),
  ];

  Widget _monthHeader(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}
