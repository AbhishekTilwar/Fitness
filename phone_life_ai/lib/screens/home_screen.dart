import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/health_snapshot.dart';
import '../services/feature_engine.dart';
import '../services/native_usage_bridge.dart';
import '../services/plan_api.dart';

enum _ScoreTone { calm, warm, vivid }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FeatureEngine _engine = FeatureEngine();
  final PlanApi _planApi = PlanApi();

  HealthSnapshot? _snap;
  String? _plan;
  String? _error;
  bool _loading = true;
  bool _planLoading = false;

  bool _usageAccessOk = false;
  PermissionStatus _activityStatus = PermissionStatus.denied;
  PermissionStatus _sensorsStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.dispose();
    _planApi.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshScores();
    }
  }

  Future<void> _updatePermissionState() async {
    if (!Platform.isAndroid) {
      if (mounted) {
        setState(() {
          _usageAccessOk = true;
          _activityStatus = PermissionStatus.granted;
          _sensorsStatus = PermissionStatus.granted;
        });
      }
      return;
    }

    final usage = await NativeUsageBridge.hasUsageAccess();
    final act = await Permission.activityRecognition.status;
    final sens = await Permission.sensors.status;

    if (mounted) {
      setState(() {
        _usageAccessOk = usage;
        _activityStatus = act;
        _sensorsStatus = sens;
      });
    }
  }

  Future<void> _init() async {
    await _refreshScores();
  }

  Future<void> _ensureAndroidPermissions() async {
    if (!Platform.isAndroid) return;

    final act = await Permission.activityRecognition.request();
    final sens = await Permission.sensors.request();

    if (mounted) {
      setState(() {
        _activityStatus = act;
        _sensorsStatus = sens;
      });
    }
  }

  Future<void> _refreshScores() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _updatePermissionState();
      if (Platform.isAndroid) {
        await _ensureAndroidPermissions();
        await _updatePermissionState();
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
          _error = _friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('Permission')) {
      return 'A permission is still needed for full insights. Use the cards above to enable access.';
    }
    return 'Something went wrong. Pull to refresh or try again.';
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
          _error = e is PlanApiException ? e.toString() : _friendlyError(e);
          _planLoading = false;
        });
      }
    }
  }

  Future<void> _openUsageSettings() async {
    await HapticFeedback.lightImpact();
    await NativeUsageBridge.openUsageAccessSettings();
  }

  Future<void> _openSensorSettings() async {
    await HapticFeedback.lightImpact();
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.secondaryContainer.withValues(alpha: 0.35),
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshScores,
            color: cs.primary,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverToBoxAdapter(child: _buildHeader(theme)),
                ),
                if (Platform.isAndroid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _permissionsPanel(theme),
                    ),
                  ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  )
                else ...[
                  if (_snap != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _metricsSection(theme, _snap!),
                      ),
                    ),
                  if (_snap?.rawNote.isNotEmpty == true)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _infoChip(theme, _snap!.rawNote),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _planCta(theme),
                    ),
                  ),
                  if (_error != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      sliver: SliverToBoxAdapter(child: _errorBanner(theme)),
                    ),
                  if (_plan != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      sliver: SliverToBoxAdapter(child: _planCard(theme)),
                    )
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                color: cs.secondary,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rhythm',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Built from how you use your phone — not a medical device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _permissionsPanel(ThemeData theme) {
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Insights access',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'We use on-device summaries only. Nothing raw leaves your phone except numbers you approve for your daily plan.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _permissionRow(
              theme,
              icon: Icons.touch_app_outlined,
              title: 'Usage access',
              subtitle: 'Sleep timing, app switches, delivery opens',
              ok: _usageAccessOk,
              onFix: _openUsageSettings,
              fixLabel: 'Open settings',
            ),
            const SizedBox(height: 12),
            _permissionRow(
              theme,
              icon: Icons.directions_walk_outlined,
              title: 'Physical activity',
              subtitle: 'Step count and movement context',
              ok: _activityStatus.isGranted,
              onFix: _activityStatus.isPermanentlyDenied ? _openSensorSettings : _ensureAndroidPermissions,
              fixLabel: _activityStatus.isPermanentlyDenied ? 'App settings' : 'Allow',
            ),
            const SizedBox(height: 12),
            _permissionRow(
              theme,
              icon: Icons.vibration_outlined,
              title: 'Body sensors',
              subtitle: 'Short motion sample for energy estimate',
              ok: _sensorsStatus.isGranted,
              onFix: _sensorsStatus.isPermanentlyDenied ? _openSensorSettings : _ensureAndroidPermissions,
              fixLabel: _sensorsStatus.isPermanentlyDenied ? 'App settings' : 'Allow',
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionRow(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool ok,
    required Future<void> Function() onFix,
    required String fixLabel,
  }) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ok
            ? cs.primary.withValues(alpha: 0.08)
            : cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: ok ? cs.primary : cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (ok)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle, color: cs.primary, size: 22),
            )
          else
            TextButton(
              onPressed: onFix,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(fixLabel),
            ),
        ],
      ),
    );
  }

  Widget _metricsSection(ThemeData theme, HealthSnapshot s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today’s signals',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _scoreRing(
                theme,
                label: 'Sleep',
                score: s.sleepScore,
                caption: '${s.sleepHoursEstimate.toStringAsFixed(1)} h est.',
                tone: _ScoreTone.calm,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _scoreRing(
                theme,
                label: 'Stress',
                score: s.stressScore,
                caption: '${s.appSwitchCount24h} switches',
                tone: _ScoreTone.warm,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _scoreRing(
                theme,
                label: 'Energy',
                score: s.energyScore,
                caption: '${s.stepsToday} steps',
                tone: _ScoreTone.vivid,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _scoreRing(
    ThemeData theme, {
    required String label,
    required int score,
    required String caption,
    required _ScoreTone tone,
  }) {
    final cs = theme.colorScheme;
    final Color accent = switch (tone) {
      _ScoreTone.calm => const Color(0xFF4A90D9),
      _ScoreTone.warm => const Color(0xFFE07C4C),
      _ScoreTone.vivid => const Color(0xFF2BB673),
    };
    final v = (score.clamp(0, 100)) / 100.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              width: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 88,
                    width: 88,
                    child: CircularProgressIndicator(
                      value: v,
                      strokeWidth: 7,
                      backgroundColor: cs.outlineVariant.withValues(alpha: 0.45),
                      color: accent,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Text(
                    '$score',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              caption,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(ThemeData theme, String text) {
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onTertiaryContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCta(ThemeData theme) {
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                cs.primary,
                Color.lerp(cs.primary, cs.tertiary, 0.25)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: _snap == null
                ? null
                : () {
                    if (_planLoading) return;
                    _generatePlan();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _planLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.auto_awesome, size: 22),
            label: Text(
              _planLoading ? 'Creating your plan…' : 'Generate today’s AI plan',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBanner(ThemeData theme) {
    return Material(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.wb_sunny_outlined, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Your plan',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SelectableText(
              _plan!,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.55,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
