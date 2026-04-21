 import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class LoggingService {
  // The name of the local database box where logs are stored
  static const String _boxName = 'app_activity_logs';
  late Box _logBox;
  final Uuid _uuid = const Uuid();

  /// Initializes the local Hive database.
  /// This is called inside main.dart before the app runs.
  Future<void> init() async {
    try {
      await Hive.initFlutter();
      _logBox = await Hive.openBox(_boxName);
      debugPrint('✅ Netgauge LoggingService Initialized Successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize LoggingService: $e');
    }
  }

  /// Logs a specific event with optional parameters.
  Future<void> logEvent(String eventName, {Map<String, dynamic>? parameters}) async {
    try {
      final logEntry = {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'event': eventName,
        'parameters': parameters ?? {},
      };

      // Save to local device storage
      await _logBox.add(logEntry);

      if (kDebugMode) {
        debugPrint('📝 Logged Event: $eventName | Params: $parameters');
      }
    } catch (e) {
      debugPrint('❌ Error writing log: $e');
    }
  }

  /// Retrieves all saved logs (useful for uploading to Firebase in batches)
  Future<List<dynamic>> getAllLogs() async {
    if (!_logBox.isOpen) return [];
    return _logBox.values.toList();
  }

  /// Clears the local logs after a successful upload
  Future<void> clearLogs() async {
    if (_logBox.isOpen) {
      await _logBox.clear();
      debugPrint('🗑️ Local activity logs cleared');
    }
  }
}