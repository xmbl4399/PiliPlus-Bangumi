# Bangumi 页加载动画 & 流式加载 方案评估

> 2026-11-24，先评估不实现

## 一、加载动画改用 PiliPlus 自带骨架屏

### 现状

| 位置 | 当前实现 |
| --- | --- |
| 新番表首屏 | `m3eLoading`（M3E 图形动画，居中） |
| 月份页首屏 | `m3eLoading` + `LinearProgressIndicator`（顶部细进度条） |
| 月份渐进加载 | 顶部 `LinearProgressIndicator` 常驻 |

### 可用素材

- **骨架屏**：`lib/common/skeleton/skeleton.dart`
  - `Skeleton` 组件提供 shimmer 流光动画，直接包任意占位布局
  - 全项目 **32 个页面**在用（首页/收藏/关注/直播/回复等），是事实上的标准加载样式
  - 已有 `MediaPgcSkeleton`（横版番剧卡）可参考，但我们是竖版 3:4，需要新建
- **动画素材**：`assets/images/loading.webp`（播放器缓冲动画）、`loading.png`（图片占位）

### 方案对比

| 方案 | 说明 | 优点 | 缺点 |
| --- | --- | --- | --- |
| **A. 骨架屏（推荐）** | 新建 `BangumiCardSkeleton`，复用 `Skeleton` shimmer；首屏铺 1 屏骨架卡 | 与全 App 一致；不闪白；能预示布局 | 需要写一个占位组件 |
| B. 动画 webp | `Image.asset(Assets.buffering)` 居中 | 字面符合「自带动画素材」 | 列表页不常见；与其它页面不一致 |
| C. 保留 m3e | 仅去掉 LinearProgressIndicator | 改动最小 | 不符合本次诉求 |

### 推荐做法（A）

- 新增 `lib/pages/bangumi/widgets/bangumi_card_skeleton.dart`
  - 外层 `Skeleton`，内部：封面方块（3:4）+ 两行标题条 +（可选）tag 条
  - 尺寸直接复用网格 delegate，保证和真实卡片同高
- 新番表首屏：`SliverGrid` 铺 6~9 个骨架卡
- 月份页首屏：同上；后续「加载更多」在列表底部放 **1 行骨架卡**，不再用进度条
- 删除 `m3eLoading` 与 `LinearProgressIndicator` 的使用（错误态仍用现有 `HttpError`）

**工作量**：0.5~1 h

---

## 二、月份页改流式加载（新番表保持一次请求）

### 现状

进入某个分类的某一年 → `BangumiRepository.loadYear()`：

- 一次性把 12 个月排进队列，并发 4 拉取
- 首屏要等 4 个月返回后才开始铺开，之后持续补数据
- 请求数：每个分类每年 **12 次**（首次）；缓存命中后为 0

### 目标

- 首屏只请求「当前可见月份」，滚到底再拉下一个月
- 保留现有缓存（当季 6h / 历史 30d）
- 快速滚动不重复请求（单飞 + 代次校验）
- 空月份不让用户卡住

### 设计

**数据层**

- 复用 `BangumiRepository.browseYearMonth(category, year, month)`（已是单月 + 缓存）
- `loadYear()` 不再使用（保留或删除）

**控制器 `BangumiMonthController`**

```
year
pendingMonths   = [12, 11, ..., 1]（当前年可改 11→12→10→…）
groups          = {month: items}
loading         = 是否有请求在飞
hasMore
failedMonths
_generation     // 切年份/刷新时 +1，丢弃过期响应
```

- `load(year)`：重置状态、生成队列、立即拉第一个月
- `loadMore()`：
  - 单飞：`loading == true` 直接返回
  - 取队首月份 → `browseYearMonth`
  - 成功且为空 → 自动继续下一个月（最多连续 2 个空月，避免变相全量）
  - 失败 → 记录失败月份，继续下一个；底部提供「重试」
  - 队列耗尽 → `hasMore = false`
- `onRefresh()`：保留当前年，从队首重拉

**视图**

- 触发方式（推荐 b）：
  - a. 最后一项 `itemBuilder` 里调 `loadMore()`（PgcPage 同款）
  - b. `ScrollController` 监听：`pixels > maxScrollExtent - 800` 时预取（更顺滑）
- 底部状态：
  - `loading` → 1 行骨架卡
  - `failed > 0` → 「N 个月份加载失败 · 重试」
  - `!hasMore` → 「没有更多了」/ 留白
- 年份切换：滚动回顶部 + 清空旧数据 + 重新从 12 月开始

**行为变化**

| 场景 | 现在 | 改后 |
| --- | --- | --- |
| 进入 TV 2026 | 12 个请求并发 | 1 个请求（12 月） |
| 滚到 11 月 | 数据已在 | 触发第 2 个请求 |
| 二次进入 | 缓存全量 | 缓存月份直接出，未缓存滚到时再拉 |
| 弱网首屏 | 等 4 个月 | 等 1 个月即可见 |

**工作量**：1~1.5 h（controller 重写 + view 改造）

---

## 三、总工作量与风险

| 项 | 时间 |
| --- | --- |
| 骨架屏组件 + 接入 | 0.5~1 h |
| 流式加载 controller/view | 1~1.5 h |
| 构建、安装、真机验证 | 0.5 h |
| **合计** | **2~3 h** |

### 风险与对策

| 风险 | 对策 |
| --- | --- |
| 骨架卡与真实卡高度不一致，加载完跳动 | 共用同一个 grid delegate；骨架只替换卡片内部 |
| 快速滚动触发多次请求 | `loading` 单飞 + `generation` 丢弃过期响应 |
| 空月份导致「滚到底没反应」 | 自动跳过，但限制最多连续 2 个 |
| 首屏 1 个月太短，页面不满一屏无法滚动 | 空/少量数据时底部放「继续加载」按钮或自动补一个月 |
| 缓存月份一次命中多个 | 允许同步追加，但每次滚动最多补 2 个月 |
| 骨架 shimmer 数量多导致耗电 | 首屏最多 9 个骨架卡，滚出屏幕即回收 |

---

## 四、需要确认

1. 加载动画：**骨架屏 shimmer（推荐）** / 动画 webp `loading.webp` / 两者都不要，保留 m3e？
2. 触发方式：**滚动阈值预取（推荐）** / 最后一项触发？
3. 首屏预取：只拉 1 个月（最省）/**2 个月（推荐，滚动更顺）**？
