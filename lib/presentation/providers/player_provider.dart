import 'package:flutter/foundation.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioRepository _audioRepository;

  PlayerProvider(this._audioRepository);

  Track? _currentTrack;
  List<Track> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  Track? get currentTrack => _currentTrack;
  List<Track> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get error => _error;

  void setQueue(List<Track> tracks, {int startIndex = 0}) {
    _queue = tracks;
    _currentIndex = startIndex;
    notifyListeners();
  }

  Future<void> playTrack(Track track) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentTrack = track;
      final audioUrl = await _audioRepository.getAudioUrl(track);
      await _audioRepository.play(audioUrl);
      _isPlaying = true;
      _duration = await _audioRepository.getDuration();
      _startPositionPolling();
    } catch (e) {
      _error = 'Failed to play: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await playTrack(_queue[index]);
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _audioRepository.pause();
      _isPlaying = false;
    } else {
      await _audioRepository.resume();
      _isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    await _audioRepository.seek(position);
    _position = position;
    notifyListeners();
  }

  Future<void> next() async {
    if (_currentIndex + 1 < _queue.length) {
      await playFromQueue(_currentIndex + 1);
    }
  }

  Future<void> previous() async {
    if (_currentIndex > 0) {
      await playFromQueue(_currentIndex - 1);
    }
  }

  void _startPositionPolling() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isPlaying) return false;
      _position = await _audioRepository.getPosition();
      _duration = await _audioRepository.getDuration();
      notifyListeners();
      return _isPlaying;
    });
  }

  void stop() async {
    await _audioRepository.stop();
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
