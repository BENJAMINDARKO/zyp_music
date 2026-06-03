import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/video.dart';
import '../presentation/providers/settings_provider.dart';

class FallbackEngine {
  final SettingsProvider settingsProvider;

  FallbackEngine({required this.settingsProvider});

  Future<SourceRef?> resolve(Track track) async {
    final priority = settingsProvider.sourcePriority;
    
    // Sort the available track sources by user priority
    final availableSources = List<SourceRef>.from(track.sources);
    availableSources.sort((a, b) {
      final indexA = priority.indexOf(a.provider.name);
      final indexB = priority.indexOf(b.provider.name);
      final sortA = indexA == -1 ? 999 : indexA;
      final sortB = indexB == -1 ? 999 : indexB;
      return sortA.compareTo(sortB);
    });

    if (availableSources.isEmpty) {
      // Fallback if no explicit sources list exists (legacy track)
      return SourceRef(
        provider: track.source,
        streamId: track.id,
        quality: track.source == TrackSource.tidal ? 'lossless' : 'adaptive',
      );
    }

    for (final source in availableSources) {
      if (!source.isOnline) continue;

      // In a real implementation, you might ping the source here.
      // For now, we assume it's online and try to use it.
      return source;
    }

    return null;
  }
}

class PlaybackSession {
  static final PlaybackSession _instance = PlaybackSession._internal();
  factory PlaybackSession() => _instance;
  PlaybackSession._internal();

  final Map<String, SourceRef> _resolvedSources = {};

  Future<void> init() async {
    // In a full implementation, you'd load the persisted session here.
    // We'll keep it simple in memory for now.
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
