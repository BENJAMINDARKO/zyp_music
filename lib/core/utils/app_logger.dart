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
    // Print to debug console
    if (kDebugMode) {
      developer.log(message, name: name);
      print('[$name] $message');
    }
    
    // Append to file if initialized
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
