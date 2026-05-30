import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioRepository _audioRepository;

  PlayerProvider(this._audioRepository) {
    _skipNextSubscription = _audioRepository.onSkipNextRequested.listen((_) {
      next();
    });
    _skipPrevSubscription = _audioRepository.onSkipPreviousRequested.listen((_) {
      previous();
    });
  }

  Track? _currentTrack;
  List<Track> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  Timer? _pollTimer;
  StreamSubscription? _completionSubscription;
  StreamSubscription? _skipNextSubscription;
  StreamSubscription? _skipPrevSubscription;

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
    _error = null;
    notifyListeners();
  }

  Future<void> playTrack(Track track) async {
    _isLoading = true;
    _error = null;
    _stopPolling();
    _completionSubscription?.cancel();
    notifyListeners();

    try {
      _currentTrack = track;
      final audioUrl = await _audioRepository.getAudioUrl(track);
      await _audioRepository.playTrack(track, audioUrl);
      _isPlaying = true;
      _startPolling();
      _listenForCompletion();
    } catch (e) {
      _error = e.toString();
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
    try {
      if (_isPlaying) {
        await _audioRepository.pause();
        _isPlaying = false;
      } else {
        await _audioRepository.resume();
        _isPlaying = true;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to toggle playback: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> seekTo(Duration position) async {
    try {
      await _audioRepository.seek(position);
      _position = position;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to seek: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> next() async {
    if (_currentIndex + 1 < _queue.length) {
      await playFromQueue(_currentIndex + 1);
    }
  }

  Future<void> previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await playTrack(_queue[_currentIndex]);
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        _position = await _audioRepository.getPosition();
        _duration = await _audioRepository.getDuration();
        notifyListeners();
      } catch (_) {}
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _listenForCompletion() {
    _completionSubscription?.cancel();
    _completionSubscription =
        _audioRepository.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && _queue.isNotEmpty) {
        next();
      }
    });
  }

  Future<void> stop() async {
    _stopPolling();
    _completionSubscription?.cancel();
    await _audioRepository.stop();
    _isPlaying = false;
    _position = Duration.zero;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    _completionSubscription?.cancel();
    _skipNextSubscription?.cancel();
    _skipPrevSubscription?.cancel();
    super.dispose();
  }
}
