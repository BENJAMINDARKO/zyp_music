import 'package:flutter/foundation.dart';

class MiniplayerVisibilityProvider extends ChangeNotifier {
  bool _isVisible = true;

  bool get isVisible => _isVisible;

  void hide() {
    if (_isVisible) {
      _isVisible = false;
      Future.microtask(notifyListeners);
    }
  }

  void show() {
    if (!_isVisible) {
      _isVisible = true;
      Future.microtask(notifyListeners);
    }
  }
}
