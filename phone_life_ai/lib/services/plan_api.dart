import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/health_snapshot.dart';

class PlanApi {
  PlanApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _prefsKey = 'plan_api_base_url';

  static Future<String> getBaseUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_prefsKey) ??
        'http://10.0.2.2:3000'; // Android emulator → host
  }

  static Future<void> setBaseUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, url.replaceAll(RegExp(r'/$'), ''));
  }

  /// Sends aggregated features only (no raw app names required on server).
  Future<String> fetchTodayPlan(HealthSnapshot snap) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/api/plan');
    final res = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'features': snap.toJson()}),
        )
        .timeout(const Duration(seconds: 45));

    if (res.statusCode != 200) {
      throw PlanApiException('Server ${res.statusCode}: ${res.body}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final plan = map['plan'] as String?;
    if (plan == null || plan.isEmpty) {
      throw PlanApiException('Empty plan from server');
    }
    return plan;
  }

  void close() => _client.close();
}

class PlanApiException implements Exception {
  PlanApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
