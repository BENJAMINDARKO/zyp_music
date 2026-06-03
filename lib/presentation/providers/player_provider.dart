import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/audio_quality.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../service/audio_handler.dart';
import 'download_provider.dart';
import 'settings_provider.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioRepository _audioRepository;
  final DownloadProvider? _downloadProvider;
  final SettingsProvider? _settingsProvider;

  PlayerProvider(
    this._audioRepository, {
    this._downloadProvider,
    this._settingsProvider,
  }) {
    _skipNextSubscription = _audioRepository.onSkipNextRequested.listen((_) {
      next();
    });
    _skipPrevSubscription = _audioRepository.onSkipPreviousRequested.listen((
      _,
    ) {
      previous();
    });
  }

  Track? _currentTrack;
  List<Track> _queue = [];
  List<Track>? _originalQueue;
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _shuffleMode = false;
  bool _isAutoplaying = false;
  repeat.PlaybackRepeatMode _repeatMode = repeat.PlaybackRepeatMode.none;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  String? _error;
  String? _currentPlaylistId;
  StreamSubscription? _completionSubscription;
  StreamSubscription? _skipNextSubscription;
  StreamSubscription? _skipPrevSubscription;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferedPositionSub;

  Timer? _sleepTimer;
  Timer? _sleepTimerTick;
  Duration? _sleepTimerRemaining;

  final List<VoidCallback> _trackChangedListeners = [];

  void addTrackChangedListener(VoidCallback cb) {
    _trackChangedListeners.add(cb);
  }

  void removeTrackChangedListener(VoidCallback cb) {
    _trackChangedListeners.remove(cb);
  }

  static const _recentlyPlayedKey = 'recently_played';
  static const _maxRecent = 20;
  List<Track> _recentlyPlayed = [];

  List<Track> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);

  Future<void> loadRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_recentlyPlayedKey);
    if (json == null) return;
    try {
      final list = jsonDecode(json) as List<dynamic>;
      _recentlyPlayed = list.map((e) {
        final m = e as Map<String, dynamic>;
        return Track(
          id: m['id'] as String,
          title: m['title'] as String,
          author: m['author'] as String?,
          thumbnailUrl: m['thumbnailUrl'] as String?,
          duration: Duration(seconds: m['durationSeconds'] as int? ?? 0),
        );
      }).toList();
    } catch (_) {}
  }

  Future<void> _addToRecentlyPlayed(Track track) async {
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > _maxRecent) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, _maxRecent);
    }
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(
      _recentlyPlayed
          .map(
            (t) => {
              'id': t.id,
              'title': t.title,
              'author': t.author,
              'thumbnailUrl': t.thumbnailUrl,
              'durationSeconds': t.duration.inSeconds,
            },
          )
          .toList(),
    );
    await prefs.setString(_recentlyPlayedKey, json);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) {
      if (_queue.length > 1) {
        final newIdx = index < _queue.length - 1 ? index : index - 1;
        _queue.removeAt(index);
        _currentIndex = newIdx.clamp(0, _queue.length - 1);
        _currentTrack = _queue.isNotEmpty ? _queue[_currentIndex] : null;
      } else {
        _queue.removeAt(index);
        _currentTrack = null;
        _currentIndex = 0;
      }
    } else {
      _queue.removeAt(index);
      if (index < _currentIndex) _currentIndex--;
    }
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else {
      if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
    }
    notifyListeners();
  }

  Track? get currentTrack => _currentTrack;
  List<Track> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isAutoplaying => _isAutoplaying;
  bool get shuffleMode => _shuffleMode;
  repeat.PlaybackRepeatMode get repeatMode => _repeatMode;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get bufferedPosition => _bufferedPosition;
  String? get error => _error;
  String? get currentPlaylistId => _currentPlaylistId;
  bool get isSleepTimerActive => _sleepTimer != null;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;

  void setQueue(List<Track> tracks, {int startIndex = 0, String? playlistId}) {
    _queue = tracks;
    _currentIndex = startIndex;
    _currentPlaylistId = playlistId;
    _originalQueue = null;
    _shuffleMode = false;
    _error = null;
    notifyListeners();
  }

  void toggleShuffle() {
    if (_shuffleMode) {
      if (_originalQueue != null) {
        final currentId = _currentTrack?.id;
        _queue = List.from(_originalQueue!);
        _currentIndex = _queue.indexWhere((t) => t.id == currentId);
        if (_currentIndex < 0) _currentIndex = 0;
      }
      _originalQueue = null;
      _shuffleMode = false;
    } else {
      _originalQueue = List.from(_queue);
      final currentId = _currentTrack?.id;
      final currentIdx = _queue.indexWhere((t) => t.id == currentId);
      if (currentIdx >= 0) {
        final current = _queue.removeAt(currentIdx);
        _queue.shuffle(Random());
        _queue.insert(0, current);
        _currentIndex = 0;
      } else {
        _queue.shuffle(Random());
        _currentIndex = 0;
      }
      _shuffleMode = true;
    }
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode =
        repeat.PlaybackRepeatMode.values[(_repeatMode.index + 1) %
            repeat.PlaybackRepeatMode.values.length];
    notifyListeners();
  }

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimerTick?.cancel();
    _sleepTimerRemaining = duration;
    _sleepTimer = Timer(duration, () {
      _sleepTimerRemaining = Duration.zero;
      _sleepTimer = null;
      _sleepTimerTick?.cancel();
      _sleepTimerTick = null;
      stop();
    });
    _sleepTimerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sleepTimerRemaining != null && _sleepTimerRemaining!.inSeconds > 0) {
        _sleepTimerRemaining =
            _sleepTimerRemaining! - const Duration(seconds: 1);
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimerTick?.cancel();
    _sleepTimer = null;
    _sleepTimerTick = null;
    _sleepTimerRemaining = null;
    notifyListeners();
  }

  Future<void> playTrack(
    Track track, {
    AudioQuality quality = AudioQuality.low,
  }) async {
    _isLoading = true;
    _error = null;
    _currentTrack = track;
    _position = Duration.zero;
    _duration = track.duration;
    _bufferedPosition = Duration.zero;
    _stopPolling();
    _completionSubscription?.cancel();
    notifyListeners();

    try {
      _addToRecentlyPlayed(track);
      final audioUrl = await _audioRepository.getAudioUrl(
        track,
        quality: quality.name,
      );
      await _audioRepository.playTrack(track, audioUrl);
      _isPlaying = true;
      _startPolling();
      _listenForCompletion();
      for (final cb in _trackChangedListeners) {
        cb();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playFromQueue(
    int index, {
    AudioQuality quality = AudioQuality.low,
  }) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await playTrack(_queue[index], quality: quality);
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
    final previous = _position;
    _position = position;
    notifyListeners();
    try {
      await _audioRepository.seek(position);
    } catch (e) {
      _position = previous;
      _error = 'Failed to seek: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> next() async {
    if (_currentIndex + 1 < _queue.length) {
      await playFromQueue(_currentIndex + 1);
    } else if (_repeatMode == repeat.PlaybackRepeatMode.all &&
        _queue.isNotEmpty) {
      await playFromQueue(0);
    } else if (_currentTrack != null) {
      await _fetchAutoplayRecommendations();
    }
  }

  Future<void> previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await playTrack(_queue[_currentIndex]);
    } else {
      await seekTo(Duration.zero);
    }
  }

  void _startPolling() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedPositionSub?.cancel();
    _positionSub = _audioRepository.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    _bufferedPositionSub = _audioRepository.bufferedPositionStream.listen((
      pos,
    ) {
      _bufferedPosition = pos;
      notifyListeners();
    });
    _durationSub = _audioRepository.durationStream.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
  }

  void _stopPolling() {
    _positionSub?.cancel();
    _positionSub = null;
    _durationSub?.cancel();
    _durationSub = null;
    _bufferedPositionSub?.cancel();
    _bufferedPositionSub = null;
  }

  void _listenForCompletion() {
    _completionSubscription?.cancel();
    _completionSubscription = _audioRepository.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed) {
        if (_repeatMode == repeat.PlaybackRepeatMode.one) {
          playFromQueue(_currentIndex);
        } else if (_currentIndex + 1 < _queue.length) {
          next();
        } else if (_repeatMode == repeat.PlaybackRepeatMode.all &&
            _queue.isNotEmpty) {
          playFromQueue(0);
        } else if (_currentTrack != null) {
          _fetchAutoplayRecommendations();
        }
      }
    });
  }

  Future<void> _fetchAutoplayRecommendations() async {
    if (_currentTrack == null) return;
    _isAutoplaying = true;
    notifyListeners();
    try {
      final related = await _audioRepository.getRelatedVideos(_currentTrack!);
      final newTracks =
          related.where((t) => !_queue.any((q) => q.id == t.id)).toList();
      if (newTracks.isEmpty) return;
      _queue.addAll(newTracks);
      notifyListeners();
      await playFromQueue(_currentIndex + 1);
      _preDownloadAutoplay();
    } catch (_) {
    } finally {
      _isAutoplaying = false;
      notifyListeners();
    }
  }

  void _preDownloadAutoplay() {
    final dl = _downloadProvider;
    final settings = _settingsProvider;
    if (dl == null || settings == null) return;
    dl.preDownloadUpcoming(
      _queue,
      _currentIndex,
      '__autoplay__',
      prebufferCount: settings.prebufferCount,
      quality: settings.audioQuality.name,
    );
  }

  Future<void> stop() async {
    _stopPolling();
    _completionSubscription?.cancel();
    await _audioRepository.stop();
    _isPlaying = false;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    notifyListeners();
  }

  Future<void> clearQueue() async {
    _queue = [];
    _currentIndex = 0;
    _currentTrack = null;
    _currentPlaylistId = null;
    _originalQueue = null;
    _shuffleMode = false;
    _audioHandler?.clearQueue();
    await stop();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  MusicAudioHandler? _audioHandler;

  void setAudioHandler(MusicAudioHandler handler) {
    _audioHandler = handler;
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _sleepTimerTick?.cancel();
    _stopPolling();
    _completionSubscription?.cancel();
    _skipNextSubscription?.cancel();
    _skipPrevSubscription?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedPositionSub?.cancel();
    super.dispose();
  }
}
