import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_category.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_item.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:PiliPlus/services/bangumi_repository.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/widgets.dart'
    show GlobalKey, ScrollController, WidgetsBinding;
import 'package:get/get.dart';

/// 顶栏一级入口对应的数据范围。
enum BangumiScope {
  /// 「番剧」：新番表 + TV 番剧 + 非 TV 番剧
  anime,

  /// 「影视」：日剧 / 欧美剧 / 华语剧 / 韩剧 / 电影
  real,
}

/// 「番剧 / 影视」页的父控制器。
///
/// 自身不持有滚动控制器，只把首页的下拉刷新 / 滚动联动转发给当前二级 Tab，
/// 这样 `HomeTabType.ctr` 仍然只需要拿到一个 `ScrollOrRefreshMixin`。
class BangumiController extends GetxController with ScrollOrRefreshMixin {
  BangumiController({required this.scope});

  final BangumiScope scope;

  late final List<BangumiSubController> tabs =
      scope == BangumiScope.anime
      ? [
          BangumiCalendarController(),
          for (final category in BangumiCategory.animeTabs)
            BangumiMonthController(category),
        ]
      : [
          for (final category in BangumiCategory.realTabs)
            BangumiMonthController(category),
        ];

  /// 当前二级 Tab 下标，由页面的 TabController 同步。
  final RxInt tabIndex = 0.obs;

  BangumiSubController get _active =>
      tabs[tabIndex.value.clamp(0, tabs.length - 1)];

  @override
  void onInit() {
    super.onInit();
    for (final tab in tabs) {
      tab.onInit();
    }
  }

  @override
  void onClose() {
    for (final tab in tabs) {
      tab.onClose();
    }
    super.onClose();
  }

  @override
  ScrollController get scrollController => _active.scrollController;

  @override
  Future<void> onRefresh() => _active.onRefresh();

  @override
  Future<void> showRefresh() => _active.showRefresh();
}

/// 二级 Tab 控制器基类。
abstract class BangumiSubController extends GetxController
    with ScrollOrRefreshMixin {
  @override
  final ScrollController scrollController = ScrollController();

  @override
  final GlobalKey<RefreshIndicatorState> refreshKey =
      GlobalKey<RefreshIndicatorState>();
}

/// 「新番表」：一次拉全站周历，按星期分组。
class BangumiCalendarController extends BangumiSubController {
  final state = Rx<LoadingState<List<BangumiCalendarGroup>>>(
    LoadingState<List<BangumiCalendarGroup>>.loading(),
  );

  @override
  void onInit() {
    super.onInit();
    query();
  }

  Future<void> query({bool isRefresh = false}) async {
    if (!isRefresh) {
      state.value = LoadingState<List<BangumiCalendarGroup>>.loading();
    }
    final res = await BangumiRepository.loadCalendar(
      hideNoScore: Pref.bangumiHideNoScore,
    );
    if (isClosed) return;
    state.value = res;
  }

  @override
  Future<void> onRefresh() => query(isRefresh: true);
}

/// 「某分类某一年」：并发拉取 12 个月，按月渐进渲染。
class BangumiMonthController extends BangumiSubController {
  BangumiMonthController(this.category);

  final BangumiCategory category;

  final RxInt year = DateTime.now().year.obs;
  final RxBool loading = false.obs;
  final RxInt failedMonths = 0.obs;

  final RxBool hasMore = true.obs;

  /// 首屏预取的月份数。
  static const int prefetchCount = 2;

  /// 距底部多少像素开始预取下一月。
  static const double prefetchDistance = 800;

  /// 待加载月份队列（按展示顺序）。
  final List<int> _pending = [];
  int _emptyStreak = 0;
  int _autoFillCount = 0;

  /// 月份 -> 条目；只放已成功返回的月份。
  final groups = <int, List<BangumiItem>>{}.obs;

  static final List<int> years = [
    for (var y = DateTime.now().year; y >= 2006; y--) y,
  ];

  static const int monthCount = 12;

  int _generation = 0;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    load();
  }

  void _onScroll() {
    if (loading.value || !hasMore.value) return;
    if (!scrollController.hasClients) return;
    if (scrollController.position.extentAfter < prefetchDistance) {
      loadMore();
    }
  }

  /// 加载指定年份；不传则重载当前年份。
  Future<void> load([int? targetYear]) async {
    final target = targetYear ?? year.value;
    year.value = target;
    _generation++;
    _pending
      ..clear()
      ..addAll(_monthOrder(target));
    groups.clear();
    failedMonths.value = 0;
    hasMore.value = true;
    _emptyStreak = 0;
    _autoFillCount = 0;
    if (scrollController.hasClients && scrollController.offset > 0) {
      scrollController.jumpTo(0);
    }
    // 首屏只预取最近 2 个月，其余滚到底部再拉。
    for (var i = 0; i < prefetchCount && _pending.isNotEmpty; i++) {
      await _loadNext();
    }
    _scheduleAutoFill();
  }

  /// 滚动阈值触发的加载下一页。
  Future<void> loadMore() async {
    if (loading.value || !hasMore.value) return;
    await _loadNext();
    _scheduleAutoFill();
  }

  Future<void> _loadNext() async {
    if (_pending.isEmpty) {
      hasMore.value = false;
      return;
    }
    final generation = _generation;
    final month = _pending.removeAt(0);
    loading.value = true;
    final res = await BangumiRepository.browseYearMonth(
      category: category,
      year: year.value,
      month: month,
      hideNoScore: Pref.bangumiHideNoScore,
    );
    if (isClosed || generation != _generation) return;
    loading.value = false;
    switch (res) {
      case Success(:final response):
        if (response.isEmpty) {
          _emptyStreak++;
        } else {
          _emptyStreak = 0;
          groups[month] = response;
        }
      case Error():
        _emptyStreak = 0;
        failedMonths.value++;
      case Loading():
        break;
    }
    if (_pending.isEmpty) {
      hasMore.value = false;
    } else if (_emptyStreak > 0 && _emptyStreak <= 2) {
      // 空月份最多连续跳过 2 个，避免滚到底看到一片空白。
      await _loadNext();
    }
  }

  /// 内容不足一屏时自动补数据（最多 3 次），避免无法滚动。
  void _scheduleAutoFill() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed || loading.value || !hasMore.value) return;
      if (_autoFillCount >= 3) return;
      if (!scrollController.hasClients) return;
      if (scrollController.position.maxScrollExtent < 240) {
        _autoFillCount++;
        loadMore();
      }
    });
  }

  /// 当前年份优先加载「当季 → 未来 → 过去」，其余年份固定 12 → 1。
  List<int> _monthOrder(int target) {
    final now = DateTime.now();
    if (target != now.year) {
      return [for (var m = 12; m >= 1; m--) m];
    }
    return [
      for (var m = now.month + 1; m <= 12; m++) m,
      for (var m = now.month; m >= 1; m--) m,
    ];
  }

  @override
  Future<void> onRefresh() => load();

  @override
  void onClose() {
    _generation++;
    scrollController.removeListener(_onScroll);
    super.onClose();
  }
}
