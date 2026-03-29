import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/health_snapshot.dart';
import 'native_usage_bridge.dart';

class FeatureEngine {
  FeatureEngine();

  final Battery _battery = Battery();
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final List<double> _accelMagnitudes = [];
  static const int _accelSampleCap = 80;

  /// Heuristic scores 0–100. Not medical advice.
  Future<HealthSnapshot> buildSnapshot() async {
    final usage = await NativeUsageBridge.fetchAndroidSignals();

    final nightMin = (usage?['nightScreenMinutes'] as num?)?.round() ?? 0;
    final switches = (usage?['appSwitchCount24h'] as num?)?.round() ?? 0;
    final unique = (usage?['uniqueApps24h'] as num?)?.round() ?? 0;
    final deliveryOpens =
        (usage?['foodDeliveryOpens24h'] as num?)?.round() ?? 0;
    final sleepH = (usage?['sleepHoursEstimate'] as num?)?.toDouble() ?? 0;
    final rawNote = usage?['note'] as String? ?? '';

    final steps = await _safeStepsToday();
    final charging = await _battery.batteryState == BatteryState.charging ||
        await _battery.batteryState == BatteryState.full;

    await _sampleAccelerometerBriefly();
    final varAccel = _variance(_accelMagnitudes);

    final sleepScore = _scoreSleep(sleepH, nightMin);
    final stressScore = _scoreStress(switches, unique, nightMin);
    final energyScore = _scoreEnergy(sleepScore, stressScore, steps, varAccel);

    return HealthSnapshot(
      sleepScore: sleepScore,
      stressScore: stressScore,
      energyScore: energyScore,
      sleepHoursEstimate: sleepH,
      nightScreenMinutes: nightMin,
      appSwitchCount24h: switches,
      uniqueApps24h: unique,
      foodDeliveryOpens24h: deliveryOpens,
      stepsToday: steps,
      movementVariance: varAccel,
      batteryChargingNow: charging,
      rawNote: rawNote,
    );
  }

  void dispose() {
    unawaited(_accelSub?.cancel());
    _accelSub = null;
  }

  int _scoreSleep(double hours, int nightScreenMin) {
    if (hours <= 0 && nightScreenMin == 0) return 50;
    var s = 72;
    if (hours > 0) {
      if (hours < 5.5) s -= 28;
      if (hours < 6.5) s -= 12;
      if (hours > 8.5) s -= 6;
    }
    if (nightScreenMin > 120) s -= 22;
    if (nightScreenMin > 60) s -= 10;
    return s.clamp(15, 95);
  }

  int _scoreStress(int switches, int uniqueApps, int nightMin) {
    var stress = 35;
    stress += (switches / 25).floor() * 4;
    stress += (uniqueApps / 8).floor() * 3;
    stress += (nightMin / 30).floor() * 2;
    return stress.clamp(18, 92);
  }

  int _scoreEnergy(
    int sleep,
    int stress,
    int steps,
    double movementVar,
  ) {
    final movement = (log(1 + movementVar) * 12).clamp(0, 18).toInt();
    final walk = (steps / 2000).floor() * 4;
    var e = 55 + (sleep - 50) ~/ 3 - (stress - 45) ~/ 3 + walk + movement;
    return e.clamp(12, 96);
  }

  static const _kStepsBase = 'pedometer_baseline_steps';
  static const _kStepsDay = 'pedometer_baseline_day';

  Future<int> _safeStepsToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dayKey = _dayKey(DateTime.now());
      final current = await Pedometer.stepCountStream
          .first
          .timeout(const Duration(seconds: 4))
          .then((e) => e.steps);
      final savedDay = prefs.getString(_kStepsDay);
      var base = prefs.getInt(_kStepsBase) ?? current;
      if (savedDay != dayKey) {
        base = current;
        await prefs.setString(_kStepsDay, dayKey);
        await prefs.setInt(_kStepsBase, base);
        return 0;
      }
      if (current < base) {
        await prefs.setInt(_kStepsBase, current);
        return 0;
      }
      return current - base;
    } catch (_) {
      return 0;
    }
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _sampleAccelerometerBriefly() async {
    _accelMagnitudes.clear();
    final completer = Completer<void>();
    _accelSub = accelerometerEventStream().listen((e) {
      final m = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _accelMagnitudes.add(m);
      if (_accelMagnitudes.length >= _accelSampleCap) {
        completer.complete();
      }
    });
    await completer.future.timeout(
      const Duration(milliseconds: 900),
      onTimeout: () {},
    );
    await _accelSub?.cancel();
    _accelSub = null;
  }

  double _variance(List<double> xs) {
    if (xs.isEmpty) return 0;
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    var v = 0.0;
    for (final x in xs) {
      v += (x - mean) * (x - mean);
    }
    return v / xs.length;
  }
}
