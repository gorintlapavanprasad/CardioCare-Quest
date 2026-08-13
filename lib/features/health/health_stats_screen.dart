// Health Stats - live watch readings (heart rate, steps, etc.).
// Checks the watch every 10 seconds. Pull down to refresh immediately.
// Nothing is saved here; saving happens at game-end.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/health_service.dart';
import '../../core/theme/app_colors.dart';

// Screen widget; state lives in the class below.
class HealthStatsScreen extends StatefulWidget {
  const HealthStatsScreen({super.key});

  @override
  State<HealthStatsScreen> createState() => _HealthStatsScreenState();
}

// State for the screen. Three flags pick which view to show:
// loading, permission denied, or the live monitor.
class _HealthStatsScreenState extends State<HealthStatsScreen>
    with WidgetsBindingObserver {
  HealthSnapshot? _current;
  DateTime? _lastSampledAt;
  Timer? _timer;
  bool _initialLoad = true;
  bool _permissionsDenied = false;
  bool _refreshing = false;

  // Poll interval: 10 s feels live without hammering HealthKit.
  static const Duration _pollInterval = Duration(seconds: 10);

  // After 30 s without a reading the status dot turns amber.
  static const Duration _staleAfter = Duration(seconds: 30);

  // On open: register lifecycle listener and start setup.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  // Pause polling when backgrounded to save battery; resume with a fresh
  // sample on foreground so the numbers aren't stale.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_permissionsDenied) {
        _sample();
        _ensureTimerRunning();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _timer?.cancel();
      _timer = null;
    }
  }

  // On close: clean up the listener and timer.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // First-time setup: ask permission, take a reading, start polling.
  Future<void> _bootstrap() async {
    final granted = await HealthService.instance.requestPermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _permissionsDenied = true;
        _initialLoad = false;
      });
      return;
    }
    await _sample();
    _ensureTimerRunning();
  }

  // Start (or restart) the repeating poll timer.
  void _ensureTimerRunning() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _sample());
  }

  // Fetch one reading and update the UI. fromUserPull shows a spinner.
  Future<void> _sample({bool fromUserPull = false}) async {
    if (fromUserPull && mounted) setState(() => _refreshing = true);
    try {
      final snap = await HealthService.instance.captureSnapshot();
      if (!mounted) return;
      setState(() {
        _current = snap;
        _lastSampledAt = DateTime.now();
        _initialLoad = false;
        _refreshing = false;
      });
    } catch (_) {
      // Keep the last good reading; don't crash on a transient HealthKit error.
      if (!mounted) return;
      setState(() {
        _initialLoad = false;
        _refreshing = false;
      });
    }
  }

  // Re-request permission and retry setup if granted.
  Future<void> _retryPermissions() async {
    setState(() {
      _initialLoad = true;
      _permissionsDenied = false;
    });
    await _bootstrap();
  }

  // Page frame with pull-to-refresh; content chosen by _buildContent.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.title,
        foregroundColor: Colors.white,
        // Override these explicitly: the global appBarTheme sets both to
        // AppColors.title (dark navy), which goes invisible on this dark AppBar.
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        title: const Text('Health Stats'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _sample(fromUserPull: true),
        child: _buildContent(),
      ),
    );
  }

  // Pick which view to show based on the current state.
  Widget _buildContent() {
    if (_initialLoad) return const _LoadingState();
    if (_permissionsDenied) {
      return _PermissionsDeniedState(onRetry: _retryPermissions);
    }
    final snap = _current;
    final hasData = snap != null && snap.hasAnyData;
    if (!hasData) {
      return _NotConnectedState(
        onRetry: () => _sample(fromUserPull: true),
        refreshing: _refreshing,
        lastSampledAt: _lastSampledAt,
      );
    }
    return _LiveMonitor(
      snapshot: snap,
      lastSampledAt: _lastSampledAt!,
      refreshing: _refreshing,
      staleAfter: _staleAfter,
    );
  }
}

// ───────────── States ─────────────

// Spinner shown on first load.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(
          height: 400,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

// Shown when health access was denied. Has an "Allow access" button.
class _PermissionsDeniedState extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionsDeniedState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.lock_outline,
            size: 72, color: AppColors.subtitle),
        const SizedBox(height: 20),
        const Text(
          'Watch access not granted',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.title,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'CardioCare Quest needs permission to read health data '
          'from your Apple Watch. Tap "Allow access" below to open '
          'the system dialog. If the dialog doesn\'t appear, you '
          'previously denied access and need to enable it manually:\n\n'
          'iPhone Settings → Privacy & Security → Health → '
          'CardioCare Quest → turn on the categories you want shared.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: AppColors.subtitle,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Allow access'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 14,
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// Shown when we have permission but no readings are coming through.
class _NotConnectedState extends StatelessWidget {
  final VoidCallback onRetry;
  final bool refreshing;
  final DateTime? lastSampledAt;
  const _NotConnectedState({
    required this.onRetry,
    required this.refreshing,
    required this.lastSampledAt,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.watch_off_outlined,
            size: 72, color: AppColors.subtitle),
        const SizedBox(height: 20),
        const Text(
          'Watch not connected',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.title,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'We can reach the Health app, but no Apple Watch readings '
          'are coming through right now. Common causes:\n\n'
          '• Watch is off-wrist\n'
          '• Watch isn\'t paired with this iPhone\n'
          '• Watch hasn\'t synced recently - try opening the Health '
          'app to force a sync',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: AppColors.subtitle,
            height: 1.55,
          ),
        ),
        if (lastSampledAt != null) ...[
          const SizedBox(height: 18),
          Text(
            'Last checked ${_agoLabel(lastSampledAt!)}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.subtitle,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: refreshing ? null : onRetry,
          icon: refreshing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.refresh),
          label: Text(refreshing ? 'Checking...' : 'Try again'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 14,
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Pull down anywhere on this page to retry as well.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.subtitle,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

// ───────────── Live monitor ─────────────

// Main live view: status badge, heart-rate hero, readings grid, footer.
class _LiveMonitor extends StatelessWidget {
  final HealthSnapshot snapshot;
  final DateTime lastSampledAt;
  final bool refreshing;
  final Duration staleAfter;
  const _LiveMonitor({
    required this.snapshot,
    required this.lastSampledAt,
    required this.refreshing,
    required this.staleAfter,
  });

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(lastSampledAt);
    final isFresh = age < staleAfter;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _LiveBadge(
          isFresh: isFresh,
          age: age,
          refreshing: refreshing,
        ),
        const SizedBox(height: 18),
        _HeartRateHero(snapshot: snapshot),
        const SizedBox(height: 16),
        _MetricGrid(snapshot: snapshot),
        const SizedBox(height: 24),
        const _AutoRefreshFooter(),
      ],
    );
  }
}

// The status pill: green dot = fresh, amber = stale, plus an age label.
class _LiveBadge extends StatelessWidget {
  final bool isFresh;
  final Duration age;
  final bool refreshing;
  const _LiveBadge({
    required this.isFresh,
    required this.age,
    required this.refreshing,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = isFresh
        ? const Color(0xFF5EC962) // green when fresh
        : const Color(0xFFF0A020); // amber when stale
    final ageLabel = age.inSeconds < 5
        ? 'just now'
        : age.inSeconds < 60
            ? '${age.inSeconds}s ago'
            : age.inMinutes < 60
                ? '${age.inMinutes} min ago'
                : '${age.inHours} h ago';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.55),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isFresh
                  ? 'LIVE - updated $ageLabel'
                  : 'STALE - last sample $ageLabel',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.title,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (refreshing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }
}

// Footer note about auto-refresh and pull-to-refresh.
class _AutoRefreshFooter extends StatelessWidget {
  const _AutoRefreshFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        'Auto-updates every 10 seconds while this screen is open. '
        'Pull down for an immediate read.',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.subtitle,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ───────────── Hero + Grid ─────────────

// The big heart-rate card with a plain "what this means" line.
class _HeartRateHero extends StatelessWidget {
  final HealthSnapshot snapshot;
  const _HeartRateHero({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final hr = snapshot.heartRate?.round();
    final hasValue = hr != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B528B), Color(0xFF21918C)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.title.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.favorite, color: Color(0xFFFDE725), size: 22),
              SizedBox(width: 10),
              Text(
                'HEART RATE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasValue ? '$hr' : '-',
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'bpm',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFDE725),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasValue
                ? _hrZone(hr)
                : 'Watch hasn\'t reported a beat in the last 30 minutes.',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // Plain-language label for the current heart rate.
  static String _hrZone(int bpm) {
    if (bpm < 60) return 'Below the typical resting range.';
    if (bpm < 70) return 'In a calm, resting range.';
    if (bpm < 90) return 'Active or alert.';
    if (bpm < 110) return 'Light activity range.';
    return 'Higher than usual - sit and breathe if needed.';
  }
}

// Grid of smaller metric cards (resting HR, HRV, steps, energy, exercise, SpO2).
class _MetricGrid extends StatelessWidget {
  final HealthSnapshot snapshot;
  const _MetricGrid({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.self_improvement_outlined,
                label: 'RESTING HR',
                value: _fmtInt(snapshot.restingHeartRate),
                unit: 'bpm',
                helper: 'Last 24 hours',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.show_chart,
                label: 'HRV',
                value: _fmtInt(snapshot.heartRateVariability),
                unit: 'ms',
                helper: 'Heart rate variability',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.directions_walk,
                label: 'STEPS TODAY',
                value: _fmtIntFromInt(snapshot.stepsToday),
                unit: 'steps',
                helper: 'Since midnight',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.local_fire_department_outlined,
                label: 'ACTIVE ENERGY',
                value: _fmtInt(snapshot.activeEnergyToday),
                unit: 'kcal',
                helper: 'Today',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.timer_outlined,
                label: 'EXERCISE',
                value: _fmtIntFromInt(snapshot.exerciseMinutesToday),
                unit: 'min',
                helper: 'Today',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.air,
                label: 'BLOOD OXYGEN',
                value: _fmtBloodOxygen(snapshot.bloodOxygen),
                unit: '%',
                helper: 'Last 6 hours',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Format a number for display, or "-" if missing.
  static String _fmtInt(double? v) =>
      (v == null || v.isNaN) ? '-' : v.round().toString();
  static String _fmtIntFromInt(int? v) => v == null ? '-' : v.toString();
  static String _fmtBloodOxygen(double? v) {
    if (v == null) return '-';
    // HealthKit gives a fraction (0.0-1.0); some Android builds give 0-100.
    // Scale to percent either way.
    final pct = v <= 1.0 ? v * 100 : v;
    return pct.round().toString();
  }
}

// One metric card: icon, label, value, unit, and a helper line.
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String helper;
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.subtitle,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.title,
                    height: 1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.subtitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            helper,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.subtitle,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────── Helpers ─────────────

// Returns a short "just now / 5 min ago / 2 h ago" label for a past time.
String _agoLabel(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inSeconds < 30) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
