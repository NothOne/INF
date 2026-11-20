# Vendored dependencies

本目录收纳的 10 个包分为三类。`analysis_options.yaml` 已将 `third_party/**` 排除在默认 Dart 分析之外（鸿蒙插件源码引用了官方 Flutter SDK 里不存在的 `OhosView` 等符号），但 Android 与鸿蒙构建都会正常编译它们。

## 1. 鸿蒙平台插件（vendored 自 gitcode）

因 GitHub Actions 访问 `gitcode.com` 会收到 HTTP 418，`pubspec.yaml` 不再使用 git 依赖，改为在 commit `30e9855` 直接拷入对应 ref 的包体（删去 `example/`）。

| 目录 | 版本 | 上游仓库 | Pinned ref | 包路径 |
|---|---|---|---|---|
| `path_provider_ohos` | `2.2.1` | `https://gitcode.com/openharmony-tpc/flutter_packages.git` | `bddb2c981fcf826eaf19ed97f55113708aa55727` | `packages/path_provider/path_provider_ohos` |
| `shared_preferences_ohos` | `2.2.0` | `https://gitcode.com/openharmony-tpc/flutter_packages.git` | `bddb2c981fcf826eaf19ed97f55113708aa55727` | `packages/shared_preferences/shared_preferences_ohos` |
| `image_picker_ohos` | `0.8.7+4` | `https://gitcode.com/openharmony-tpc/flutter_packages.git` | `bddb2c981fcf826eaf19ed97f55113708aa55727` | `packages/image_picker/image_picker_ohos` |
| `video_player_ohos` | `1.0.0+2` | `https://gitcode.com/openharmony-tpc/flutter_packages.git` | `bddb2c981fcf826eaf19ed97f55113708aa55727` | `packages/video_player/video_player_ohos` |
| `webview_flutter_ohos` | `3.15.0` | `https://gitcode.com/openharmony-tpc/flutter_packages.git` | `bddb2c981fcf826eaf19ed97f55113708aa55727` | `packages/webview_flutter/webview_flutter_ohos` |
| `sqflite` | `2.4.2+1` | `https://gitcode.com/CPF-Flutter/flutter_sqflite.git` | `9627805b994b89d8abc273a450bfb176142c5860` | `sqflite` |
| `sqflite_ohos` | `2.4.2` | `https://gitcode.com/CPF-Flutter/flutter_sqflite.git` | `9627805b994b89d8abc273a450bfb176142c5860` | `sqflite_ohos` |

本地适配仅 1 处：`webview_flutter_ohos/pubspec.yaml` 中将 `webview_flutter_platform_interface` 的 git 依赖改为 `^2.14.0`（主工程在 `dependency_overrides` 统一锁定版本）。升级上述任意包时，按上表拉取目标 ref 重新覆盖并删去 `example/` 即可。

## 2. 鸿蒙编译兼容转发包

| 目录 | 覆盖版本 | 原因 |
|---|---|---|
| `material_ui` | `1.9.0` | `cached_network_image` 依赖 pub.dev 的 `material_ui`，原包对 `TargetPlatform` 做穷举 `switch`，在新增了 `TargetPlatform.ohos` 的鸿蒙版 Flutter 上编译失败；这里改为直接转发 `package:flutter/material.dart` |
| `cupertino_ui` | `1.1.5` | 同上，直接转发 `package:flutter/cupertino.dart` |

当上游 `material_ui` / `cupertino_ui`（或 `cached_network_image` 移除对其依赖）支持非穷举 `TargetPlatform` 后，即可删除这两个转发包与 `pubspec.yaml` 中对应 `dependency_overrides`。

## 3. 带本地补丁的第三方包

| 目录 | 版本 | 来源 | 补丁说明 |
|---|---|---|---|
| `liquid_glass_widgets` | `1.17.3` | `https://pub.dev/packages/liquid_glass_widgets` | 见 [`liquid_glass_widgets/PATCHES.md`](liquid_glass_widgets/PATCHES.md)（共 2 处本地改动） |
