# INF-Flutter Code Map

这份文档讲代码结构：模块怎么分层、各文件管什么、依赖往哪个方向走、新功能应该放在哪里。

规模：`lib/` 共 69 个 Dart 文件，约 1.8 万行。支持 Android 和鸿蒙 NEXT，原生代码各一个文件：`MainActivity.kt` 和 `NativePlugin.ets`。

## 1. 分层总览

```mermaid
flowchart TD
    subgraph App["入口 / 外壳"]
        main["main.dart"] --> app["app.dart · InfApp"]
        app --> shell["features/shell/root_shell.dart"]
    end

    subgraph Features["L5 功能页 features/*"]
        tabs["首页 feed · 通知 notify · 私信 message · 我 profile"]
        pages["详情 detail · 用户 user · 话题 topic · 搜索 search · 编辑 compose · 媒体 media · …"]
    end

    subgraph Router["L4 路由"]
        nav["core/navigation.dart · pushInf / openXxx"]
    end

    subgraph UI["L3 UI 基础"]
        theme["theme · look · motion · container_route"]
        widgets["core/widgets/*"]
    end

    subgraph State["L2 状态 / 服务（单例 + ChangeNotifier）"]
        paging["paging · PagingController"]
        stores["status_store · unread_monitor · image_prefetch · haptics · shell_tabs"]
    end

    subgraph Data["L1 数据"]
        api["api · WeiboApi"] --> parse["parse"] --> models["models"]
        api --> session["session"]
        api --> pagecache["page_cache"]
        prefs["prefs"]
        emoji["emoji"]
    end

    subgraph Platform["L0 平台"]
        native["native · MethodChannel"] --- kt["MainActivity.kt"]
        misc["touches · perf_log · cast(DLNA)"]
    end

    shell --> tabs
    Features --> Router
    Features --> UI
    Features --> State
    Features --> Data
    Router --> Features
    UI --> State
    State --> Data
    Data --> Platform
```

**依赖规则：只允许上层依赖下层。** 路由层是例外：

- `core/navigation.dart` 是唯一允许 import `features/*` 的 core 文件，它就是路由表。
- 任何 UI 层（包括 `core/widgets/*`）都可以调用 `navigation.dart` 来跳页面。

目前没有越层依赖；还剩一处有意保留的循环依赖（`api` ↔ `session`），见第 9 节。

## 2. 启动流程

```
main()
 ├─ Touches.ensureInitialized()           全局指针路由，统计手指数（长按只认单指）
 ├─ PerfLog.start()                       仅 --dart-define=PERF_LOG=true 时生效
 ├─ await Prefs.init() + PageCache.init() 偏好与首屏缓存全部读入内存
 ├─ EmojiStore.init()
 └─ runApp(InfApp)
      └─ 首帧后：Native.requestPeakRefreshRate()
                 → Session.init() → Session.refresh() → UnreadMonitor.start()
      MaterialApp(home: RootShell)
        RootShell：4 个 Tab 用 Stack + Offstage 常驻，1.2s 后预构建其余 Tab
```

`InfApp` 只在外观类偏好（风格、模糊、通透度、主题色、深浅色、字号）变化时重建 `MaterialApp`，其他偏好写入不会触发全局重建。

## 3. 目录与文件

### 3.1 入口

| 文件 | 职责 |
|---|---|
| `lib/main.dart` | 初始化单例，`runApp` |
| `lib/app.dart` | `InfApp`：主题、`InfLook`、本地化、系统栏样式、字号缩放 |

### 3.2 `lib/core/` —— 数据层（L1）

| 文件 | 主要符号 | 职责 |
|---|---|---|
| `models.dart` | `User` `Status` `Media` `Comment` `NotificationItem` `Conversation` `DirectMessage` `UserProfile` `FeedSource` `Draft` `ViewedStatus` `Place` `PageResult<T>` 等 | 纯数据模型和枚举，不依赖任何其他文件 |
| `parse.dart` | `parseWeiboResult` `toStatus` `toUser` `toComment` `parseXxx` `weiboHtmlToText` `parseWeiboTime` `relativeTime` `compactCount` `textOf/idOf/intOf` | 把微博 JSON 转成模型，外加时间、计数、HTML 文本工具。**所有 JSON 字段解析都放这里**。`page_info` 为 `bigPic`（m.weibo.cn）或 `card_info.card_type == '107'`（weibo.com）时是生日祝福、运动会奖牌这类图片横幅，解析成 `LinkCard(banner: true)`，前景透明图叠在背景图上，地址可能为空。`blog_audio`（weibo.com 的语音，时长毫秒；m.weibo.cn 不给，只在正文开头写 `[语音10"]请用最新版手机微博app收听原声<br />`，这行从正文里去掉，解析成没有地址的语音 `AudioClip`）和 `object_type` 含 audio / `type` 44 的 `page_info`（播客，时长秒）解析成 `Status.audio`（`AudioClip`）。其余认不出的卡片（无流的视频、故事、全景……）兜底成 `LinkCard`，地址依次取 `page_url` → `media_info.h5_url` → `card_info.scheme`，只要标题、地址、图片有一样就显示 |
| `api.dart` | `WeiboApi.instance` `ApiException` `LoginRequiredException` | 所有 m.weibo.cn 请求（Dio）。按注释分节：feeds / statuses / notifications and messages / relationships and people / comments / writes / plumbing。拦截器统一注入 UA、XSRF，Cookie 只发给 m.weibo.cn。另有几个免登录的公开接口走 `_getPublic`：热搜榜 `weibo.com/ajax/statuses/hot_band`、文娱/社会/科技/生活/体育/ACG 榜 `weibo.com/ajax/statuses/{entertainment,social,technology,life,sport,acg}`、推荐频道 `weibo.com/ajax/feed/allGroups`（type 1 分组）与频道流 `weibo.com/ajax/feed/hottimeline`（每次随机一批，`max_id` 只当页码）（这些要带 passport `genvisitor2` 换来的游客 SUB/SUBP，统一走 `_asVisitor`，失效时重取一次）、搜索提示 `weibo.com/ajax/side/search`、话题卡片与阅读趋势 `m.s.weibo.com/ajax_topic/detail|trend`（必须带对应 vtopic 页面作 Referer）、`cardUrl` 用 `weibo.com/ajax/statuses/show` 补出横幅卡片的完整地址（m.weibo.cn 给的生日页缺 `mid`，打开是空白）、扫码登录 `passport.weibo.com/sso/v2/qrcode/image|check`（`qrLogin` / `qrLoginStatus`，返回 `retcode` 而不是 `ok`，`_getPublic` 两种都认）、主页分栏（游客：`profile/info` 的 `tabList` 与 `status_total_counter`（转评赞）加 `profile/detail`（IP 属地、星座、注册时间、阳光信用、标签）→ `profileExtras`；`profile/feature?containerid=` 代理 m.weibo.cn 容器，按 `page` 翻页，精选 `231002<uid>_-_HOTMBLOG`、筛选流 `230413<uid>_-_WEIBO_SECOND_PROFILE_WEIBO[_ORI|_PIC|_VIDEO|_ARTICAL]`；视频 `profile/getWaterFallContent`、音频 `profile/getAudioList`（`next_cursor` 0/-1 结束）、相册 `profile/getImageWall`（`since_id` 0 结束））、`audioClip` 用 `statuses/show` 换签名的语音/音频地址和语音转文字。搜索走 m.weibo.cn `100103type=<n>&q=` 容器（`searchStatuses` 第一页顺带返回频道列表，`searchEntries` 取话题类条目） |
| `session.dart` | `Session.instance` `SessionState` `WeiboConfig` | 登录态：从原生 CookieManager 读 m.weibo.cn 的 Cookie，判断 SUB 是否为访客，维护 `uid`、`st`、`xsrf`、`cacheScope` |
| `page_cache.dart` | `PageCache.instance` | 磁盘缓存若干列表的第一页原始 JSON（按账号隔离），启动时全部读入内存 |
| `prefs.dart` | `Prefs.instance` `AccentTheme` `VisualStyle` `HapticLevel` `ImagePreload` `PageMotion` | SharedPreferences 封装：外观、页面动效（`pageMotion`：展开 / 推入，默认推入）、触感档位、搜索历史、草稿、浏览记录、首页来源、推荐频道、热搜榜单顺序（`hotBoards`）、本机屏蔽名单（`blockedUsers`/`isBlocked`，信息流和 `PagedStatusList` 跳过，用户主页不跳过）、表情 |
| `emoji.dart` | `EmojiStore.instance` | 表情短码 → 图片 URL，从接口返回中学习并持久化 |
| `image_url.dart` | `sanitizeImageUrl` `secureUrl` `signedUrlExpired` `sinaimgSized` `weiboImageHeaders` | `signedUrlExpired` 判断视频 CDN 地址的 `Expires` 是否已过；图片 URL 规范化、http→https、sinaimg 尺寸替换、防盗链请求头（Referer 只发给微博自己的域名，B 站等图床带了会 403）。不含 Widget，状态层也可以用 |
| `links.dart` | `linkTargetOf` `LinkTarget` `linkKindOf` `linkKindLabel` `expandShortLink` `unwrapWeiboRedirect` `weiboAppBrowserUrl` `appNameOf` `siteNameOf` `linkInText` | 链接归类：任意 http(s) / `sinaweibo://` 地址 → 微博、用户、话题、超话、t.cn 短链、网页、仅客户端可开（`ClientPageTarget`：m.weibo.cn 的 wbox 小程序页、文章专栏 `a/hot/<cid>_1.html` / `p/232718<cid>`，网页版只显示「打开微博客户端体验」，兜底页经 `sinaweibo://browser?url=` 交给微博客户端）；`appNameOf` / `siteNameOf` 给网页想唤起的 App 和卡片站点起名；`linkInText` 从一段粘贴文字里找出链接；`linkKindOf` 按地址和 `timeline_card_small_*` 图标判断位置/超话/投票/抽奖/群聊/音频（网易云、QQ 音乐、喜马拉雅、小宇宙等）等。纯逻辑，有测试 |

### 3.3 `lib/core/` —— 状态与服务（L2）

| 文件 | 主要符号 | 职责 |
|---|---|---|
| `paging.dart` | `PagingController<T>` | 通用游标分页：首屏 `seed`（缓存）、`refresh`（返回是否成功）、`loadMore`、去重、`fresh` 新增项标记、`onScroll` 触底加载 |
| `status_store.dart` | `StatusStore.instance` | 微博点赞、收藏和评论点赞状态的唯一来源（乐观更新 + 失败回滚；评论点赞走 `api/likes/update|destroy` `type=comment`，和网页版一致），长微博全文缓存（`longText` 同一 id 只请求一次、记最近 50 条、失败不记；`longTextNow` 同步取已到的，供详情页首帧直接用），浏览记录写入，`feedRevision` |
| `unread_monitor.dart` | `UnreadMonitor.instance` | 未读数，每 2 分钟轮询一次，切到通知/私信 Tab 时强制刷新，跟随 `Session` 状态 |
| `image_prefetch.dart` | `ImagePrefetcher.instance` | 列表图片预取，按 `ImagePreload` 偏好和计费网络判断 |
| `haptics.dart` | `Haptic` 枚举 `HapticThreshold` | 触感反馈词汇表，所有震动都走这里 |
| `shell_tabs.dart` | `currentShellTab` `ShellTabAware` `shellBarsVisible` `showShellBars` | 底栏当前 Tab；Tab 页用 mixin 的 `onTabShown` 代替生命周期；`shellBarsVisible` 由 `RootShell` 按滚动写入，底栏和各 Tab 顶栏一起跟随，页面只能 `showShellBars()` 叫回、不能隐藏 |
| `hot_search_store.dart` | `HotSearchStore.instance` | 榜单单例（按 `HotBoard` 分别缓存热搜/文娱/社会/科技/生活/体育/ACG）：首页「热搜」页、搜索页、热搜/话题详情页共用，2 分钟内不重复请求；`lookup()` 按词找回榜单条目（排名、热度、标签，先查热搜榜） |

### 3.4 `lib/core/` —— UI 基础（L3）

| 文件 | 主要符号 | 职责 |
|---|---|---|
| `theme.dart` | `infTheme` `accentColor` | 构造 `ThemeData`，包括 `PageTransitionsTheme`（安卓和鸿蒙都是 fade-forwards，不用预测性返回：下层页面也读 navigator 级的手势标志，会换成手势自己的变换、裁圆角，结束时跳回） |
| `chrome.dart` `chrome_classic.dart` `chrome_glass.dart` `chrome_liquid.dart` | `InfChrome` `ClassicChrome` `GlassChrome` `LiquidChrome` | 三种风格分开实现的界面外壳：顶栏背景、页面底色、底部输入栏 `edgePanel`、悬浮控件 `floatingPanel`、输入面板 `typingSheet`、操作面板、小块底色 `fill`、圆形悬浮按钮 `floatingButton`（发微博）、悬浮胶囊 `floatingCapsule`（信息流「N 条新微博」）、提示条 `snackBar`、顶栏返回键 `actionIconTheme`（进 `theme.dart`）、顶栏右侧按钮组 `barActions`、顶栏下的分区标签 `barTabs`（通知、私信）。页面只调 `InfChrome.of(context)`，不自己判断风格；经典实现全部不透明，模糊和半透明只出现在 `GlassChrome` / `LiquidChrome`。`LiquidChrome` 的悬浮控件用 `liquid_glass_widgets`：悬浮面板是 `GlassContainer`，操作面板是 `GlassSheet`，发微博是白色图标的 56 `GlassButton`，主色透明度随「通透度」在 0.95–0.45 之间变（厚度、折射、高光本来就跟着 `LiquidGlassTheme`），胶囊是主色 0.8 的 `GlassButton.custom`，提示条是深色 0.78 的 `GlassContainer`；顶栏背景、底部输入栏 `edgePanel` 和页面底色都是纯页面色（不加光晕、不渐隐、不模糊），顶栏上的玻璃只有三处：40 的圆形返回 / 关闭键、右侧按钮收进一个玻璃胶囊、通知和私信的分区标签是 38 高的玻璃胶囊，输入面板 `typingSheet` 沿用毛玻璃的实心面板 |
| `look.dart` | `InfLook`（ThemeExtension） `GlassSurface` `GlassBarBackground` `GlassSheet` `lookBarBackground` | 经典 / 毛玻璃风格。控件用 `InfLook.of(context)` 读取，不直接读 `Prefs`。玻璃分三档：静止的顶栏是浅乳白薄霜加细线，内容滑入下方后全霜；悬浮控件（底栏、热搜榜切换胶囊）全霜并用 `lifted` 投影；输入用的面板（评论框）不用玻璃。模糊一律走 `FadeSafeBackdrop`。液态玻璃只在这里存三个滑块值 `refraction` / `liquidClarity` / `liquidShine`（默认都是 0.5），换算成玻璃参数在 `liquid_glass.dart` |
| `liquid_glass.dart` | `liquidGlassTheme` `LiquidGlassTheme` | 液态玻璃用 pub 包 `liquid_glass_widgets`（iOS 26 风格的现成控件，不自己写着色器）。`main.dart` 里 `LiquidGlassWidgets.initialize()` 预载着色器，`wrap(brightnessResolver: Theme.maybeBrightnessOf)` 让玻璃跟随应用的深浅色；`app.dart` 用 `LiquidGlassTheme` 包住整个应用。`liquidGlassTheme` 把设置里的三个滑块换算成 `GlassThemeSettings`，三者都在 0.5 时正好是包里的 `ios27Light` / `ios27Dark`：折射 → 厚度 12–52、折射率 1.1–1.38；通透度 → 玻璃底色透明度（浅 0.85→0.21、深 0.22→0.02）和磨砂 28→0；高光 → 边缘亮线 0–2 倍。`tint` 给发微博、胶囊、提示条换底色。顶栏背景不是玻璃，是纯页面色。用到包里控件的地方：`RootShell` 底栏 `GlassTabBar.bottom`（58 高、和其他风格同样的边距；按下就把光斑移到手指下的那项，松手才真正切换页面）、横屏/平板侧边栏是同一个 `GlassTabBar.bottom` 套 `GlassVerticalBar` 变成竖向（平时只显示图标，按住才展开文字，光斑跟手，松手切换）、详情页「转发 / 评论」和评论排序 `GlassSegmentedControl`、详情页底部写评论栏（悬浮的 `GlassButton.custom` 胶囊加转发、点赞两个圆形 `GlassButton.custom`，评论列表从下面滚过）、`LiquidChrome` 各处、设置页预览。玻璃每帧都要重新折射下方内容，页面转场时下面的页面由 `CoveredSnapshot` 画成一张快照 |
| `link_preview.dart` | `LinkPreviews` `LinkPreview` | 链接预览：解开跳转和 t.cn，微博/用户/话题走接口或直接起名，普通网页读前 192 KB HTML 的 og:title / description / image；微博自家网页不抓（未登录只会拿到登录页），登录墙标题丢掉；按地址缓存 |
| `fade_safe_backdrop.dart` | `FadeSafeBackdrop` `insideFade` | 合成时发现自己处在半透明的 `OpacityLayer` 或任何 `ImageFilterLayer` 里（切换底部标签、页面展开/推入的淡入淡出）就跳过模糊：否则背景模糊采样的是淡入层里的空白，整块玻璃变灰闪一下。`GlassSurface` 用它（液态玻璃的控件自带折射，不经过这里）；新加的模糊不要直接用 `BackdropFilter` |
| `motion.dart` | `InfMotion` `showInfSheet` `showActionSheet` `afterFrame` | 所有时长和曲线常量；底部面板和操作菜单 |
| `container_route.dart` | `ContainerOrigin` `ContainerTransformRoute` | 「展开」动效：页面从点到的控件放大展开（卡片 → 详情对齐正文、楼中楼回复框 → 评论详情、按钮 → 编辑页），没有控件时从手指按下处（`ContainerOrigin.atTouch`）展开；含返回手势驱动。手机上卡片用对齐版（卡片内容和详情正文对齐着放大），`containerAlignProfile(t)` 给出那一刻的透明度 / 模糊 / 位移：整页和下面的真卡片交叉淡入淡出（路由没有遮挡层，半透明的页面露出的就是原卡片，所以收尾时不会出现「详情内容缩在卡片框里、再跳成卡片」），淡出用的 `t` 段贴近卡片一端，淡变期间页面停在卡片上方不动，模糊只在页面不可见和已稳定处为零、交叉过半时已 4σ 以上；平板/侧栏布局信息流列和全屏详情宽度不一样，对不齐，所以只做形状缩放 + 页面淡入并叠一层随透明度减弱的动态模糊（`ImageFiltered`）。对齐只用于打开：页面稳定过之后的返回（按键或手势）一律按不对齐的方式缩回卡片并淡出，本条和转发原博返回一致；返回用 400ms `easeInOutCubic`（打开曲线翻转后几乎全部位移挤在开头 100ms，页面像是瞬间消失） |
| `layout.dart` | `WindowClass` `InfLayout` `contentGutter` `ContentColumn` `ContentBar` `ContentArea` `ShellLayout` | 平板适配：按窗口宽度分紧凑（< 600）/ 中等（600–840）/ 宽屏（≥ 840），叠加设置里的「设备布局」（自动 / 手机 / 平板）。非紧凑时外壳换成侧边栏，内容限宽 `kContentMaxWidth` 居中 |
| `pane.dart` | `DetailPane` `PaneSelected` | 宽屏双栏：首页、通知、私信左边列表、右边独立 Navigator（淡入淡出，空态「选择一条…」）。从列表打开替换右栏，从右栏里打开压栈；返回先退右栏，空了再交给外壳。`PaneSelected` 按 pane key 高亮左栏当前条目。窗口缩到中等时外壳不再构建它，右栏直接关闭 |
| `share.dart` | `statusLink` `shareText` 等 | 分享文案与链接 |
| `media_save.dart` | `saveImagesToGallery` `exportImage` `exportName` `imageTypeOfBytes` | 存图：从图片缓存导出原图（按文件头认 png/gif/webp/jpg），逐张存进相册，实况照片走 `Native.saveMotionPhoto`（合成失败才存静态图，`saveAllMessage` 会说明几张是实况、几张只存了静态图；菜单文字 `saveAllLabel` 标出含几张实况）；查看器和微博长按菜单、详情页「保存全部」共用 |

### 3.5 `lib/core/widgets/` —— 通用控件（L3）

| 文件 | 主要符号 | 用途 |
|---|---|---|
| `status_card.dart` | `StatusCard` `showStatusActions` | 信息流微博卡片（头部、正文、转发块、文章卡、操作栏；头部 IP 不被来源挤掉；正文里「…的微博视频」链接直接播放本条视频）；`showStatusActions` 是长按菜单，详情页右上角共用：（卡片点击走 `_openCard`：横幅或无地址的卡片先 `cardUrl` 补地址，再不行打开兜底页）长图、收藏（`api/statuses/createfav|destroyfav`）、复制、浏览器打开、本机屏蔽此人、投诉（`statusReportLink` 打开网页版举报页）、保存全部图片；正文下显示 `AudioCard`；`saveAllButton`（详情页开）在多图下方放「保存全部 N 张」 |
| `share_sheet.dart` | `showStatusShare` | 详情页分享：最近私信联系人头像（点一下把微博链接发进私信）+ 系统分享、复制链接、长图 |
| `hot_board_bar.dart` | `HotBoardChips` `showHotBoardEditor` `shownBoard` | 热搜榜单切换条（长按拖动排序、+ 打开榜单管理：排序/移除/添加），首页热搜页与搜索页共用，顺序存 `Prefs.hotBoards` |
| `app_logo.dart` | `InfLogo` | 按启动图标路径画的两个渐变环，背景透明（长图左上角） |
| `paged_status_list.dart` | `PagedStatusList` | `PagingController<Status>` + `StatusCard` 的标准列表，带刷新、空态、错误、加载更多。`nested: true` 用于 `NestedScrollView` + 吸顶 Tab（配合 `SliverOverlapAbsorber`），`refreshable: false` 交给外层下拉刷新 |
| `hot_search_row.dart` | `HotSearchRow` `HotLabel` `rankColor` | 热搜榜单行（排名、新/热/沸标签、热度，`detailed` 时加分类与上榜时间） |
| `people_pager_list.dart` | `PeoplePagerList` | 分页用户列表 + 关注按钮 |
| `rich_text.dart` | `RichStatusText` `linkKindIcon` | 正文富文本：@提及、#话题#、链接、表情（`linkColor` 可换链接色，私信里自己发的气泡用）；链接用 `Status.links` 里微博给的文字和类型（地名、超话名、抽奖详情…） |
| `image_grid.dart` | `StatusImageGrid` `thumbnailUrl` | 九宫格，每格包 `ViewerHero` |
| `viewer_hero.dart` | `ViewerHero` `viewerHeroTags` | 所有能点开大图的图片（九宫格、正文/评论里的图和「查看图片」）都用它当 Hero：原图位置不再被 Hero 一直藏到关闭，只隐藏查看器当前所在那张（`ViewerHero.showing`，`openImage` 设、翻页时改、关闭动画结束时清），左右滑过再拖回不会错位；`viewerHeroTags` 从点开的那个 tag 推出每页的 tag（按在全部媒体里的序号，视频不算页但占号） |
| `audio_card.dart` | `AudioCard` | 语音微博和播客/音频卡片的播放条（`video_player` 播音频）：同一时间只播一条；进度条一直显示，播放前拖动就从那里开始；m.weibo.cn 的语音没有地址或地址没签名会被 CDN 拒绝，用 `audioClip` 从 weibo.com 换签名地址和语音转文字（没有地址的语音卡片一出现就去取），起播失败再换一次；语音转文字默认收两行 |
| `smart_image.dart` | `SmartImage` `weiboImageProvider` `isImageInMemory` | 带防盗链 Referer 的网络图片；带签名（`Expires`/`ssig`）的地址去掉查询串作 `cacheKey`，同一头像换了签名仍命中内存和磁盘缓存，显示过就不再淡入；`Avatar` 64 以下统一按 192 解码，各页面共用一份 |
| `comment_sheet.dart` | `showCommentSheet` `CommentSheet` | 评论 / 回复底部面板，首页、详情、通知和 `PagedStatusList` 共用；两种风格下都是实心面板（`InfChrome.typingSheet`） |
| `mention_picker.dart` | `showMentionPicker` `EmojiKeyboard` `EmojiKeyboardSlot` `EmojiPanel` | @ 用户选择器和表情面板，评论面板、编辑页、私信共用 |
| `avatar.dart` / `user_row.dart` | `Avatar` `UserListRow` | 头像、用户行 |
| `refresh.dart` | `InfRefreshIndicator` `nestedScrollRefreshPredicate` | 下拉刷新（触发点触感、失败提示）；`NestedScrollView` 里顶部下拉由内层列表（depth 1）上报，要传 `nestedScrollRefreshPredicate` |
| `shell_top_bar.dart` | `ShellTopBar` `ShellBarBand` | 四个 Tab 页的顶栏：随 `shellBarsVisible` 上滑收起，占位高度不变（页面 `extendBodyBehindAppBar: true`，列表不跳），状态栏那一条始终被背景盖住；`ShellBarBand` 给吸在顶栏下的控件（首页热搜榜单条）跟着走 |
| `transitions.dart` | `StateSwitcher` `RefreshingBar` `AppearIn` `RowListSkeleton` | 状态切换、后台刷新条、入场动画、骨架 |
| `common.dart` | `showMessage` `infSnackBar` `ErrorRetry` `EmptyHint` `CountBadge` `SectionHeader` `SkeletonBox` `StatusListSkeleton` `LoadingFooter` `KeepAlivePage` `formatBytes` | 杂项基础控件。提示条一律 `showMessage` / `infSnackBar`，由 `InfChrome.snackBar` 决定外观（液态是深色玻璃条）；要在 pop 之前建好再交给 messenger |
| `paper.dart` | `PaperBackground` | 页面背景，`RootShell` 外层统一提供，内容由 `InfChrome.backdrop` 决定：经典是纸感渐变，毛玻璃是顶部两团极淡的主色/第三色光晕，液态是纯页面色；页面直接用 `Scaffold` |
| `covered_snapshot.dart` | `CoveredSnapshot` | 整页页面（`RootShell` 和 `pushInf` 打开的每一页）在另一整页打开或关闭期间画成一张快照（Flutter 的 `SnapshotWidget`），正在动的那一页保持实时；每页监听自己路由的动画，所以底部面板、对话框、半透明浮层不触发。液态玻璃在转场时实时折射会让 GPU 每帧约 20ms，快照后回到 1–9ms |
| `web_view.dart` | `InfWebView` `upgradeSinaimgScript` | 统一 WebView（Android 10+ 用 hybrid composition 规避 Impeller 白屏；Android 10 以下引擎走 Skia，用默认纹理模式，hybrid composition 在那里会空白）；`upgradeSinaimgScript` 页面加载后把 `http://*.sinaimg.cn` 图片改成 https（Android 不加载明文图片，生日页的礼物图就是这种） |

### 3.6 `lib/core/` —— 路由（L4）与平台（L0）

| 文件 | 职责 |
|---|---|
| `navigation.dart` | `rootNavigatorKey`、`solveCaptcha`（同时被拒的写操作共用一个验证框）；`pushInf()` 统一 push：传了 `pane` 且处在双栏里 → 进右栏（`DetailPane.open`）；`overlay` → 透明浮层；其余按 `Prefs.pageMotion`：展开 → `ContainerTransformRoute`（用捕获的 `ContainerOrigin`，没有就从手指按下处），推入 → `MaterialPageRoute`（主题里的 fade-forwards，返回是它的倒放），两种不混用，都推在根 Navigator 上。以及所有 `openXxx(context, …)` 入口：能进右栏的（微博详情、楼中楼、用户主页、话题、聊天）显式传 `pane` key，其余（图片、视频、编辑、登录、网页、设置等）始终全屏 |
| `native.dart` | `Native`：MethodChannel `app.inf.flutter/native`，对应 `android/app/src/main/kotlin/app/inf/flutter/MainActivity.kt` 和鸿蒙的 `ohos/entry/src/main/ets/plugins/NativePlugin.ets`；`Native.isOhos` 判断鸿蒙 |
| `touches.dart` | 全局手指计数、最近一次按下的位置（`lastDown`） |
| `perf_log.dart` | 帧耗时统计（编译开关） |
| `version.dart` | `appVersion`，设置页和「我的」显示用；须与 `pubspec.yaml`、`ohos/AppScope/app.json5` 一致，`test/version_test.dart` 检查 |
| `cast.dart` | 纯 Dart 的 SSDP 发现 + DLNA AVTransport 投屏 |

原生方法一览（`Native` ↔ `MainActivity`）：`getCookies` `setCookie` `clearCookies` `clearAuthCookies` `userAgent` `openUrl`（可指定包名，`sinaweibo://` 指定 `com.sina.weibo`，避免被其他声明了该 scheme 的 App 截走；支持 `intent:` 地址）`takeLink`（取外部传入的 `inf://open?url=<编码后的地址>`，`RootShell` 启动和回到前台时读取并 `openLink`）`sdkInt`（启动时 `Native.init()` 读入 `Native.sdkInt`，鸿蒙为 null）`isMetered` `isPipAvailable` `enterPip` `saveImage` `saveVideo` `peakRefreshRate` `haptic`。新增原生能力时两边同时改，Dart 侧只通过 `Native` 调用。

鸿蒙端（`NativePlugin.ets`）实现同一组方法，另加 `share`（share_plus 没有鸿蒙实现，`share.dart` 在鸿蒙上走它）。差异：画中画、`setVolume` 返回 false，`peakRefreshRate` 返回 null；存图存视频走系统保存弹窗，每次需用户确认；实况照片只存静态图。

鸿蒙相关的其余部分：`ohos/` 是鸿蒙工程（`EntryAbility.ets` 注册 `NativePlugin` 并允许第三方 Cookie）；`pubspec.yaml` 里的 `*_ohos` 依赖是各插件的鸿蒙实现；`third_party/material_ui` 与 `third_party/cupertino_ui` 是覆盖 pub.dev 同名包的转发包，因为那两个包对 `TargetPlatform` 做穷举 switch，在多了 `ohos` 的鸿蒙版 Flutter 上编不过。`third_party/liquid_glass_widgets` 是 pub.dev 1.17.0 的副本，只改了侧栏按下时镜片的尺寸（`_lensSize`，原生是圆形，改成竖向胶囊，长边顺着上下拖动的方向）；升级时重新复制再补这一处。主题里鸿蒙的页面转场按名字匹配 `TargetPlatform.ohos`，所以官方 Flutter 也能编译。

### 3.7 `lib/features/` —— 功能页（L5）

| 目录 | 入口 | 说明 | 打开方式 |
|---|---|---|---|
| `shell/` | `RootShell` | 底栏 4 Tab、fade-through、底栏随滚动收起、发微博按钮；宽窗口或手机横屏下换成左侧 `_SideRail`（Tab 区域用 GlobalKey 保留，切换布局不重建；Tab 区域的 `MediaQuery` 要在 `Scaffold` 下面读，否则键盘高度会被各 Tab 的 `Scaffold` 再扣一次，平板分屏左半边整个缩没） | `InfApp.home` |
| `feed/` | `FeedPage` + `FeedController` | 首页顶栏三个等宽标签、推荐居中，三页可左右滑动，每页再点一次标题打开选择器：关注（全部关注流，切分组）、推荐（默认「热门」= 登录账号的 m.weibo.cn 102803 个性化流；「推荐」及其余频道 = weibo.com 游客推荐频道；`recommend_channels_sheet.dart` 选频道）、热搜（`HotBoardChips` 切榜单，标题处打开榜单管理）；底栏「首页」单击作用于当前页（回顶/刷新） | Tab 0 |
| `notify/` | `NotifyPage` | 通知四个子 Tab | Tab 1 |
| `captcha/` | `showCaptchaDialog` | 微博安全验证：写接口返回 `error_type: captcha` 时，用 m.weibo.cn 自己的 `validate-loader` + 网易易盾弹出拼图，完成后把返回字段并进原请求重发一次；关闭则操作不执行 | `solveCaptcha`（`WeiboApi.captchaSolver`，经 `rootNavigatorKey` 弹在当前页面上） |
| `place/` | `showPlaceSheet` | 地点面板：图、名称、到访统计、地址（可复制），地点详情网页、用地图导航（`geo:` 交给地图 App，没有就开高德网页） | `openPlace`（正文里的位置链接、卡片位置行） |
| `message/` | `MessagePage` `ChatPage` `chat_link_sheet` | 私信列表、单聊/群聊、私信链接面板；消息里的链接在气泡下显示预览卡（`LinkPreviews`）；消息列表倒序（offset 0 是最新），首帧就停在底部；按会话在内存里记住最近消息，再次进入直接显示；对方头像用列表传进来的那张（`openChat(avatar:)`） | Tab 2 / `openChat` |
| `profile/` | `ProfilePage` | 「我」、菜单入口（我的微博 → 自己的 `UserPage`、草稿箱、浏览记录、赞过……）、退出 | Tab 3 |
| `detail/` | `StatusDetailPage` `CommentTile` `showCommentActions` `CommentFloorPage` | 微博详情、评论/转发切换（点标签或左右滑）、评论按热度/按时间（`comments/hotflow` 的 `max_id_type` 0/1）、楼中楼（顶部显示主评论，取自 `hotFlowChild` 的 `rootComment`）；评论下的回复预览和转发列表里，图片显示为「查看图片」，点开直接看图 | `openStatus` |
| `compose/` | `ComposePage` | 发博/转发、多图、草稿 | `openCompose` |
| `user/` | `UserPage` | 他人主页（「我」页的「我的微博」也进这里）：整个资料头放在 `SliverAppBar` 里，封面顶到状态栏下，分栏是它的 `bottom`；资料头高度量出来再定展开高度。上滑收起后 `_HeaderLockPhysics` 锁住外层滚动，微博列表滑回顶部也不再展开（余量交给内层作下拉刷新），点顶栏才展开。资料头显示获赞、转评赞和 `ProfileExtras.facts`。分栏按 `ProfileTab`（`profileExtras` 返回的 `tabList`）增减。微博（全部 / 原创 / 图片 / 视频筛选，`ProfilePostFilter`）、精选、音频、文章用 `PagedStatusList`；视频是封面网格（点按播放，长按开微博）；相册是图片墙（点按进查看器，长按开原微博）。各分栏第一次显示时才加载 | `openUser` |
| `topic/` | `HotTopicPage` `TopicPage` `SuperTopicsPage` | 热搜/话题详情：头部只留排名与标签、两行导语、主持人、一行热度摘要（点开「热点数据」面板看热度/阅读/讨论、24 小时阅读趋势、上榜记录、贡献者/媒体）、单行相关搜索、相关用户和「参与讨论/全站搜索」，下方吸顶「综合/实时/热门/视频」；`TopicPage` 用于赞过、container 流和话题内关键词搜索 | `openTopic` `openHotTopic` `openLiked` `openTopicFeed` `openSuperTopics` |
| `search/` | `SearchPage` | 搜索框里粘贴微博/网页链接直接打开；输入时的搜索提示（联想词 + 用户）、热搜（与首页同款榜单切换条和详细行）、历史（默认折叠成两行，可展开，清空前确认）、结果是一行可横滑的频道 Tab（`SearchChannel`：综合 / 实时 / 热门 / 用户 / 视频 / 图片 / 关注 / 文章 / 话题 / 超话，`100103type=<n>`；第一页 `cardlistInfo` 的 `channel_list` 到了就换成微博给的列表），按 `SearchResultKind` 显示微博、用户或话题类条目（`SearchEntry`） | `openSearch` |
| `relations/` | `RelationsPage` | 关注/粉丝 | `openRelations` |
| `friends/` | `FriendsPage` | 好友 | `openFriends` |
| `history/` | `DraftsPage` `ViewedPage` | 草稿箱、浏览记录 | `openDrafts` `openViewed` |
| `media/` | `ImageViewerPage` `VideoPage` `cast_sheet` `video_surface` | 图片查看器（Hero、缩放、拖动关闭；`viewerPictureBox` 定布局：比竖屏还细长的才算长图，在屏幕短边宽的一栏里滚动，平板横屏不会放大到整屏宽，其余图片完整放进屏幕；长按菜单可保存全部；实况照片带声音播放；`viewerDecodeWidth` 让超过 GPU 最大纹理（鸿蒙平板 8192）的长图按比例缩窄解码，Impeller 超限时会把宽高各自截断，长图被压扁成放大、裁边、发糊）、视频（PiP、下载、投屏；`openVideo` 带上 `statusId`，地址签名过期或起播失败时重新取一次这条微博换新地址，只换一次）；`startVideo` 先走纹理，起不来就换 SurfaceView（`VideoViewType.platformView`）重建，并记进 `Prefs.videoSurfaceView`（华为海思解码器在纹理的 ImageReader 上分配不了缓冲区） | `openImage` `openVideo` |
| `longimage/` | `LongImagePage` | 长图截图分享：底色随主题 `surface`、无外边距，`InfLogo` 放在底部「长图由 INF 生成」左边 | `openLongImage` |
| `login/` | `LoginPage` `QrLoginPanel` | 登录方式选择：扫码 / 本机微博 App 确认（`qr_login_panel.dart`，确认后把 passport 给的跳转地址交给 WebView 走完 SSO 链）；短信验证码、账号密码、网页登录都在官方登录页的 WebView 里完成，前两者加载后用 JS 点开对应 Tab | `openLogin` |
| `settings/` | `SettingsPage` | 外观、毛玻璃调节、页面动效、触感、缓存 | `openSettings` |
| `web/` | `WebPage` `LinkFallbackPage` | 通用网页（http 升级 https、加载失败页、用浏览器打开；左上角返回 + 关闭，返回后 2 秒内又跳回刚离开的地址视为跳转页回弹，直接关闭；页内 `sinaweibo://` 的微博/用户/话题跳回 INF，其他 App 跳转弹出「网页想打开「X」」由用户决定；标题栏显示网页标题和域名）；兜底页给只有微博客户端能开的链接和找不到地址的卡片：说明原因，提供在微博客户端打开 / 浏览器打开 / 复制链接 | `openLink`（所有正文链接、卡片的统一入口）`openWeb` `openLinkFallback` |

功能页之间现有的直接依赖（除 `RootShell` 引用 4 个 Tab 外）：

- `history/drafts_page` → `compose/compose_page.dart`（重发草稿）
- `media/video_page` → `media/cast_sheet.dart`（同模块）

被两个以上功能页用到的组件应放进 `core/widgets/`，不要让功能页之间互相 import。

## 4. 状态管理方式

项目**没有使用 Provider / Riverpod / Bloc**。如果以后要引入，需要整体迁移，不要和单例模式混用。约定如下：

- **全局状态 = 单例 + `ChangeNotifier`**：`Session` `Prefs` `StatusStore` `UnreadMonitor` `EmojiStore` 都是 `Xxx.instance`；`WeiboApi` `PageCache` `ImagePrefetcher` 也是单例，但不通知监听者。
- **页面状态 = `StatefulWidget` + `setState`**；页面逻辑较复杂时拆出页面级 `ChangeNotifier` 控制器（目前只有 `FeedController`）。
- **列表 = `PagingController<T>`**，由页面 `State` 创建和 `dispose`，用 `AnimatedBuilder` / `ListenableBuilder` 监听。
- **跨页面共享的可变实体状态放进 Store**：例如点赞状态只存在 `StatusStore`，列表渲染时用 `StatusStore.instance.apply(status)` 取当前值。
- **Tab 页**不依赖 `initState` 发请求，而是混入 `ShellTabAware`，在 `onTabShown(first:)` 里加载，因为 Tab 是预构建并常驻的。

## 5. 数据流（以一个列表为例）

```
Widget  ──创建──▶ PagingController<T>(fetch: (cursor) => WeiboApi.instance.xxx(cursor), id: …)
  ▲                    │ seed(WeiboApi.instance.cachedXxx())   ← PageCache 首屏
  │                    │ refresh() / loadMore()
  │                    ▼
  │             WeiboApi._get/_post ── Dio 拦截器(UA/Cookie/XSRF，取自 Session)
  │                    │
  │                    ▼  原始 JSON → parseWeiboResult → parseXxx/toXxx (parse.dart)
  │                    ▼
  └──notifyListeners── PageResult<T>(items, nextCursor)        (models.dart)
```

错误约定：未登录抛 `LoginRequiredException`（`Session.onLoginRequired()` 先用 `api/config` 确认确实没登录，再切到未登录态；返回体不是 JSON 时 `unparsable` 为真，本地仍有登录 SUB 就只算暂时连不上），业务错误抛 `ApiException(message)`，UI 用 `showMessage` / `ErrorRetry` 展示。

## 6. 新功能放在哪里

| 要做的事 | 放在哪里 / 怎么做 |
|---|---|
| 新接口 | 在 `WeiboApi` 对应分节里加方法，只能用 `_get` / `_post` / `_postMultipart` / `_numberedPage`；JSON 解析写到 `parse.dart`；需要新模型就加到 `models.dart` |
| 列表首屏秒开 | 在 API 方法里 `cursor == null` 时 `PageCache.instance.write(session.uid, key, data)`，再提供 `cachedXxx()`，页面里 `pager.seed(...)` |
| 新页面 | `features/<模块>/<名字>_page.dart`；在 `navigation.dart` 里加 `openXxx(context, …)`，**其他地方只调 `openXxx`，不要直接 `Navigator.push`** |
| 新底栏 Tab 的子页面 | 混入 `ShellTabAware`，在 `onTabShown` 里加载 |
| 微博列表 | 直接用 `PagedStatusList(pager: …)`；用户列表用 `PeoplePagerList` |
| 页面顶栏 | `Scaffold(extendBodyBehindAppBar: InfLook.of(context).glass, appBar: AppBar(flexibleSpace: lookBarBackground(context), …))`，列表顶部留 `MediaQuery.paddingOf(context).top`，与现有页面保持一致 |
| 底部面板 / 长按菜单 | `showInfSheet` / `showActionSheet`（`motion.dart`），自动适配毛玻璃 |
| 动画时长、曲线 | 用 `InfMotion` 的常量，不要在页面里写魔法数字 |
| 卡片/按钮展开成新页面 | 点击时先 `ContainerOrigin.capture(context, …)`，紧接着调用 `openXxx` |
| 震动 | 只用 `Haptic.xxx.play()` / `HapticThreshold`，不要直接调 `HapticFeedback` |
| 新偏好项 | `Prefs` 里加字段和 `setXxx()`；如果影响外观，同步加进 `app.dart` 的 `_Appearance` |
| 风格相关的视觉 | 读 `InfLook.of(context)`，不要直接读 `Prefs.visualStyle` |
| 按屏幕宽度调整布局 | 只用 `WindowClass.of(context)`，不要自己比较 `MediaQuery.sizeOf(context).width`（它已经算上「设备布局」偏好）。滚动列表把 `contentGutter(context)` 加进列表自己的左右 padding（两侧空白仍可滑动）；不滚动的头部、Tab 条、底部输入栏包 `ContentColumn`，`AppBar.bottom` 用 `ContentBar` |
| Tab 页列表底部留白 | `ShellLayout.clearance(context, 底栏高度)`：有底栏时让出底栏，侧边栏布局下只留 24 |
| 网络图片 | `SmartImage` / `Avatar`（带防盗链头），不要直接用 `Image.network` |
| WebView | `InfWebView` |
| 跨页面同步的状态（如收藏、关注） | 仿照 `StatusStore` 建 Store：乐观更新、失败回滚、触感 |
| 原生能力 | `MainActivity.kt` 的 `when` 分支 + `NativePlugin.ets` 的 `switch` 分支 + `Native` 静态方法 |
| 测试 | `test/`：`widget_test.dart` 测解析，`paging_test.dart` 测分页，`layout_test.dart` 测宽度分档与内容留白。不依赖单例的纯逻辑都应该补测试 |

## 7. 持久化一览

| 存储 | 位置 | 内容 |
|---|---|---|
| SharedPreferences | `Prefs` | 外观、触感、首页来源、搜索历史、草稿、浏览记录（最多 60 条）、表情、上次 uid、欢迎页 |
| 文件 `app_support/page_cache/*.json` | `PageCache` | `feed` `profile` `notify-<kind>` `conversations-<strangers>` 的第一页原始 JSON，按 `Session.cacheScope` 隔离 |
| 图片缓存 | `flutter_cache_manager` | 由 `SmartImage` / `ImagePrefetcher` 使用，设置页可清理 |
| Cookie | Android `CookieManager` | 与登录 WebView 共享，经 `Native` 读写 |

## 8. 体量较大的文件（改动前先读）

| 文件 | 行数 | 备注 |
|---|---|---|
| `features/detail/status_detail_page.dart` | ~1740 | 详情 + 评论/转发两个列表 + 交叉淡化 |
| `core/parse.dart` | ~1210 | 所有解析 |
| `features/media/image_viewer_page.dart` | ~1100 | 手势状态机 |
| `core/api.dart` | ~675 | 所有接口 |
| `features/compose/compose_page.dart` / `core/widgets/status_card.dart` | ~590 | |

## 9. 有意保留的结构

1. `core/api.dart` 和 `core/session.dart` 互相 import：`WeiboApi` 从 `Session` 取 Cookie，`Session.refresh()` 又调用 `WeiboApi.config()` 检查登录。Dart 允许循环 import，两者都是懒加载的单例，不会有初始化顺序问题。拆开需要引入接口或回调注入，复杂度大于收益，所以保留。
2. `StatusStore.toggleLike` 里直接调用 `Haptic`，状态层带了 UI 副作用。所有点赞入口都需要同样的手感，放在一处比每个调用方各写一遍更不容易漏。
