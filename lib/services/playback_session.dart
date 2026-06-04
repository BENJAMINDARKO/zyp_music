import 'dart:async';
import '../domain/entities/video.dart';

class FallbackEngine {
  FallbackEngine();

  Future<SourceRef?> resolve(Track track) async {
    return SourceRef(
      provider: TrackSource.youtube,
      streamId: track.id,
      quality: 'adaptive',
    );
  }
}

class PlaybackSession {
  static final PlaybackSession _instance = PlaybackSession._internal();
  factory PlaybackSession() => _instance;
  PlaybackSession._internal();

  final Map<String, SourceRef> _resolvedSources = {};

  Future<void> init() async {
    _resolvedSources.clear();
  }

  Future<SourceRef?> resolve(Track track, FallbackEngine engine) async {
    if (_resolvedSources.containsKey(track.id)) {
      return _resolvedSources[track.id];
    }
    final source = await engine.resolve(track);
    if (source != null) {
      _resolvedSources[track.id] = source;
    }
    return source;
  }

  void clear() {
    _resolvedSources.clear();
  }
}
