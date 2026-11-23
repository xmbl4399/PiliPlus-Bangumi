import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/common/widgets/native_top_spacer.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_category.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_item.dart';
import 'package:PiliPlus/pages/bangumi/controller.dart';
import 'package:PiliPlus/pages/bangumi/widgets/bangumi_card_v.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 首页一级 Tab「番剧 / 影视」的落地页。
///
/// 二级 Tab 留在 Flutter 内，ArkTS 顶栏协议（`setHomeTopBarData`）完全不动。
class BangumiPage extends StatefulWidget {
  const BangumiPage({
    super.key,
    required this.scope,
    required this.tag,
  });

  final BangumiScope scope;

  /// GetX 控制器 tag，与 `HomeTabType.name` 保持一致。
  final String tag;

  @override
  State<BangumiPage> createState() => _BangumiPageState();
}

class _BangumiPageState extends State<BangumiPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final BangumiController controller;

  @override
  bool get wantKeepAlive => true;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      BangumiController(scope: widget.scope),
      tag: widget.tag,
    );
    _tabController = TabController(
      length: controller.tabs.length,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    controller.tabIndex.value = _tabController.index;
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  String _labelOf(BangumiSubController tab) => switch (tab) {
    BangumiCalendarController() => '新番表',
    BangumiMonthController(:final category) => category.label,
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        // 原生顶栏生效时留出顶栏高度；非原生顶栏时高度为 0。
        Obx(() => SizedBox(height: NativeTopSpacer.staticHeight(context))),
        Material(
          color: theme.colorScheme.surface,
          child: SizedBox(
            height: 42,
            width: double.infinity,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              dividerHeight: 0,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
              indicatorPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 7,
              ),
              indicator: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: const BorderRadius.all(Radius.circular(20)),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: theme.colorScheme.onSecondaryContainer,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              labelStyle: const TextStyle(fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontSize: 14),
              tabs: [
                for (final tab in controller.tabs) Tab(text: _labelOf(tab)),
              ],
            ),
          ),
        ),
        Expanded(
          child: tabBarView(
            controller: _tabController,
            children: [
              for (final tab in controller.tabs)
                switch (tab) {
                  BangumiCalendarController() => BangumiCalendarView(
                    controller: tab,
                  ),
                  BangumiMonthController() => BangumiMonthView(
                    controller: tab,
                  ),
                  _ => const SizedBox.shrink(),
                },
            ],
          ),
        ),
      ],
    );
  }
}

/// 新番表：7 个星期分组纵向滚动，今天排第一组。
class BangumiCalendarView extends StatelessWidget {
  const BangumiCalendarView({super.key, required this.controller});

  final BangumiCalendarController controller;

  @override
  Widget build(BuildContext context) {
    return NativeTopRefreshIndicator(
      refreshKey: controller.refreshKey,
      onRefresh: controller.onRefresh,
      child: Obx(
        () => switch (controller.state.value) {
          Loading() => CustomScrollView(
            controller: controller.scrollController,
            slivers: const [
              SliverFillRemaining(hasScrollBody: false, child: m3eLoading),
            ],
          ),
          Error(:final errMsg) => CustomScrollView(
            controller: controller.scrollController,
            slivers: [
              HttpError(
                errMsg: errMsg,
                onReload: controller.query,
              ),
            ],
          ),
          Success(:final response) => _buildGroups(context, response),
        },
      ),
    );
  }

  Widget _buildGroups(
    BuildContext context,
    List<BangumiCalendarGroup> groups,
  ) {
    final slivers = <Widget>[];
    for (final group in groups) {
      slivers
        ..add(
          SliverToBoxAdapter(
            child: _GroupTitle(
              title: group.title,
              highlight: group.isToday,
            ),
          ),
        )
        ..add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
            sliver: group.items.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('这天没有可显示的番剧', style: TextStyle(fontSize: 12)),
                    ),
                  )
                : SliverGrid.builder(
                    gridDelegate: _gridDelegate(context, textExtent: 46),
                    itemCount: group.items.length,
                    itemBuilder: (context, index) => BangumiCardV(
                      item: group.items[index],
                      showEpisodes: false,
                    ),
                  ),
          ),
        );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return CustomScrollView(
      controller: controller.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }
}

/// 年月浏览：年份切换 + 12 个月渐进渲染。
class BangumiMonthView extends StatelessWidget {
  const BangumiMonthView({super.key, required this.controller});

  final BangumiMonthController controller;

  @override
  Widget build(BuildContext context) {
    final isTv = controller.category == BangumiCategory.tvAnime;
    final coverTags = Pref.bangumiShowTags && isTv;
    final showTags =
        Pref.bangumiShowTags &&
        controller.category.type == bangumiTypeAnime &&
        !isTv;
    final showEpisodes =
        Pref.bangumiShowEpisodes &&
        controller.category == BangumiCategory.tvAnime;

    return NativeTopRefreshIndicator(
      refreshKey: controller.refreshKey,
      onRefresh: controller.onRefresh,
      child: Obx(() {
        final groups = controller.groups;
        final loading = controller.loading.value;
        final failed = controller.failedMonths.value;

        final slivers = <Widget>[
          SliverToBoxAdapter(child: _YearBar(controller: controller)),
          if (loading)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ];

        if (loading && groups.isEmpty) {
          slivers.add(
            const SliverToBoxAdapter(
              child: SizedBox(height: 240, child: m3eLoading),
            ),
          );
        }

        for (var month = 12; month >= 1; month--) {
          final items = groups[month];
          if (items == null || items.isEmpty) continue;
          slivers
            ..add(
              SliverToBoxAdapter(
                child: _GroupTitle(title: '$month月 · ${items.length}部'),
              ),
            )
            ..add(
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.safeSpace,
                ),
                sliver: SliverGrid.builder(
                  gridDelegate: _gridDelegate(
                    context,
                    textExtent: coverTags ? 46 : 60,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => BangumiCardV(
                    item: items[index],
                    showTags: showTags,
                    showEpisodes: showEpisodes,
                    coverTags: coverTags,
                  ),
                ),
              ),
            );
        }

        if (!loading) {
          if (groups.isEmpty && failed == 0) {
            slivers.add(
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: Text('这个分类暂无条目')),
                ),
              ),
            );
          } else if (failed > 0) {
            slivers.add(
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$failed 个月份加载失败',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: controller.onRefresh,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        }

        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 100)));
        return CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        );
      }),
    );
  }
}

class _YearBar extends StatelessWidget {
  const _YearBar({required this.controller});

  final BangumiMonthController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = controller.year.value;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Style.safeSpace,
          vertical: 6,
        ),
        itemCount: BangumiMonthController.years.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final year = BangumiMonthController.years[index];
          final selected = year == current;
          return ChoiceChip(
            label: Text('$year'),
            selected: selected,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelStyle: TextStyle(
              fontSize: 12,
              color: selected
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            selectedColor: theme.colorScheme.secondaryContainer,
            onSelected: (_) {
              if (!selected) controller.load(year);
            },
          );
        },
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title, this.highlight = false});

  final String title;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: highlight
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

SliverGridDelegateWithExtentAndRatio _gridDelegate(
  BuildContext context, {
  double textExtent = 60,
}) => SliverGridDelegateWithExtentAndRatio(
  mainAxisSpacing: Style.cardSpace,
  crossAxisSpacing: Style.cardSpace,
  maxCrossAxisExtent: Grid.smallCardWidth * 0.6,
  childAspectRatio: 0.75,
  // TV 卡片 tag 贴在封面上，标题区只需容纳两行（46dp）；
  // 其它分类标题下还有一行 tag（60dp）。
  mainAxisExtent: MediaQuery.textScalerOf(context).scale(textExtent),
);
