
<p align="center">
  <h1 align="center"> <code>video_player_ohos</code> </h1>
</p>





本项目基于 [video_player@2.7.1 ](https://pub.dev/packages/video_player/versions/2.7.1)开发。

## 1. 安装与使用

### 1.1 安装方式

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

<!-- tabs:start -->

#### pubspec.yaml

```yaml
dependencies:
  video_player:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/video_player/video_player
      # ref: video_player-v2.7.2-ohos-1.0.1
      ref: TAG  #   请根据下方TAG版本对应表选择TAG
```

执行命令

```bash
flutter pub get
```

**TAG 版本对应表**

| Flutter 框架版本 | TAG1 | TAG2 | 分支 |
| :--- | :--- | :--- | :--- |
| 3.41 | `-` | `video_player-v2.11.1-ohos-1.0.0` | `br_video_player-v2.11.1_ohos` |
| 3.35 | `-` | `video_player-v2.10.1-ohos-1.0.1` | `br_video_player-v2.10.1_ohos` |
| 3.27 | `video_player-v2.10.0-ohos-1.0.0` | `video_player-v2.10.0-ohos-1.0.1` | `br_video_player-v2.10.0_ohos` |
| 3.22 | `video_player-v2.9.2-ohos-1.0.0` | `video_player-v2.9.2-ohos-1.0.1` | `br_video_player-v2.9.2_ohos` |
| 3.7 | `video_player-v2.7.2-ohos-1.0.0` | `video_player-v2.7.2-ohos-1.0.1` | `master` |

<!-- tabs:end -->

### 1.2 使用案例

使用案例详见 [ohos/example](./example)

## 2. 约束与限制

### 2.1 兼容性

在以下版本中已测试通过

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

### 2.2 权限要求

以下权限中有`system_basic` 权限，而默认的应用权限是 `normal` ，只能使用 `normal` 等级的权限，所以可能会在安装hap包时报错**9568289**，请参考 [文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/bm-tool-V5#ZH-CN_TOPIC_0000001884757326__安装hap时提示code9568289-error-install-failed-due-to-grant-request-permissions-failed) 修改应用等级为 `system_basic`

#### 在 entry 目录下的module.json5中添加权限

打开 `entry/src/main/module.json5`，添加：

```yaml
"requestPermissions": [
  {
    "name": "ohos.permission.INTERNET",
    "reason": "$string:network_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"
      ],
      "when":"inuse"
    }
  },
]
```

#### 在 entry 目录下添加申请以上权限的原因

打开 `entry/src/main/resources/base/element/string.json`，添加：

```
{
  "string": [
    {
      "name": "network_reason",
      "value": "使用网络"
    },
  ]
}
```

## 3. API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

| Name                                          | return value                      | Description                                             | Type     | ohos Support |
| --------------------------------------------- | --------------------------------- | ------------------------------------------------------- | -------- | ------------ |
| init()                                        | Future<void>                      | 初始化平台接口，并释放所有已存在的视频播放器实例        | function | yes          |
| dispose(int textureId)                        | Future<void>                      | 释放指定的视频资源                                      | function | yes          |
| create([DataSource](#DataSource) dataSource)  | Future<int?>                      | 创建一个视频播放器实例，并返回其对应的textureId         | function | yes          |
| setLooping(int textureId, bool looping)       | Future<void>                      | 设置是否循环播放                                        | function | yes          |
| play(int textureId)                           | Future<void>                      | 开始视频播放                                            | function | yes          |
| pause(int textureId)                          | Future<void>                      | 停止视频播放                                            | function | yes          |
| setVolume(int textureId, double volume)       | Future<void>                      | 设置音量，取值范围为0.0到1.0                            | function | yes          |
| setPlaybackSpeed(int textureId, double speed) | Future<void>                      | 设置播放速度。OHOS 平台当前仅支持以下倍速：0.125×、0.25×、0.5×、0.75×、1.0×、1.25×、1.5×、1.75×、2.0×、3.0×                                            | function | yes          |
| seekTo(int textureId, Duration position)      | Future<void>                      | Sets the video position to a [Duration] from the start. | function | yes          |
| getPosition(int textureId)                    | Future<[Duration](#Duration)>     | Gets the video position as [Duration] from the start.   | function | yes          |
| videoEventsFor(int textureId)                 | Stream<[VideoEvent](#VideoEvent)> | 返回一个[[VideoEventType](#VideoEventType)]类型的事件流 | Stream   | yes          |
| setMixWithOthers(bool mixWithOthers)          | Future<void>                      | 设置音频模式，以允许与其他音源混合播放                  | function | yes          |

## 4. 属性

### DataSource 

| Name        | Description                                            | Type                              | ohos Support |
| ----------- | ------------------------------------------------------ | --------------------------------- | ------------ |
| sourceType  | 视频的原始加载方式                                     | [DataSourceType](#DataSourceType) | yes          |
| uri         | 视频文件的URI                                          | String?                           | yes          |
| formatHint  | 将使用此处设置的格式覆盖平台默认的通用文件格式检测机制 | [VideoFormat](#VideoFormat)       | yes          |
| asset       | 资源的名称                                             | String?                           | yes          |
| package     | 加载该资源的包名                                       | String?                           | yes          |
| httpHeaders | HTTP请求头                                             | Map<String, String>               | yes          |

### DataSourceType

| Name                      | Description                            | Type | ohos Support |
| ------------------------- | -------------------------------------- | ---- | ------------ |
| DataSourceType.asset      | 应用资源文件                           | enum | yes          |
| DataSourceType.network    | 网络资源                               | enum | yes          |
| DataSourceType.file       | 本地文件                               | enum | yes          |
| DataSourceType.contentUri | 视频通过contentUri访问，仅适用于Andoid | enum |              |

### VideoFormat

| Name              | Description                   | Type | ohos Support |
| ----------------- | ----------------------------- | ---- | ------------ |
| VideoFormat.dash  | HTTP动态自适应流（MPEG-DASH） | enum | yes          |
| VideoFormat.hls   | HTTP实时流媒体（HLS）         | enum | yes          |
| VideoFormat.ss    | 平滑流媒体                    | enum | yes          |
| VideoFormat.other | 其他格式                      | enum |              |

### VideoEvent

| Name               | Description                              | Type                              | ohos Support |
| ------------------ | ---------------------------------------- | --------------------------------- | ------------ |
| eventType          | 事件的类型                               | [VideoEventType](#VideoEventType) | yes          |
| duration           | 视频的时长                               | Duration?                         | yes          |
| size               | 视频的大小                               | Size?                             | yes          |
| rotationCorrection | 视频需要顺时针旋转的角度，以确保正确显示 | int?                              | yes          |
| buffered           | 视频已缓冲的部分                         | List<DurationRange>?              | yes          |
| isPlaying          | 当前视频是否正在播放                     | bool?                             | yes          |

### VideoEventType

| Name                                | Description          | Type | ohos Support |
| ----------------------------------- | -------------------- | ---- | ------------ |
| VideoEventType.initialized          | 视频初始化完成       | enum | yes          |
| VideoEventType.completed            | 播放结束             | enum | yes          |
| VideoEventType.bufferingUpdate      | 更新缓冲状态         | enum | yes          |
| VideoEventType.bufferingStart       | 视频开始缓冲         | enum | yes          |
| VideoEventType.bufferingEnd         | 视频停止缓冲         | enum | yes          |
| VideoEventType.isPlayingStateUpdate | 视频播放状态发生变化 | enum | yes          |
| VideoEventType.unknown              | 收到未知事件         | enum | yes          |

## 5. 遗留问题

## 6. 开源协议

本项目基于 [The MIT License (MIT)](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/video_player/video_player_ohos/LICENSE) ，请自由地享受和参与开源。



> 模板版本: v0.0.1