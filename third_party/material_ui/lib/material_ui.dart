/// The pub.dev copy of Material switches exhaustively over [TargetPlatform] and fails to compile
/// under the OpenHarmony Flutter fork, which adds `TargetPlatform.ohos`. The SDK's own copy is
/// patched in that fork and identical upstream, so dependencies get that one instead.
library;

export 'package:flutter/material.dart';
