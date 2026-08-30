import 'dart:async' show unawaited;

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/bangumi/bangumi_browse_item.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 月份分组段
class BangumiMonthSegment {
  final int month;
  final Rx<LoadingState<List<BangumiBrowseItem>?>> state;

  BangumiMonthSegment(
    this.month,
    LoadingState<List<BangumiBrowseItem>?> initial,
  ) : state = initial.obs;
}

/// 年份下限：2006（更早无意义）
const int kBangumiEarliestYear = 2006;

/// 单个浏览页控制器（一个 BangumiBrowseMode 一个实例）
///
/// 年份流式加载算法（Bangumi_Integration_Guide §5.1）：
/// 1. 先显缓存：同步遍历月份，已缓存月立即入列表（秒出，不触发网络）
/// 2. 缺失月后台补：顺序拉取，逐月追加，保持月份倒序
/// 3. 下拉刷新：force 重拉，当月返回即停转圈，后续月份静默追加（P3-2）
class BangumiBrowseController extends GetxController with ScrollOrRefreshMixin {
  BangumiBrowseController(this.mode);

  final BangumiBrowseMode mode;

  final int currentYear = DateTime.now().year;
  final RxInt selectedYear = RxInt(DateTime.now().year);

  final RxList<BangumiMonthSegment> segments = <BangumiMonthSegment>[].obs;

  /// 首屏加载中（存在缺失月且第一个缺失月未返回）
  final RxBool yearLoading = true.obs;

  @override
  final ScrollController scrollController = ScrollController();

  bool _disposed = false;
  int _loadToken = 0;

  List<int> _monthsOf(int year) {
    final start = year == currentYear ? DateTime.now().month : 12;
    return [for (var m = start; m >= 1; m--) m];
  }

  @override
  void onInit() {
    super.onInit();
    loadYear();
  }

  void selectYear(int year) {
    if (year == selectedYear.value && segments.isNotEmpty) return;
    selectedYear.value = year;
    loadYear();
  }

  Future<void> loadYear() async {
    final token = ++_loadToken;
    segments.clear();
    yearLoading.value = true;

    final months = _monthsOf(selectedYear.value);
    final missing = <int>[];

    // 步骤1：同步检查缓存，命中的月立即入列表（秒出）
    for (final m in months) {
      if (token != _loadToken || _disposed) return;
      final cached = mode.peekCache(year: selectedYear.value, month: m);
      if (cached != null && cached.isNotEmpty) {
        segments.add(
          BangumiMonthSegment(m, Success<List<BangumiBrowseItem>?>(cached)),
        );
      } else {
        missing.add(m);
      }
    }

    // 步骤2：缺失月后台补，逐月追加（段在数据到达后才插入，避免占位空段导致白屏）
    var first = true;
    for (final m in missing) {
      if (token != _loadToken || _disposed) return;
      await _fetchMonth(m, force: false, token: token);
      if (first) {
        first = false;
        yearLoading.value = false;
      }
    }
    if (first) yearLoading.value = false;
  }

  /// 拉取某月：已有段则原地替换（刷新保持旧数据防闪烁），
  /// 无段则等数据到达后插入；带 token/年份双重竞态保护
  Future<void> _fetchMonth(
    int m, {
    required bool force,
    required int token,
  }) async {
    final year = selectedYear.value;
    final idx = segments.indexWhere((s) => s.month == m);
    try {
      final items = await mode.fetch(year: year, month: m, force: force);
      if (_disposed || token != _loadToken || year != selectedYear.value) {
        return;
      }
      if (idx >= 0) {
        segments[idx].state.value = Success<List<BangumiBrowseItem>?>(items);
      } else {
        segments.add(
          BangumiMonthSegment(m, Success<List<BangumiBrowseItem>?>(items)),
        );
      }
    } catch (e) {
      if (_disposed || token != _loadToken || year != selectedYear.value) {
        return;
      }
      if (idx >= 0) {
        segments[idx].state.value = Error(e.toString());
      } else {
        segments.add(BangumiMonthSegment(m, Error(e.toString())));
      }
    }
  }

  /// 单月重试（错误段点击）
  Future<void> retryMonth(int month) =>
      _fetchMonth(month, force: true, token: _loadToken);

  /// 下拉刷新（流式，P3-2）：首月 force 重拉，返回即停转圈；
  /// 其余月份后台逐月静默替换追加，保持月份倒序
  @override
  Future<void> onRefresh() async {
    final token = ++_loadToken;
    final months = _monthsOf(selectedYear.value);
    await _fetchMonth(months.first, force: true, token: token);
    unawaited(_fillRest(months.sublist(1), token));
  }

  Future<void> _fillRest(List<int> months, int token) async {
    for (final m in months) {
      if (token != _loadToken || _disposed) return;
      await _fetchMonth(m, force: true, token: token);
    }
  }

  @override
  void onClose() {
    _disposed = true;
    _loadToken++;
    scrollController.dispose();
    super.onClose();
  }
}

/// 番剧/影视容器控制器：透传当前子页的滚动/刷新给首页 tab 栏
class BangumiSectionController extends GetxController
    with GetSingleTickerProviderStateMixin, ScrollOrRefreshMixin {
  BangumiSectionController(this.tag);

  final String tag;

  late final List<BangumiBrowseMode> modes = switch (tag) {
    'bangumi' => const [
      BangumiBrowseMode.tvAnime,
      BangumiBrowseMode.webAnime,
      BangumiBrowseMode.ovaAnime,
      BangumiBrowseMode.animeMovie,
    ],
    _ => const [
      BangumiBrowseMode.jpDrama,
      BangumiBrowseMode.westernDrama,
      BangumiBrowseMode.cnDrama,
      BangumiBrowseMode.kdrama,
      BangumiBrowseMode.movie,
    ],
  };

  late final TabController tabController = TabController(
    length: modes.length,
    vsync: this,
  );

  BangumiBrowseController? get activeController {
    if (modes.isEmpty) return null;
    try {
      return Get.find<BangumiBrowseController>(
        tag: modes[tabController.index].name,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  ScrollController get scrollController =>
      activeController?.scrollController ?? _fallbackController;

  static final ScrollController _fallbackController = ScrollController();

  @override
  Future<void> onRefresh() async {
    await activeController?.onRefresh();
  }

  @override
  void onClose() {
    tabController.dispose();
    super.onClose();
  }
}
