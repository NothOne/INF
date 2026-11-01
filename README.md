# INF

一个用 Flutter 写的微博第三方 Android 客户端，通过微博网页版接口访问你自己的账号。

> 个人学习项目，与新浪微博官方无关。请只用它登录你自己的账号，并遵守微博的用户协议。

## 功能

- **首页**：关注流与分组、热门、热搜三页左右滑动；热搜页可切换热搜 / 文娱 / 社会 / 生活 / 体育榜。
- **微博**：正文、评论与楼中楼、转发列表、点赞、图片查看器、视频播放、生成长图。
- **热搜与话题**：榜单排名与标签、导语、主持人、热度与 24 小时阅读趋势、上榜记录、相关搜索，以及综合 / 实时 / 热门 / 视频分流。
- **搜索**：输入时的联想词与相关用户、热搜、历史、微博和用户结果。
- **发布**：发微博、转发、评论与回复，支持多图、@、话题、表情和草稿。
- **消息**：通知、私信与群聊。
- **个人**：关注 / 粉丝、好友、超话、赞过、浏览记录、草稿箱。
- **外观**：经典与毛玻璃两种风格，浅色 / 深色，四种主题色，文字大小可调；全应用的触感反馈。

## 构建

需要 Flutter 3.x 和带 NDK 的 Android SDK。

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

产物在 `build/app/outputs/flutter-apk/app-release.apk`。

release 构建默认用 `android/app/debug.keystore` 签名，这个文件不在仓库里：自己生成一个，或者改 `android/app/build.gradle.kts` 里的 `signingConfig`。

### 鸿蒙 NEXT（手机与平板）

需要 OpenHarmony 版 Flutter（[flutter_flutter](https://gitcode.com/openharmony-tpc/flutter_flutter) 的 `oh-3.47.7-preview` 分支）和 HarmonyOS command-line-tools（`DEVECO_SDK_HOME` 指向其中的 `sdk`，`PATH` 里有 `ohpm`、`hvigorw`、`hdc`）。

```bash
flutter pub get
flutter build hap --release
```

产物在 `ohos/entry/build/default/outputs/default/`。仓库里没有签名配置，构建出来是 `entry-default-unsigned.hap`：用 DevEco Studio 打开 `ohos/`，在 File → Project Structure → Signing Configs 里勾选自动签名后再构建，才能装到设备上。

用官方 Flutter 构建 Android 不受影响：鸿蒙插件只在 `ohos` 平台注册。

## 代码结构

见 [`CODE_MAP.md`](CODE_MAP.md)。

## 测试

```bash
flutter test
```
