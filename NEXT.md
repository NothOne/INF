# 优化方案（1.6.9 之后）

这份文档给下一个接手的人：现在的架构是什么样、为什么是这样、接下来做什么、以及**为什么不做某些看起来该做的事**。

先读 `AGENTS.md` 的规则和 `CODE_MAP.md` 的结构，再读这份。这份只讲判断和取舍。

---

## 一、现状：这套架构是什么

规模：`lib/` 137 个文件、34k 行；`test/` 46 个文件、356 条测试。

### 分层

```
features/*（页面）
  ├─→ core/navigation.dart（唯一的 openXxx 路由表）
  ├─→ core/widgets/*（通用控件）
  └─→ 状态单例 → api / parse / models → native
```

硬约束（可用 `rg -n "features/" lib/core` 自检）：
- `core/` 里只有 `navigation.dart` 可以 import `features/*`
- 功能页之间不互相 import；`shell/root_shell.dart` 引用 4 个 Tab 是唯一例外
- 只允许上层依赖下层

### 四类"决定"各有唯一落点

这是这套架构真正的组织原则，不是分层。每类决定只允许写一次：

| 决定 | 落点 | 曾经有几份 |
|---|---|---|
| 一条微博能做什么 | `core/widgets/status_actions.dart`（纯数据） | 1 |
| 卡片在页面里怎么接线 | `core/widgets/status_card_host.dart` `buildStatusCard` | 4 |
| 发评论 / 回复 | `core/comment_store.dart` `CommentStore.send` | 3 |
| 发私信 | `core/message_sender.dart` | 2 |
| 关注 / 屏蔽 | `core/relation_store.dart` | 3 |
| 错误怎么显示 | `core/error_text.dart` `ErrorView` | 10 |
| 列表尾部 | `core/widgets/pager_tail.dart` | 6 |
| 时间 / 计数 / HTML→文本 | `weibo_time` / `weibo_json` / `weibo_html` | 1 |
| 哪个接口用哪套凭据 | `api.dart` + `api_<域名>.dart` / `GroupChatApi` / `WeiboComSession` | 3 类混在一起过 |

### 状态管理：单例 + ChangeNotifier，无框架

- 全局状态：`Session` `Prefs` `StatusStore` `CommentStore` `RelationStore` `UnreadMonitor` `EmojiStore` `HotSearchStore`
- 页面状态：`StatefulWidget` + `setState`；复杂页有页面级控制器（`FeedController`、`FeedReadingPosition`）
- 列表：`PagingController<T>`

**按 id 订阅**（这是 1.6.9 新加的，重要）：

```dart
// 只在这个 id 变化时重建
AnimatedBuilder(
  animation: StatusStore.instance.of([status.id]),
  builder: ...,
)
```

不要写 `animation: StatusStore.instance`——那会让列表里任何一条被点赞时整屏重建。
`test/status_store_scope_test.dart` 数重建次数钉住这件事。

### 数据流的形状（这是最该改的地方，见第三节）

```
Widget ──创建──→ PagingController<T>(fetch: cursor => WeiboApi.instance.xxx(cursor))
  ▲                    │ refresh() / loadMore()
  │                    ▼  原始 JSON → parse.dart → 新模型对象
  └──notifyListeners── PageResult<T>(items, nextCursor)
```

**注意这里：每次刷新都产出全新的对象，旧对象被丢弃。** 页面之间靠 Store 存的"差量"对齐（点赞、评论数），而不是靠共享同一个对象。这是当前架构最根本的局限。

---

## 二、接下来做什么（按优先级）

判断标准只有一条：**这件事会不会随功能增长而恶化。** 不会恶化的，再丑也可以先放着。

### P1 · 端点能力矩阵 + fixture 解析测试 —— **已完成（1.7.0）**

**为什么第一优先**：这是唯一会持续腐烂的地方。微博改字段不会通知任何人，现在的防护是"用户投诉"。

**做什么**：

1. 把 `test/fixtures/` 建起来，每个主要接口存一份真实响应 JSON（脱敏）
2. 每个 endpoint 一条 golden test：fixture → `parse.dart` → 断言关键字段
3. 把"哪个域名、哪套凭据、有没有验证码风险"从注释变成结构：

```dart
// core/endpoint.dart
enum EndpointHost { mWeibo, weiboCom, apiWeibo, passport, msWeibo }
enum EndpointAuth { user, visitor, none }

class Endpoint {
  final EndpointHost host;
  final EndpointAuth auth;
  final bool captchaRisk;   // 写接口
  final bool cached;        // 是否写 PageCache
  const Endpoint(...);
}
```

**不要**做成"一个 Endpoint 描述一切"的大重构。第一步只需要两件：
- fixture 测试（独立，无侵入）
- `captchaRisk` 这个布尔（用来在 UI 上提前提示"这个操作可能要验证"，而不是等失败）

**验收**：`test/fixtures/` 有至少 8 个接口的样本；`flutter test` 里有对应的 golden 断言；改坏 `parse.dart` 的一个字段能让测试红。

**风险**：低。纯新增测试文件。

**落地情况**：`test/fixtures/` 20 份真实回包（2026-11-19 抓的，裁剪规则见那里的 `README.md`），`test/fixture_parse_test.dart` 36 条 golden 断言，`lib/core/endpoints.dart` 是那张表（`Endpoint` 是 enum，`captchaRisk` 只给走 `_post` 的 m.weibo.cn 写接口标），`test/endpoint_matrix_test.dart` 10 条把表和 `api_*.dart` 的真实调用对齐——API 层问到的路径必须有行，每行也必须真的有地方在问，走 `_getWeiboCom` / 全 URL 的还要落在对的 host 上。`compose_page.dart` 发微博时据此提前提示可能要过验证。

**抓不到的**：要登录态的接口（信息流、通知、私信、某人时间线、搜索结果、weibo.com 那份微博本体）对游客一律回 `{ok:-100}`，所以没有 fixture；它们的解析由同形状的容器（`profile/feature` 就是一页 card 列表）和 `widget_test.dart` / `comment_parse_test.dart` 里手写的用例覆盖。要补的话，从真机的 `page_cache/*.json` 里取。

---

### P2 · 归一化实体存储（`Entities`）—— **第一步已完成（1.7.0）**

**为什么第二**：它消灭最大一类 bug——"同一个东西的多个副本不同步"。这个项目里这类 bug 出现过至少三次（关注状态、评论数、点赞），每次的修法都是"再加一个 Store 记住差量"，而 Store 越多越难保证一致。

**做什么**：

```dart
// core/entities.dart
class Entities extends ChangeNotifier {
  Entities._();
  static final Entities instance = Entities._();

  final Map<String, Status> _statuses = {};
  final Map<String, User> _users = {};
  final Map<String, Comment> _comments = {};

  Status? status(String id) => _statuses[id];
  void putStatus(Status status) { ... }        // 合并，不是覆盖
  void mergeStatus(String id, {bool? liked, int? likesCount, ...});
}
```

要点：

- **`put` 是合并语义**：一个只带 `likes_count` 的响应不能把 `text` 抹掉
- **列表仍存对象，但对象来自 `Entities`**：`PagingController` 产出 id 后从 `Entities` 取当前值
- **需要回收**：`Map` 会无限增长，加 LRU（保留最近 N 条，N 与 `StatusStore` 的 `longTextKept` 同量级）

**分阶段**（不要一次改完）：

1. 先只做 `Status`，接入 `StatusStore.apply` 的读路径，让列表和详情读同一份
2. 观察一个版本，确认没有"某个页面依赖自己的副本"的隐式假设
3. 再纳入 `User`（关注状态）和 `Comment`（评论点赞）

**验收**：在信息流点赞 → 打开详情 → 返回，三步都是同一个数；把这个流程做成 widget 测试。

**风险**：中。会触及 `StatusStore` / `PagingController` / `StatusCard` 的读路径。**必须一次只做一个实体类型**。

**落地情况（第一步：只做 `Status`）**：

- `core/entities.dart`：`put` 是合并，同一回答返回同一对象；LRU 200 条。
- `StatusStore.apply` 的底稿改成从 `Entities` 取，不信任调用方那份副本；新增 `remember` / `rememberAll` 作为唯一写入入口，`seed` 先 `remember` 再记点赞基线。
- `PagingController` 加了可选的 `remember` 回调，在 `_append` 里对**每一行到达的数据**调用一次（含 cache seed）。8 个 `PagingController<Status>` 全部接上。选择在 pager 收口、而不是在卡片 `build` 里 file，是因为后者会把行手里那份旧副本反复写回去——正是这层要消掉的漂移。
- 详情页取到全文后写回 `Entities`，所以从详情返回时列表里的卡片读到的是全文而不是六行截断。
- **顺带修了一个真 bug**：`_LikeState` 原来存绝对值，`apply` 会用它盖掉更新的计数（详情页刷新出 101 赞，列表还是显示 100）。现在和评论数一样是 baseline + delta。
- 测试：`entities_test.dart`（15 条，合并语义 + LRU）、`entities_flow_test.dart`（4 条 widget 级：列表/详情同一份、本机改动不被新回答覆盖）。`status_counts_test.dart` 的辅助函数改成把微博 file 进 `Entities`，因为它现在代表真实产生状态的那个流程。

**下一步（未做）**：观察一个版本，确认没有页面依赖自己那份副本；再把 `User` 和 `Comment` 纳入。`User` 要先想清楚和 `RelationStore` 的关系——关注状态是「本机会话改过什么」，搬进 `Entities` 会让两者都想当唯一来源。**别在没看清这点之前动它。**

---

### P3 · 失败分类（`Failure` sealed class）—— **已完成（1.7.0）**

**为什么**：现在所有错误都是 `ApiException(String message)`，所以"该不该重试"只能靠字符串匹配。`api_writes.dart` 里有一处 `error.code == 20000`、`comment_store.dart` 里有一处 `message.contains('图片上传失败')`、`error_text.dart` 里有一处 `error.code == 20000`——都是这个问题的症状。

```dart
// core/failure.dart
sealed class Failure {
  final String message;          // 给用户看
  bool get retryable;
  const Failure(this.message);

  factory Failure.from(Object error) => ...;
}

final class NetworkFailure extends Failure     { retryable => true;  }
final class AuthFailure extends Failure        { retryable => false; }
final class RiskControlFailure extends Failure { retryable => false; }  // errno 20000 / 操作频繁
final class ParseDriftFailure extends Failure  { retryable => false; }  // 结构变了
final class BusinessFailure extends Failure    { retryable => false; }
```

落地顺序：
1. `ApiException` 保留（1300 行调用方太多），加一个 `Failure.from(error)` 适配
2. `ErrorView` 和 `PagerTail` 改用 `Failure` 决定要不要给"重试"
3. 把已有的两处字符串匹配换成类型判断

**验收**：`test/failure_test.dart`：喂各种 `Object`，断言 `retryable` 和 `message`。

**风险**：低。纯新增 + 两处调用点。

**落地情况**：

- `core/failure.dart`：`Failure.from(error)` 是唯一判定点。`ApiException` 保留并加了 `kind`（`FailureKind.network` / `parse`），让传输层把已经知道的事直接标出来，不从文案倒推。
- 三处调用点换掉了：`error_text.dart`（未登录给「去登录」，可重试给「重试」，其余只说原因）、`pager_tail.dart`（底部失败页同理）、`comment_store.dart`（去掉 `contains('图片上传失败')`）。
- **`api_writes.dart` 那处数字判断保留了**：它是 `part of 'api.dart'`，而 `failure.dart` 反过来 import `api.dart`，引入会成环。而且数字判断本身不是 P3 要消的问题——要消的是字符串匹配。
- 顺带改了 `comment_store` 的判断逻辑：带图发送失败时，**网络失败不再被说成权限问题**（"发图片评论需要微博的权限"），因为超时说明不了账号权限，那样写会让读者放弃重试。这是原来字符串匹配掩盖的一处误报。
- `ErrorRetry.onRetry` 改成可空，`onRetry == null` 时不画按钮。

---

### P4 · 缓存策略收进 `CachedPage` / `CachedValue` —— **已完成**

**为什么**：现在"要不要缓存"的判断散在 `api.dart` 的 `if (maxId == null) PageCache.write(...)` 里，共 5 处。加一个列表就要再判断一次。

**做什么**：不做完整 Repository 层（那是 P5 的事），只做一个薄封装：

```dart
// core/repository.dart
enum CachePolicy { cacheFirst, networkFirst, networkOnly }

class Repository<T> {
  final String cacheKey;              // 由调用方给，如 'comments-<id>-0'
  final CachePolicy policy;
  final Future<PageResult<T>> Function(String? cursor) fetch;
  final dynamic Function(dynamic) parse;
  final dynamic Function(T) encode;   // 可选：只缓存需要的字段
}
```

**风险**：中。会改 `api.dart` 里 5 处调用点。

**落地情况**：

- 名字叫 `CachedPage<T>` / `CachedValue<T>` 而不是 `Repository<T>`：它不是一层，不负责发请求。`WeiboApi` 照旧建请求、照旧知道哪个游标是第一页；搬过去的只有「存哪、存不存、读回来怎么解析」。
- 两个方法：`accept(data, isFirstPage:)` 存并解析，`read()` 读回来。`networkOnly` 两边都是空操作，所以调用方写法统一。
- **全部五组已迁完**（`comments-*`、`feed`、`profile`、`notify-*`、`conversations-*`），`api_*.dart` 不再直接触碰 `PageCache`（由 `test/arch_guard_test.dart` 守门）。`cachedFeed()` 通过 `readRawCached` + `decode` 避免重复解码。
- **读写域已统一**：读写均走 `Session.instance.cacheScope`。
- `PageCache` 已分级：固定首屏键启动预加载，高基数 `comments-*` 按需懒读并按 LRU 限制内存与磁盘上限（40 份）。
- `read()` 把「存的东西解析不出来」当成没有缓存：页面显示骨架屏再问一次，而不是在没发请求时就显示「加载失败」。
- 测试：`cached_page_test.dart`（13 条：只存第一页、networkOnly 不存、wrap/unwrap、坏缓存当没有、账号隔离、checking 阶段读写一致、`CachedValue`、动态缓存懒读与磁盘上限）。

---

### P5 · `user_page.dart` 的拆分（唯一剩下的"多个概念挤在一起"）

`user_page.dart` 1218 行，里面是：资料头（吸顶 + 封面展开高度）+ 分栏 TabController + 各分栏的懒加载列表 + 三种不同的墙（视频 / 相册 / 音频）。**它不像详情页那样是"多个独立的东西"，但它有三个可以独立的东西**：

1. `_ProfileHeader`（含 `_HeaderLockPhysics`）→ `features/user/profile_header.dart`
2. `_PagedGrid<T>`（视频/相册共用）→ `core/widgets/paged_grid.dart`
3. 分栏的懒加载状态机 → `features/user/profile_tabs.dart`

**只在真的要改用户主页时做。** 如果只是"为了行数"，不值得。

---

## 三、不要做的事（附原因）

这一节比上一节重要。下面每一条都有人会建议做，且都有具体理由不做。

| 不建议 | 原因 |
|---|---|
| **Clean Architecture 全套**（Entity/UseCase/Repository/DataSource 每方法一个类） | 文件数 ×3。UseCase 只在"同一业务动作被多个入口以不同方式触发"时才值得——这个项目里只有"发评论"符合，而它已经有 `CommentStore.send` 了 |
| **BLoC 全站** | 单人维护 133 个文件，Event/State 类会占掉 1/3 代码量，换来的是"状态变化可审计"，而这里没有审计需求 |
| **引入 Riverpod（除非 P2 失败）** | 它解决的三个问题（按 id 订阅、异步三态、auto-dispose）本工程已各自手搓了一份且工作正常。**只有当 P2 的 Entities 也失败时**（说明手搓方案的上限到了），才考虑整体迁移，且不要和单例混用 |
| **GetX** | 隐式依赖 + 全局可变单例，会让现在还算干净的测试变得不可能 |
| **按行数继续拆** | 剩下的长文件大多是"一个自洽的东西"：`parse.dart` 只有解析，`image_viewer_page.dart` 只有一个手势状态机，`models.dart` 只有模型。拆它们只增加跳转成本 |
| **端到端测试为主** | 反爬客户端跑 E2E 会被风控打死。测试重心放解析（P1）和纯逻辑（已有） |
| **多 package 拆分** | 编译变慢、重构变难；等真要复用到第二个 app 再说 |
| **重写 UI 层** | `InfChrome` / `InfLook` 把三套视觉做成接口而不是分支，`buildStatusCard` 收掉了接线——这些是**对的设计**，不该跟着新架构重写 |
| **给 `PagingController` 加 `insert/replace/remove`** | 看着有用，实际上"发完评论就地插入"的需求已经被 `CommentStore.pending` 解决，加这些方法只会让"列表内容从哪来"多一个来源 |
| **把 `api.dart` 传输层也搬进 extension** | extension 之间不能互调私有成员，编译期就失败。已踩过两次，见 `DEVLOG.md` |

### 一条通用的判断

**如果一个改动不影响"同一个决定只有一个落点"，那它大概率不值得做。** 这个项目 1.6.9 里修的 9 个 bug，形状全是"同一个决定写在多处"：三份发送路径、四种刷新策略、六份 footer、四处卡片接线、三处关注状态、五处缓存判断。

---

## 四、当前架构的已知缺点（准确版）

不是"待办"，是"接受了这个代价"。写在这里是为了让接手的人知道**这些是选择，不是疏忽**。

### 1. 全局 Store 没有作用域

`StatusStore.instance` 是进程级的。`of([id])` 缓解了重建问题，但没有解决"什么时候该释放"——`_scoped` 表会在 listener dispose 时自动摘除，但 Store 里的 `_likes` / `_counts` Map 会随会话增长。

**缓解**：这些 Map 的条目很小（2 个 int），一万条约 300KB。真到了要管的时候，加 LRU 即可，不需要改架构。

### 2. 没有依赖注入，测试只能覆盖纯逻辑

`CommentStore.send` 直接调 `WeiboApi.instance`。所以测试能覆盖"发送成功之后的计数和 pending"，覆盖不了"发送本身"。

**这是有意识的取舍**：引入注入点等于引入一个 DI 框架，而 P1 的 fixture 测试能从另一头覆盖同样的风险（解析对不对）。

### 3. 单例初始化顺序靠 `main.dart` 的注释

**已缓解**：`Prefs` 现在在 debug 下断言已初始化（`test/prefs_guard_test.dart`）。其余单例（`PageCache` / `EmojiStore`）仍靠约定，但它们初始化失败的症状很直接（缓存不生效），不像 `Prefs` 那样静默返回默认值。

### 4. `api.dart` 仍是传输层的唯一居所

479 行，含 42 个私有成员（传输、游客身份、解析辅助）。**这是硬约束下的最优解**——`part` + `extension` 拆分要求传输层留在类里，再拆只能拆成"类和它的 mixin"，那会引入新的继承复杂度而无实际收益。

### 5. 三套视觉 = 三份实现

`chrome_classic` / `chrome_glass` / `chrome_liquid` 各自实现 `edgePanel`、`floatingPanel`、`snackBar`……新加一个视觉部件要改三个文件。

**这是抽象的代价，不是缺陷**：三套视觉的差异大到无法用参数化统一（毛玻璃是模糊、液态是折射 + 形变）。抽象层（`InfChrome`）已经保证页面不需要知道有几种。

### 6. `parse.dart` 1655 行

它只做一件事（JSON → 模型），但一件事有 60 个接口的份额。按域拆会变成 `parse_status.dart` / `parse_user.dart` / ...，收益是"改用户解析不用翻 1600 行"，成本是多 8 个文件间的跳转。

**没做，因为 `parse.dart` 的问题不是长度，是它同时是"所有解析"和"解析的唯一测试对象"**。P1 的 fixture 测试建立后，如果确实变难维护，再按域拆。

---

## 五、给新窗口的工作方式建议

1. **先跑一遍**：`flutter analyze`、`flutter test --concurrency=1`、`python3 tools/doc_facts.py --check`，确认起点是干净的（1.7.0 时是 356 条测试全绿）
2. **一次只做一件事**：这份文档里每一节都可以独立完成和回滚
3. **不要用 `git checkout <file>` 局部回滚**：这个项目的改动常常跨多个文件，checkout 单文件会丢掉同文件里的其他改动（1.6.9 时踩过三次，见 `DEVLOG.md`）
4. **改完必须跑三项检查**：`flutter analyze`（要零 error/warning）、`flutter test`、`doc_facts --check`
5. **新增文件后**：跑 `python3 tools/doc_facts.py --update` 或手工补 `CODE_MAP.md` 第 3 节，否则 CI 会红
6. **拆分/重构类改动的验收标准**不是行数，是：**调用方是否零改动**、**测试是否全绿**、**同一个决定是否只剩一个落点**

---

## 六、一页速查

| 现在的做法 | 为什么 | 该不该改 |
|---|---|---|
| 单例 + ChangeNotifier | 加概念的边际成本最低 | 不改（除非 P2 失败） |
| `StatusStore.of([id])` 按 id 订阅 | 避免整屏重建 | 保留，P2 后可能自然消失 |
| Store 存"差量"（`_CountsState` 的 baseline + delta） | 让多个副本对齐 | P2 后会变得不必要 |
| `PagingController` 每次刷出新对象 | 简单、无引用计数 | P2 会改（改为从 Entities 取） |
| `api_<域名>.dart` 的 part + extension | 按凭据分文件，调用方零改动 | 保留 |
| 传输层留在 `WeiboApi` 类里 | extension 调不到别的 extension 的私有成员 | 只能这样 |
| `Prefs` 的 assert 守卫 | 让"忘 init"变成错误而不是默认值 | 保留 |
| `tools/doc_facts.py` | 文档数字不再靠人手改 | 保留，扩展它 |
| 三套 chrome 实现 | 视觉差异无法参数化 | 保留 |
| 没有 UseCase 层 | 这里没有"多入口同一动作" | 不改 |
