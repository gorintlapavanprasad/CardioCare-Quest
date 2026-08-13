import 'package:get_it/get_it.dart';

import 'package:cardio_care_quest/core/services/activity_logs.dart';
import 'package:cardio_care_quest/core/services/session_manager.dart';

// TelemetryHooks - log "something happened" events for analysis.
// Saves on the phone first, uploads when online. Don't include personal info.
abstract class TelemetryHooks {
  static LoggingService get _logger => GetIt.instance<LoggingService>();

  // Record an event. Returns immediately.
  // Adds the paired session id automatically if one is running.
  static Future<void> logEvent(
    String name, {
    Map<String, dynamic>? parameters,
    String? phone,
    String? userId,
  }) {
    // Add the paired session id if there is one, but don't overwrite a caller-set id.
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
