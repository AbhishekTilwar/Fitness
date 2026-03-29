import 'dart:convert';
import 'package:flutter/services.dart';

/// Android-only: aggregates UsageEvents + UsageStats for passive signals.
class NativeUsageBridge {
  static const _channel = MethodChannel('com.phonelifai.lifeopt/usage');

  static Future<Map<String, dynamic>?> fetchAndroidSignals() async {
    try {
      final raw = await _channel.invokeMethod<String>('getSignals');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded;
    } on PlatformException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> openUsageAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('openUsageSettings');
    } catch (_) {}
  }
}
