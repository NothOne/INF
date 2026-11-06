# AGENTS.md

INF：用 Flutter 写的微博第三方客户端，走 m.weibo.cn / weibo.com 网页版接口。支持 Android 和鸿蒙 NEXT（手机与平板）。

动手前先读 [`CODE_MAP.md`](CODE_MAP.md)：分层、每个文件管什么、新功能放哪里都在里面。本文件只列必须遵守的规则和常用命令。

## 命令

本机构建用工作区的 Flutter 和缓存，Android SDK 用 `~/Android/Sdk`（已装 NDK 28.2.13676358 和 CMake 3.22.1）。`HOME` 会被改到 `.tools/home`，所以要在改 `HOME` 之前先把 SDK 路径存下来，之后不要再用 `$HOME` 或 `~`：

```bash
SDK=$HOME/Android/Sdk
export ANDROID_HOME=$SDK ANDROID_SDK_ROOT=$SDK
export PUB_CACHE=$PWD/.tools/pub-cache HOME=$PWD/.tools/home \
  GRADLE_USER_HOME=$PWD/.tools/gradle-home3
FLUTTER=../.tools/flutter/bin/flutter

$FLUTTER analyze
$FLUTTER test
$FLUTTER build apk --debug --target-platform android-arm64   # 调试包
$FLUTTER build apk --release --target-platform android-arm64 # 正式包
$SDK/platform-tools/adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Flutter SDK 在工作区外（`../.tools/flutter`），运行时要写它的 `bin/cache`，在沙箱里会报 Permission denied，需要放开沙箱。构建报 `CXX1101` 时，先检查 SDK 的 `ndk/` 下有没有中断下载留下的不完整目录。

鸿蒙用 OpenHarmony 版 Flutter 执行 `flutter build hap --release`，见 `README.md`。

改完代码至少跑 `flutter analyze` 和 `flutter test`，两者都要干净。

## 架构规则

- 只允许上层依赖下层：`features/*` → `core/navigation.dart` → `core/widgets/*` 与 UI 基础 → 状态单例 → `api`/`parse`/`models` → `native`。`core/` 里只有 `navigation.dart` 可以 import `features/*`。
- 功能页之间不互相 import；两个以上页面要用的控件放进 `core/widgets/`。
- 不引入 Provider / Riverpod / Bloc。全局状态是 `Xxx.instance` 单例 + `ChangeNotifier`，页面状态用 `setState`，列表用 `PagingController<T>`。
- 跨页面共享的可变状态（点赞、收藏、关注）放进 Store，乐观更新、失败回滚，参照 `StatusStore`。

## 写代码时的约定

| 要做的事 | 必须这样做 |
|---|---|
| 新接口 | 加在 `WeiboApi` 对应分节，只用 `_get` / `_post` / `_postMultipart` / `_numberedPage`；JSON 解析只写在 `parse.dart`，模型只加在 `models.dart` |
| 打开页面 | 在 `navigation.dart` 加 `openXxx(context, …)`，其他地方只调它，不直接 `Navigator.push` |
| 风格相关的视觉 | 用 `InfChrome.of(context)` / `InfLook.of(context)`，不读 `Prefs.visualStyle`，不自己判断 `glass` |
| 模糊 | 用 `FadeSafeBackdrop`，不直接用 `BackdropFilter`（淡入淡出时会变灰） |
| 网络图片 / WebView | `SmartImage` / `Avatar` / `InfWebView`，不用 `Image.network` 或裸 `WebView` |
| 震动 | 只用 `Haptic.xxx.play()` / `HapticThreshold` |
| 动画时长、曲线 | 用 `InfMotion` 常量 |
| 按宽度调整布局 | 只用 `WindowClass.of(context)` 和 `contentGutter` / `ContentColumn` / `ContentBar` |
| 底部面板、长按菜单 | `showInfSheet` / `showActionSheet` |
| Tab 页加载数据 | 混入 `ShellTabAware`，在 `onTabShown` 里加载，不在 `initState` 里发请求 |
| 原生能力 | 同时改 `MainActivity.kt` 的 `when`、`NativePlugin.ets` 的 `switch` 和 `Native` 静态方法 |
| 新偏好 | `Prefs` 里加字段和 `setXxx()`；影响外观的同步进 `app.dart` 的 `_Appearance` |

- 不依赖单例的纯逻辑要在 `test/` 补测试。
- 改 `parse.dart`、`api.dart`、`status_detail_page.dart`、`image_viewer_page.dart` 这类大文件前先通读相关部分。
- 注释只写代码本身表达不了的约束，跟周围代码的密度和语气保持一致。

## 版本与文档

- 版本号三处一起改：`pubspec.yaml`（`x.y.z+build`）、`ohos/AppScope/app.json5`（`versionName` / `versionCode`）、`lib/core/version.dart`。`test/version_test.dart` 会检查。
- 改了模块职责、新增文件或接口，要同步更新 `CODE_MAP.md` 对应表格。
- 本地的 `DEVLOG.md` 不入库，记录调试过程和实测结论；遇到奇怪的行为（风控、Impeller、vivo 手势、WebView 白屏等）先看它和 `CODE_MAP.md` 第 9 节。

## Git

- 在 `dev` 上开发，发布合到 `main`。提交信息用英文，一句话说清这次改了什么（参照 `git log`）。
- 不提交：`.tools/`、`build/`、APK、`android/local.properties`、`android/app/debug.keystore`、日志、截图录屏、Cookie 文件。
- 不要推送或改动远端，除非用户明确要求。

## 注意

- 这是访问用户自己微博账号的客户端。不要把 Cookie、SUB、token 写进代码、测试或提交里。
- 写接口返回「操作频繁」或 errno 20000 多半是微博风控，不是代码错误，不要为此加重试循环。
