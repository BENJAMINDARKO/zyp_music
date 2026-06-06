import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class AppLogger {
  static File? _logFile;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/app_logs.txt');
      
      if (await _logFile!.exists()) {
        final stat = await _logFile!.stat();
        // Clear log file if larger than 5MB
        if (stat.size > 5 * 1024 * 1024) {
          await _logFile!.delete();
        }
      }
      _initialized = true;
      log('AppLogger initialized', name: 'System');
    } catch (e) {
      developer.log('Failed to initialize AppLogger: $e', name: 'System');
    }
  }

  static void log(String message, {String name = 'AppLogger'}) {
    _write(message, name: name);
  }

  /// Warning-level log. Same sink as [log] but prefixes the
  /// line with `[WARN]` so triage can grep for it. The
  /// `dart:developer` level is `WARNING` (900) so the
  /// debug console renders it as a warning-level entry.
  static void warning(String message, {String name = 'AppLogger'}) {
    _write('[WARN] $message', name: name, level: 900);
  }

  static void _write(String message, {required String name, int level = 700}) {
    if (kDebugMode) {
      developer.log(message, name: name, level: level);
      print('[$name] $message');
    }
    if (_logFile != null) {
      try {
        final timestamp = DateTime.now().toIso8601String();
        _logFile!.writeAsStringSync('[$timestamp] [$name] $message\n', mode: FileMode.append);
      } catch (e) {
        if (kDebugMode) {
          developer.log('Failed to write to log file: $e', name: 'System');
          print('[System] Failed to write to log file: $e');
        }
      }
    }
  }

  static File? get logFile => _logFile;
}
