import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/health_snapshot.dart';

class PlanApi {
  PlanApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _prefsKey = 'plan_api_base_url';

  /// Optional override: `--dart-define=PLAN_API_BASE=https://...`
  static const String _baseFromDefine = String.fromEnvironment(
    'PLAN_API_BASE',
    defaultValue: '',
  );

  static const String _productionBase =
      'https://fitness-qpfe.onrender.com';

  static String _defaultBase() {
    if (_baseFromDefine.isNotEmpty) return _baseFromDefine;
    if (kReleaseMode) return _productionBase;
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://127.0.0.1:3000';
  }

  static Future<String> getBaseUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_prefsKey) ?? _defaultBase();
  }

  static Future<void> setBaseUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, url.replaceAll(RegExp(r'/$'), ''));
  }

  /// Sends aggregated features only (no raw app names required on server).
  Future<String> fetchTodayPlan(HealthSnapshot snap) async {
    final base = await getBaseUrl();
    final uri = Uri.parse('$base/api/plan');
    http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'features': snap.toJson()}),
          )
          .timeout(const Duration(seconds: 45));
    } on SocketException {
      throw PlanApiException(
        'No internet connection. Check Wi‑Fi or mobile data and try again.',
      );
    } on TimeoutException {
      throw PlanApiException(
        'The request took too long. Try again in a moment.',
      );
    } on HttpException {
      throw PlanApiException(
        'Could not reach the plan service. Try again later.',
      );
    }

    if (res.statusCode != 200) {
      var detail = 'service returned ${res.statusCode}';
      try {
        final errMap = jsonDecode(res.body);
        if (errMap is Map<String, dynamic>) {
          final err = errMap['error'] as String?;
          if (err != null && err.isNotEmpty) detail = err;
        }
      } catch (_) {}
      throw PlanApiException('Could not load your plan ($detail).');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final plan = map['plan'] as String?;
    if (plan == null || plan.isEmpty) {
      throw PlanApiException('No plan was returned. Please try again.');
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
