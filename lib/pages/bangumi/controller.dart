import 'dart:async';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_category.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_item.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:PiliPlus/services/bangumi_repository.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/widgets.dart' show GlobalKey, ScrollController;
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

  /// 已完成（成功或失败）的月份数，用于进度提示。
  final RxInt settledMonths = 0.obs;

  /// 月份 -> 条目；只放已成功返回的月份。
  final groups = <int, List<BangumiItem>>{}.obs;

  static final List<int> years = [
    for (var y = DateTime.now().year; y >= 2006; y--) y,
  ];

  static const int monthCount = 12;

  StreamSubscription<BangumiMonthResult>? _subscription;
  int _generation = 0;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// 加载指定年份；不传则重载当前年份。
  Future<void> load([int? targetYear]) {
    final target = targetYear ?? year.value;
    year.value = target;

    final generation = ++_generation;
    _subscription?.cancel();
    groups.clear();
    failedMonths.value = 0;
    settledMonths.value = 0;
    loading.value = true;

    final completer = Completer<void>();
    _subscription = BangumiRepository.loadYear(
      category: category,
      year: target,
      months: _monthOrder(target),
      hideNoScore: Pref.bangumiHideNoScore,
    ).listen(
      (result) {
        if (generation != _generation) return;
        settledMonths.value++;
        if (result.isSuccess) {
          groups[result.month] = result.items;
        } else {
          failedMonths.value++;
        }
      },
      onError: (Object _) {
        if (generation != _generation) return;
        loading.value = false;
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (generation != _generation) return;
        loading.value = false;
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: false,
    );
    return completer.future;
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
    _subscription?.cancel();
    super.onClose();
  }
}
