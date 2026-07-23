import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/services/activity_logs.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

// TelemetryHooks - the simple way to record "something happened" events
// (game opened, quest finished, an error, etc.) for later analysis.
//
// It saves right away on the phone (works offline), sends to the cloud when
// there's internet, and updates the dashboard's sync badge. Don't put personal
// info in the event details.
abstract class TelemetryHooks {
  static LoggingService get _logger => GetIt.instance<LoggingService>();

  // Record an event. Returns immediately - doesn't wait on the cloud.
  //
  // If a paired (two-person) session is running, its id is added automatically
  // (unless you already passed one) so every event during co-play links back to
  // that session - the caller doesn't have to think about pairing.
  static Future<void> logEvent(
    String name, {
    Map<String, dynamic>? parameters,
    String? phone,
    String? userId,
  }) {
    // No paired session? Send the details as-is. Otherwise add the session id
    // (but don't overwrite one the caller already set).
    final pairedSessionId = SessionManager.pairedSessionId;
    final enriched = (pairedSessionId == null)
        ? parameters
        : {
            ...?parameters,
            if (!(parameters?.containsKey('pairedSessionId') ?? false))
              'pairedSessionId': pairedSessionId,
          };
    return _logger.logEvent(
      name,
      parameters: enriched,
      phone: phone,
      userId: userId,
    );
  }
}
