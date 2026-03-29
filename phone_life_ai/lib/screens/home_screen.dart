import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/health_snapshot.dart';
import '../services/feature_engine.dart';
import '../services/native_usage_bridge.dart';
import '../services/plan_api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FeatureEngine _engine = FeatureEngine();
  final PlanApi _planApi = PlanApi();

  HealthSnapshot? _snap;
  String? _plan;
  String? _error;
  bool _loading = true;
  bool _planLoading = false;
  final _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final base = await PlanApi.getBaseUrl();
    _urlCtrl.text = base;
    await _refreshScores();
  }

  Future<void> _refreshScores() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (Platform.isAndroid) {
        await _ensureAndroidPermissions();
      }
      final s = await _engine.buildSnapshot();
      if (mounted) {
        setState(() {
          _snap = s;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _ensureAndroidPermissions() async {
    await Permission.activityRecognition.request();
    await Permission.sensors.request();
  }

  Future<void> _generatePlan() async {
    final snap = _snap;
    if (snap == null) return;
    setState(() {
      _planLoading = true;
      _error = null;
    });
    try {
      final text = await _planApi.fetchTodayPlan(snap);
      if (mounted) {
        setState(() {
          _plan = text;
          _planLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _planLoading = false;
        });
      }
    }
  }

  Future<void> _saveApiUrl() async {
    await PlanApi.setBaseUrl(_urlCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API base URL saved')),
      );
    }
  }

  @override
  void dispose() {
    _engine.dispose();
    _planApi.close();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshScores,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                'Life optimization',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'From phone behavior — not a medical device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (Platform.isAndroid) _usageCard(theme),
              const SizedBox(height: 16),
              _apiCard(theme),
              const SizedBox(height: 20),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_snap != null) ...[
                _scoreRow(theme, _snap!),
                if (_snap!.rawNote.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _snap!.rawNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _planLoading ? null : _generatePlan,
                  icon: _planLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _planLoading ? 'Generating…' : "Today's AI plan",
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (_plan != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Today’s plan',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _plan!,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _usageCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usage access',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'We read aggregated usage on your device to estimate sleep timing, '
              'app switching, and delivery-app opens. Raw events stay on-device; '
              'only summary numbers go to your server for the AI plan.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => NativeUsageBridge.openUsageAccessSettings(),
              child: const Text('Open usage access settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _apiCard(ThemeData theme) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backend URL',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                hintText: 'http://10.0.2.2:3000',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saveApiUrl,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreRow(ThemeData theme, HealthSnapshot s) {
    return Row(
      children: [
        Expanded(
          child: _scoreTile(
            theme,
            'Sleep',
            s.sleepScore,
            '${s.sleepHoursEstimate.toStringAsFixed(1)}h est.',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _scoreTile(
            theme,
            'Stress',
            s.stressScore,
            '${s.appSwitchCount24h} switches',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _scoreTile(
            theme,
            'Energy',
            s.energyScore,
            '${s.stepsToday} steps',
          ),
        ),
      ],
    );
  }

  Widget _scoreTile(
    ThemeData theme,
    String label,
    int score,
    String subtitle,
  ) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$score',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
