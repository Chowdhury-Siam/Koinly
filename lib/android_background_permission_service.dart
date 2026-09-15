import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only bridge for the system battery-optimization exemption used by
/// Koinly's background update/subscription workers.
class AndroidBackgroundPermissionService {
  const AndroidBackgroundPermissionService._();

  static const MethodChannel _channel = MethodChannel('com.koinly.siam/background_permissions');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens Android's battery-optimization list directly.
  static Future<bool> openBatteryOptimizationSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openBatteryOptimizationSettings') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
