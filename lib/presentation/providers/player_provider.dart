import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/audio_quality.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../../core/services/hybrid_cache_service.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../service/audio_handler.dart';
import '../../services/playback_session.dart';
import 'settings_provider.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioRepository _audioRepository;
  final SettingsProvider _settingsProvider;
  final HybridCacheService _hybridCache;
  late final FallbackEngine _fallbackEngine;

  PlayerProvider(
    this._audioRepository,
    this._settingsProvider,
    this._hybridCache,
  ) {
    _fallbackEngine = FallbackEngine();

    _settingsProvider.addListener(() {
      PlaybackSession().clear();
    });

    _skipNextSubscription = _audioRepository.onSkipNextRequested.listen((_) {
      next();
    });
    _skipPrevSubscription = _audioRepository.onSkipPreviousRequested.listen((_) {
      previous();
    });
    // Drive the Hive-driven preload loop off the existing track-changed hook.
    addTrackChangedListener(_onTrackChangedForPreload);
    // Load recently played tracks on startup
    loadRecentlyPlayed().then((_) {
      if (_recentlyPlayed.isNotEmpty) {
        notifyListeners();
      }
    });
  }

  Track? _currentTrack;
  List<Track> _queue = [];
  List<Track>? _originalQueue;
  int _currentIndex = 0;
  bool _isPlaying = false;
  ProcessingState _processingState = ProcessingState.idle;
  bool _isLoading = false;
  bool _shuffleMode = false;
  repeat.PlaybackRepeatMode _repeatMode = repeat.PlaybackRepeatMode.none;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  String? _currentPlaylistId;
  StreamSubscription? _completionSubscription;
  StreamSubscription? _skipNextSubscription;
  StreamSubscription? _skipPrevSubscription;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _bufferedPositionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<ProcessingState>? _processingStateSub;

  Timer? _sleepTimer;
  Timer? _sleepTimerTick;
  Duration? _sleepTimerRemaining;

  String? _lyrics;
  bool _isLoadingLyrics = false;
  
  Color? _dominantColor;
  bool _autoScroll = true;
  bool _isKaraokeMode = false;

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
      
      // If we have history and no current track, restore the last played track
      // so the miniplayer is persistent and visible on startup!
      if (_recentlyPlayed.isNotEmpty && _currentTrack == null) {
        _currentTrack = _recentlyPlayed.first;
        _queue = [_currentTrack!];
        _currentIndex = 0;
        _processingState = ProcessingState.idle;
      }
    } catch (_) {}
  }

  Future<void> _addToRecentlyPlayed(Track track) async {
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > _maxRecent) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, _maxRecent);
    }
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_recentlyPlayed.map((t) => {
      'id': t.id,
      'title': t.title,
      'author': t.author,
      'thumbnailUrl': t.thumbnailUrl,
      'durationSeconds': t.duration.inSeconds,
    }).toList());
    await prefs.setString(_recentlyPlayedKey, json);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    final bool wasPlayingCurrent = (index == _currentIndex && _isPlaying);
    
    if (index == _currentIndex) {
      if (_queue.length > 1) {
        final newIdx = index < _queue.length - 1 ? index : index - 1;
        _queue.removeAt(index);
        _currentIndex = newIdx.clamp(0, _queue.length - 1);
        if (wasPlayingCurrent) {
          playFromQueue(_currentIndex);
        } else {
          _currentTrack = _queue[_currentIndex];
          _position = Duration.zero;
          _bufferedPosition = Duration.zero;
          notifyListeners();
        }
      } else {
        _queue.removeAt(index);
        stop();
      }
    } else {
      _queue.removeAt(index);
      if (index < _currentIndex) _currentIndex--;
      notifyListeners();
    }
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
  bool get isBuffering => _processingState == ProcessingState.loading || _processingState == ProcessingState.buffering;
  bool get isActuallyPlaying => _isPlaying && !isBuffering;
  bool get isLoading => _isLoading;
  bool get shuffleMode => _shuffleMode;
  repeat.PlaybackRepeatMode get repeatMode => _repeatMode;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration => _duration;
  String? get error => _error;
  String? get currentPlaylistId => _currentPlaylistId;
  bool get isSleepTimerActive => _sleepTimer != null;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  String? get lyrics => _lyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;
  Color? get dominantColor => _dominantColor;

  bool get autoScroll => _autoScroll;
  bool get isKaraokeMode => _isKaraokeMode;

  void setAutoScroll(bool value) {
    _autoScroll = value;
    notifyListeners();
  }

  void setKaraokeMode(bool value) {
    _isKaraokeMode = value;
    notifyListeners();
  }

  Future<void> _fetchLyricsForCurrentTrack() async {
    final track = _currentTrack;
    if (track == null) {
      _lyrics = null;
      _isLoadingLyrics = false;
      notifyListeners();
      return;
    }

    _isLoadingLyrics = true;
    _lyrics = null;
    notifyListeners();

    final result = await _audioRepository.getLyrics(track);
    
    // Only update if the track hasn't changed while we were fetching
    if (_currentTrack?.id == track.id) {
      _lyrics = result;
      _isLoadingLyrics = false;
      notifyListeners();
    }
  }

  Future<void> refreshLyrics() async {
    final track = _currentTrack;
    if (track == null) return;

    _isLoadingLyrics = true;
    _lyrics = null;
    notifyListeners();

    final result = await _audioRepository.refreshLyrics(track);

    if (_currentTrack?.id == track.id) {
      _lyrics = result;
      _isLoadingLyrics = false;
      notifyListeners();
    }
  }

  Future<void> _extractDominantColor(String? url) async {
    _dominantColor = null;
    notifyListeners();
    if (url == null || url.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('dynamicAccentColor') == false) return;
    
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        maximumColorCount: 5,
      );
      if (_currentTrack?.thumbnailUrl == url) {
        _dominantColor = palette.dominantColor?.color ?? palette.vibrantColor?.color;
        notifyListeners();
      }
    } catch (_) {}
  }

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
    _repeatMode = repeat.PlaybackRepeatMode.values[(_repeatMode.index + 1) % repeat.PlaybackRepeatMode.values.length];
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
        _sleepTimerRemaining = _sleepTimerRemaining! - const Duration(seconds: 1);
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

  Future<void> playTrack(Track track, {AudioQuality quality = AudioQuality.adaptive}) async {
    _isLoading = true;
    _error = null;
    _stopPolling();
    _completionSubscription?.cancel();
    notifyListeners();

    try {
      _currentTrack = track;
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
      _addToRecentlyPlayed(track);

      // Kick off lyrics & color extraction concurrently — do NOT await either
      // here. Both are non-blocking background tasks: lyrics may take several
      // seconds over a slow network and blocking on them was causing the
      // provider to time them out (1500 ms) before the APIs had a chance to
      // respond, resulting in "No lyrics available" for most tracks.
      _fetchLyricsForCurrentTrack();
      _extractDominantColor(track.thumbnailUrl);

      final sourceRef = await PlaybackSession().resolve(track, _fallbackEngine);
      final qualityStr = sourceRef?.quality ?? 'adaptive';

      final audioUrl = await _audioRepository.getAudioUrl(
        track,
        quality: qualityStr,
      );

      if (sourceRef != null) {
        _currentTrack = track.copyWith(activeSource: sourceRef);
      }

      await _audioRepository.playTrack(track, audioUrl);
      _isPlaying = true;
      _startPolling();
      _listenForCompletion();
      for (final cb in _trackChangedListeners) {
        cb();
      }

      _preloadNextTrack();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _preloadNextTrack() async {
    if (_currentIndex + 1 < _queue.length) {
      final nextTrack = _queue[_currentIndex + 1];
      // Do not block playback on preloading
      _audioRepository.preloadTrack(nextTrack);
    }
  }

  /// Settings-slider-driven preload. On every track change we look ahead by
  /// `_settingsProvider.prebufferCount` (1..5) tracks, check the Hive box
  /// instantly, and fire background downloads for any missing ones.
  Future<void> _onTrackChangedForPreload() async {
    final lookAhead = _settingsProvider.prebufferCountClamped;
    for (var i = 1; i <= lookAhead; i++) {
      final idx = _currentIndex + i;
      if (idx < 0 || idx >= _queue.length) break;
      final track = _queue[idx];
      if (_hybridCache.isCached(track.id)) continue;
      if (_hybridCache.isActivelyCaching(track.id)) continue;
      _hybridCache.markCaching(track.id);
      // Fire-and-forget — never block the queue change on background writes.
      unawaited(_audioRepository.preloadTrack(track).catchError((_) {
        _hybridCache.markNotCaching(track.id);
      }));
    }
  }

  Future<void> playFromQueue(int index, {AudioQuality quality = AudioQuality.adaptive}) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await playTrack(_queue[index], quality: quality);
  }

  Future<void> togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioRepository.pause();
        _isPlaying = false;
        _autoScroll = false;
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

  Future<void> pause() async {
    try {
      await _audioRepository.pause();
      _isPlaying = false;
      _autoScroll = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to pause: ${e.toString()}';
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
    } else if (_repeatMode == repeat.PlaybackRepeatMode.all && _queue.isNotEmpty) {
      await playFromQueue(0);
    } else {
      // Autoplay: fetch next tracks if at the end
      if (_currentTrack != null) {
        final upNexts = await _audioRepository.getUpNexts(_currentTrack!);
        if (upNexts.isNotEmpty) {
          _queue.addAll(upNexts);
          notifyListeners();
          await playFromQueue(_currentIndex + 1);
        }
      }
    }
  }

  Future<void> previous() async {
    if (_position.inSeconds > 3) {
      seekTo(Duration.zero);
    } else if (_currentIndex > 0) {
      _currentIndex--;
      await playTrack(_queue[_currentIndex]);
    } else {
      seekTo(Duration.zero);
    }
  }

  void _startPolling() {
    _positionSub?.cancel();
    _bufferedPositionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _positionSub = _audioRepository.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    _bufferedPositionSub = _audioRepository.bufferedPositionStream.listen((pos) {
      _bufferedPosition = pos;
      notifyListeners();
    });
    _durationSub = _audioRepository.durationStream.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
    _playingSub = _audioRepository.playingStream.listen((isPlaying) {
      if (_isPlaying != isPlaying) {
        _isPlaying = isPlaying;
        notifyListeners();
      }
    });
    _processingStateSub?.cancel();
    _processingStateSub = _audioRepository.processingStateStream.listen((state) {
      if (_processingState != state) {
        _processingState = state;
        notifyListeners();
      }
    });
  }

  void _stopPolling() {
    _positionSub?.cancel();
    _positionSub = null;
    _bufferedPositionSub?.cancel();
    _bufferedPositionSub = null;
    _durationSub?.cancel();
    _durationSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    _processingStateSub?.cancel();
    _processingStateSub = null;
  }

  void _listenForCompletion() {
    _completionSubscription?.cancel();
    _completionSubscription =
        _audioRepository.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && _queue.isNotEmpty) {
        if (_repeatMode == repeat.PlaybackRepeatMode.one) {
          seekTo(Duration.zero);
          _audioRepository.resume();
        } else if (_currentIndex + 1 < _queue.length) {
          next();
        } else if (_repeatMode == repeat.PlaybackRepeatMode.all) {
          playFromQueue(0);
        } else {
          next(); // Will trigger autoplay fetching
        }
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
    _bufferedPositionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }
}
