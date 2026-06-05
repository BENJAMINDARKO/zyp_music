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
import '../../core/services/queue_manager.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../service/audio_handler.dart';
import '../../services/playback_session.dart';
import 'settings_provider.dart';

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final AudioRepository _audioRepository;
  final SettingsProvider _settingsProvider;
  final HybridCacheService _hybridCache;
  final QueueManager? _queueManager;
  late final FallbackEngine _fallbackEngine;

  PlayerProvider(
    this._audioRepository,
    this._settingsProvider,
    this._hybridCache, {
    QueueManager? queueManager,
  }) : _queueManager = queueManager {
    _fallbackEngine = FallbackEngine();
    WidgetsBinding.instance.addObserver(this);

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
    // Auto DJ engine state must invalidate any UI bound to this provider.
    _queueManager?.addListener(notifyListeners);
    // Allow the offline Auto DJ pool to look up recently-played metadata.
    _queueManager?.metadataResolver = () => {
          for (final t in _recentlyPlayed) t.id: t,
        };
    // Load recently played tracks on startup
    loadRecentlyPlayed().then((_) {
      _queueManager?.metadataResolver = () => {
            for (final t in _recentlyPlayed) t.id: t,
          };
      if (_recentlyPlayed.isNotEmpty) {
        notifyListeners();
      }
    });
    // Restore the persisted Auto Queue engagement flag and active track
    // metadata from disk so the engine and miniplayer resume their
    // previous state across cold launches.
    _loadAutoQueueState();
    _loadActiveTrackState();
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
  // Persistent state keys for the Auto Queue engine. Written on every
  // toggle and on app termination (via WidgetsBindingObserver) so the
  // next launch can resume the previous engagement.
  static const _autoQueueActiveKey = 'auto_queue_active';
  static const _activeTrackIdKey = 'active_track_id';
  static const _activeTrackTitleKey = 'active_track_title';
  static const _activeTrackAuthorKey = 'active_track_author';
  static const _activeTrackThumbnailKey = 'active_track_thumbnail';
  static const _activeTrackPositionKey = 'active_track_position_seconds';
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

  /// Persists the current Auto Queue engagement flag. Called on every
  /// enable/disable flip and on app termination so the next cold launch
  /// resumes the previous state.
  Future<void> _saveAutoQueueState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoQueueActiveKey, _queueManager?.isActive ?? false);
  }

  /// Restores the Auto Queue engagement flag from disk. Invoked once
  /// during construction. A previously-enabled engine is re-armed so the
  /// completion handler can immediately hand the baton to the
  /// recommendation loop on the next track end.
  Future<void> _loadAutoQueueState() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_autoQueueActiveKey) ?? false) {
      _queueManager?.enableAutoDJ();
    }
  }

  /// Persists the active track metadata + playback position. Invoked on
  /// app termination (and any future explicit save points) so the
  /// miniplayer can be restored on the next launch.
  Future<void> _saveActiveTrackState() async {
    final track = _currentTrack;
    final prefs = await SharedPreferences.getInstance();
    if (track == null) {
      await prefs.remove(_activeTrackIdKey);
      await prefs.remove(_activeTrackTitleKey);
      await prefs.remove(_activeTrackAuthorKey);
      await prefs.remove(_activeTrackThumbnailKey);
      await prefs.remove(_activeTrackPositionKey);
      return;
    }
    await prefs.setString(_activeTrackIdKey, track.id);
    await prefs.setString(_activeTrackTitleKey, track.title);
    await prefs.setString(_activeTrackAuthorKey, track.author ?? '');
    await prefs.setString(_activeTrackThumbnailKey, track.thumbnailUrl ?? '');
    await prefs.setInt(_activeTrackPositionKey, _position.inSeconds);
  }

  /// Restores the active track metadata from disk into the in-memory
  /// queue. Playback is NOT auto-resumed — the miniplayer just appears
  /// populated, and the user can press play to pick up where they left
  /// off.
  Future<void> _loadActiveTrackState() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_activeTrackIdKey);
    if (id == null || id.isEmpty) return;
    if (_currentTrack != null) return; // Already restored by recently-played.
    final restored = Track(
      id: id,
      title: prefs.getString(_activeTrackTitleKey) ?? '',
      author: prefs.getString(_activeTrackAuthorKey),
      thumbnailUrl: prefs.getString(_activeTrackThumbnailKey),
      duration: Duration(seconds: prefs.getInt(_activeTrackPositionKey) ?? 0),
    );
    _currentTrack = restored;
    _queue = [restored];
    _currentIndex = 0;
    _processingState = ProcessingState.idle;
    notifyListeners();
  }

  /// WidgetsBindingObserver hook. Persists the Auto Queue state and the
  /// active track metadata on full app termination (iOS-style detached
  /// state) so the next cold launch can resume. Other lifecycle
  /// transitions (backgrounded, inactive) are intentionally ignored —
  /// the OS may resume the process without a true cold start.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _saveAutoQueueState();
      _saveActiveTrackState();
    }
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
    // A direct setQueue is always a manual playback action. Auto DJ must be
    // explicitly engaged by the user via the context menu or the dedicated
    // Auto DJ icon; never implicit.
    _queueManager?.disableAutoDJ();
    notifyListeners();
  }

  /// Cleared: the Auto DJ functional block has been migrated to
  /// [startAutoQueue] per the Auto Queue spec. Kept as a no-op so any
  /// external callers (tests, legacy widgets) continue to compile and
  /// run without side-effects.
  void startAutoDJ(List<Track> tracks, {int startIndex = 0, String? playlistId}) {
    // No-op: Auto DJ functional block has been migrated to Auto Queue.
  }

  /// Engages the Auto Queue engine.
  ///
  /// * If a track is already playing or paused in memory, the existing
  ///   recommendation engine is armed so the next track is generated and
  ///   appended to the queue after the current one finishes — playback is
  ///   not interrupted.
  /// * If the queue is empty, the engine cold-starts from [seedTrack]
  ///   (full audio load + lyrics read + play) to eliminate dead-air.
  void startAutoQueue(Track seedTrack) {
    if (_queue.isNotEmpty) {
      _queueManager?.enableAutoDJ();
      _saveAutoQueueState();
      notifyListeners();
    } else {
      coldStartAutoQueue(seedTrack);
    }
  }

  /// Cold-starts the Auto Queue engine from [seedTrack]: resets the active
  /// queue to a single seed, enables the recommendation engine, and fires
  /// [playTrack] so the audio is loaded, lyrics are fetched, and playback
  /// begins immediately. Used by the context-menu "Auto Queue" action
  /// when the global queue is empty.
  void coldStartAutoQueue(Track seedTrack) {
    _queue = [seedTrack];
    _currentIndex = 0;
    _currentPlaylistId = null;
    _originalQueue = null;
    _shuffleMode = false;
    _error = null;
    _queueManager?.enableAutoDJ();
    _saveAutoQueueState();
    notifyListeners();
    playTrack(seedTrack);
  }

  /// True iff the Auto Queue recommendation engine is currently armed.
  /// Surface for the context menu snackbar messaging.
  bool get isAutoQueueActive => _queueManager?.isActive ?? false;

  /// Appends [tracks] to the end of the active queue without interrupting
  /// the currently playing track. **Never** engages Auto DJ — once the
  /// manual queue finishes, playback stops.
  void appendToQueue(List<Track> tracks) {
    if (tracks.isEmpty) return;
    _queue.addAll(tracks);
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
      return;
    }
    if (_repeatMode == repeat.PlaybackRepeatMode.all && _queue.isNotEmpty) {
      await playFromQueue(0);
      return;
    }
    // End of the manual queue. The next-button is a no-op here — auto DJ
    // (if engaged) is only driven by the completion handler so a user who
    // taps "next" at the end of a manual queue does not unexpectedly flip
    // on the recommendation engine.
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
        } else if (_queueManager?.isActive ?? false) {
          _generateAutoDJNext();
        } else {
          // End of the manual queue with Auto DJ disengaged. Strict finite
          // playback: stop without auto-rolling recommendations.
          _stopAfterQueue();
        }
      }
    });
  }

  /// Asks the [QueueManager] for the next Auto DJ track and plays it.
  /// Falls back to a graceful stop if the engine returns nothing.
  Future<void> _generateAutoDJNext() async {
    final manager = _queueManager;
    final current = _currentTrack;
    if (manager == null || current == null) {
      _stopAfterQueue();
      return;
    }
    final next = await manager.generateNextAutoDJTrack(current);
    if (next == null) {
      _stopAfterQueue();
      return;
    }
    _queue.add(next);
    await playFromQueue(_currentIndex + 1);
  }

  /// Stops playback at the end of the manual queue when Auto DJ is off.
  /// Mirrors the existing [stop] side-effects but leaves the queue and
  /// current track metadata intact so the miniplayer remains in its last
  /// resting state.
  void _stopAfterQueue() {
    _audioRepository.pause();
    _isPlaying = false;
    _autoScroll = false;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _processingState = ProcessingState.idle;
    _queueManager?.disableAutoDJ();
    notifyListeners();
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
    _queueManager?.disableAutoDJ();
    _audioHandler?.clearQueue();
    await stop();
    notifyListeners();
  }

  /// Toggles the Auto DJ engine without changing the active queue. Used by
  /// the dedicated Auto DJ icon in the miniplayer and the full-screen
  /// player. Returns the new state.
  bool toggleAutoDJ() {
    final manager = _queueManager;
    if (manager == null) return false;
    return manager.toggleAutoDJ();
  }

  bool get isAutoDJEnabled => _queueManager?.isActive ?? false;

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
    _queueManager?.removeListener(notifyListeners);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
