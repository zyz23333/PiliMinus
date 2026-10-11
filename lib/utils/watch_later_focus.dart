import 'package:flutter/foundation.dart';

/// Android always uses the focused flow, including installations with old preferences.
abstract final class WatchLaterFocus {
  static bool get enabled => defaultTargetPlatform == TargetPlatform.android;
}
