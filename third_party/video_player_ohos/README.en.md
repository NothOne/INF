

<p align="center">
  <h1 align="center"> <code>video_player_ohos</code> </h1>
</p>




This project is developed based on [video_player@2.7.1](https://pub.dev/packages/video_player/versions/2.7.1).

## 1. Installation and Usage

### 1.1 Installation

Navigate to your project directory and add the following dependency to `pubspec.yaml`:

<!-- tabs:start -->

#### pubspec.yaml

```yaml
dependencies:
  video_player:
    git:
      url: https://gitcode.com/CPF-Flutter/flutter_packages.git
      path: packages/video_player/video_player
      # ref: video_player-v2.7.2-ohos-1.0.1
      ref: TAG  #   Select a TAG according to the TAG version table below
```

Run the command:

```bash
flutter pub get
```

**TAG Version Table**

| Flutter Version | TAG1 | TAG2 | Branch |
| :--- | :--- | :--- | :--- |
| 3.41 | `-` | `video_player-v2.11.1-ohos-1.0.0` | `br_video_player-v2.11.1_ohos` |
| 3.35 | `-` | `video_player-v2.10.1-ohos-1.0.1` | `br_video_player-v2.10.1_ohos` |
| 3.27 | `video_player-v2.10.0-ohos-1.0.0` | `video_player-v2.10.0-ohos-1.0.1` | `br_video_player-v2.10.0_ohos` |
| 3.22 | `video_player-v2.9.2-ohos-1.0.0` | `video_player-v2.9.2-ohos-1.0.1` | `br_video_player-v2.9.2_ohos` |
| 3.7 | `video_player-v2.7.2-ohos-1.0.0` | `video_player-v2.7.2-ohos-1.0.1` | `master` |

<!-- tabs:end -->

### 1.2 Usage

For usage examples, see [ohos/example](./example).

## 2. Constraints

### 2.1 Compatibility

Tested and passed on the following versions:

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;

### 2.2 Permission Requirements

Some of the following permissions require the `system_basic` privilege level, while the default application privilege level is `normal`, which can only use `normal`-level permissions. As a result, you may encounter error **9568289** when installing the HAP package. Please refer to the [documentation](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/bm-tool-V5#EN_TOPIC_0000001884757326__%E5%AE%89%E8%A3%85hap%E6%97%B6%E6%8F%90%E7%A4%BAcode9568289-error-install-failed-due-to-grant-request-permissions-failed) to change the application level to `system_basic`.

#### Add permissions in module.json5 under the entry directory

Open `entry/src/main/module.json5` and add:

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

#### Add the reason for requesting the above permissions under the entry directory

Open `entry/src/main/resources/base/element/string.json` and add:

```
{
  "string": [
    {
      "name": "network_reason",
      "value": "Use network"
    },
  ]
}
```

## 3. API

> [!TIP] An **ohos Support** value of **yes** means the property is supported on the ohos platform; **no** means not supported. The usage method is consistent across platforms, and the behavior is aligned with iOS or Android.

| Name                                          | return value                      | Description                                             | Type     | ohos Support |
| --------------------------------------------- | --------------------------------- | ------------------------------------------------------- | -------- | ------------ |
| init()                                        | Future<void>                      | Initializes the platform interface and releases all existing video player instances.        | function | yes          |
| dispose(int textureId)                        | Future<void>                      | Releases the specified video resource.                                      | function | yes          |
| create([DataSource](#DataSource) dataSource)  | Future<int?>                      | Creates a video player instance and returns its corresponding textureId.         | function | yes          |
| setLooping(int textureId, bool looping)       | Future<void>                      | Sets whether to loop playback.                                        | function | yes          |
| play(int textureId)                           | Future<void>                      | Starts video playback.                                            | function | yes          |
| pause(int textureId)                          | Future<void>                      | Stops video playback.                                            | function | yes          |
| setVolume(int textureId, double volume)       | Future<void>                      | Sets the volume, ranging from 0.0 to 1.0.                            | function | yes          |
| setPlaybackSpeed(int textureId, double speed) | Future<void>                      | Sets the playback speed. The OHOS platform currently supports the following speeds only: 0.125x, 0.25x, 0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 1.75x, 2.0x, 3.0x.                                            | function | yes          |
| seekTo(int textureId, Duration position)      | Future<void>                      | Sets the video position to a [Duration] from the start. | function | yes          |
| getPosition(int textureId)                    | Future<[Duration](#Duration)>     | Gets the video position as [Duration] from the start.   | function | yes          |
| videoEventsFor(int textureId)                 | Stream<[VideoEvent](#VideoEvent)> | Returns an event stream of type [[VideoEventType](#VideoEventType)]. | Stream   | yes          |
| setMixWithOthers(bool mixWithOthers)          | Future<void>                      | Sets the audio mode to allow mixing with other audio sources.                  | function | yes          |

## 4. Properties

### DataSource

| Name        | Description                                            | Type                              | ohos Support |
| ----------- | ------------------------------------------------------ | --------------------------------- | ------------ |
| sourceType  | The original loading method of the video.                                     | [DataSourceType](#DataSourceType) | yes          |
| uri         | The URI of the video file.                                          | String?                           | yes          |
| formatHint  | The format set here overrides the platform's default generic file format detection. | [VideoFormat](#VideoFormat)       | yes          |
| asset       | The name of the resource.                                             | String?                           | yes          |
| package     | The name of the package that loads this resource.                                       | String?                           | yes          |
| httpHeaders | HTTP request headers.                                             | Map<String, String>               | yes          |

### DataSourceType

| Name                      | Description                            | Type | ohos Support |
| ------------------------- | -------------------------------------- | ---- | ------------ |
| DataSourceType.asset      | Application resource file.                           | enum | yes          |
| DataSourceType.network    | Network resource.                               | enum | yes          |
| DataSourceType.file       | Local file.                               | enum | yes          |
| DataSourceType.contentUri | The video is accessed via contentUri, Android only. | enum |              |

### VideoFormat

| Name              | Description                   | Type | ohos Support |
| ----------------- | ----------------------------- | ---- | ------------ |
| VideoFormat.dash  | HTTP Dynamic Adaptive Streaming (MPEG-DASH). | enum | yes          |
| VideoFormat.hls   | HTTP Live Streaming (HLS).         | enum | yes          |
| VideoFormat.ss    | Smooth Streaming.                    | enum | yes          |
| VideoFormat.other | Other formats.                      | enum |              |

### VideoEvent

| Name               | Description                              | Type                              | ohos Support |
| ------------------ | ---------------------------------------- | --------------------------------- | ------------ |
| eventType          | The type of the event.                               | [VideoEventType](#VideoEventType) | yes          |
| duration           | The duration of the video.                               | Duration?                         | yes          |
| size               | The size of the video.                               | Size?                             | yes          |
| rotationCorrection | The angle the video needs to be rotated clockwise to ensure correct display. | int?                              | yes          |
| buffered           | The portion of the video that has been buffered.                         | List<DurationRange>?              | yes          |
| isPlaying          | Whether the video is currently playing.                     | bool?                             | yes          |

### VideoEventType

| Name                                | Description          | Type | ohos Support |
| ----------------------------------- | -------------------- | ---- | ------------ |
| VideoEventType.initialized          | Video initialization completed.       | enum | yes          |
| VideoEventType.completed            | Playback completed.             | enum | yes          |
| VideoEventType.bufferingUpdate      | Updates buffering status.         | enum | yes          |
| VideoEventType.bufferingStart       | Video starts buffering.         | enum | yes          |
| VideoEventType.bufferingEnd         | Video stops buffering.         | enum | yes          |
| VideoEventType.isPlayingStateUpdate | Video playback state changed. | enum | yes          |
| VideoEventType.unknown              | Unknown event received.         | enum | yes          |

## 5. Known Issues

## 6. License

This project is licensed under [The MIT License (MIT)](https://gitcode.com/CPF-Flutter/flutter_packages/blob/master/packages/video_player/video_player_ohos/LICENSE), feel free to use and contribute.



> Template version: v0.0.1
