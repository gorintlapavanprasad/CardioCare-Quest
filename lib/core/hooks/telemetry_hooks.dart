import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/services/activity_logs.dart';

/// Thin façade over [LoggingService] for non-blocking, offline-safe analytics.
///
/// Every event:
///  * Is queued to the Hive `event_queue` immediately (offline-safe).
///  * Syncs to Firestore `events/*` on next connectivity event or 15 s retry.
///  * Increments the dashboard sync badge so researchers can see queue health.
///
/// Use [logEvent] from anywhere — game completion, screen open, error,
/// whatever. The name is the canonical event identifier; `parameters` is a
/// free-form map (avoid PII).
///
/// JS-bridge equivalent: a Twine page can call
///   `window.FlutterBridge.postMessage(JSON.stringify({type:'TELEMETRY',
///                                                    name:'...', params:{}}))`
/// when wired through `TwineGameHost`'s default handler — but in practice
/// the host already calls [logEvent] for the standard lifecycle events
/// (`*_opened`, `*_quest_started`, `*_quest_completed`, `*_closed`).
abstract class TelemetryHooks {
  static LoggingService get _logger => GetIt.instance<LoggingService>();

  /// Queue an event for sync. Returns immediately; does NOT block on Firestore.
  static Future<void> logEvent(
    String name, {
    Map<String, dynamic>? parameters,
    String? phone,
    String? userId,
  }) {
    return _logger.logEvent(
      name,
      parameters: parameters,
      phone: phone,
      userId: userId,
    );
  }
}
