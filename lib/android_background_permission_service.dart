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

  /// Returns Android's current IANA/Olson time-zone identifier when available.
  /// Scheduled notifications use this to preserve the device's local wall-clock
  /// time instead of silently falling back to UTC.
  static Future<String?> deviceTimeZoneId() async {
    if (!isSupported) return null;
    try {
      final value = await _channel.invokeMethod<String>('deviceTimeZoneId');
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    } on PlatformException {
      return null;
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
