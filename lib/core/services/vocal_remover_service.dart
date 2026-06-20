import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class VocalRemoverService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('com.benjamindarko.monochrome/vocal_control');
  
  static final VocalRemoverService _instance = VocalRemoverService._internal();
  factory VocalRemoverService() => _instance;
  
  double _vocalReductionFactor = 0.0;
  bool _isMonoTrack = false;
  
  double get vocalReductionFactor => _vocalReductionFactor;
  bool get isMonoTrack => _isMonoTrack;

  VocalRemoverService._internal() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onMonoTrack') {
        _isMonoTrack = true;
        _vocalReductionFactor = 0.0;
        notifyListeners();
      }
    });
  }

  Future<void> setVocalReduction(double factor) async {
    if (_isMonoTrack && factor > 0) return; // Prevent setting if track is mono
    
    _vocalReductionFactor = factor.clamp(0.0, 1.0);
    notifyListeners();
    
    try {
      await _channel.invokeMethod('setVocalReduction', {'factor': _vocalReductionFactor});
    } on PlatformException catch (e) {
      debugPrint("Failed to set vocal reduction: '${e.message}'.");
    }
  }

  void resetMonoState() {
    if (_isMonoTrack) {
      _isMonoTrack = false;
      notifyListeners();
    }
  }
}
