import 'dart:convert';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/playlist_sort_mode.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/playlist_repository.dart';

class PlaylistProvider extends ChangeNotifier {
  final PlaylistRepository _repository;

  PlaylistProvider(this._repository);

  List<Playlist> _playlists = [];
  Playlist? _currentPlaylist;
  bool _isLoading = false;
  String? _error;
  PlaylistSortMode _sortMode = PlaylistSortMode.dateAdded;

  PlaylistSortMode get sortMode => _sortMode;

  List<Playlist> get playlists {
    final sorted = List<Playlist>.from(_playlists);
    switch (_sortMode) {
      case PlaylistSortMode.title:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case PlaylistSortMode.trackCount:
        sorted.sort((a, b) => b.videoCount.compareTo(a.videoCount));
        break;
      case PlaylistSortMode.dateAdded:
        break;
    }
    return sorted;
  }

  void setSortMode(PlaylistSortMode mode) {
    _sortMode = mode;
    notifyListeners();
  }

  Playlist? get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<Playlist?> fetchPlaylist(String input) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final cleanId = _extractPlaylistId(input);
      if (cleanId.isEmpty) {
        _error = 'Could not extract a playlist ID from that URL';
        return null;
      }
      _currentPlaylist = await _repository.getPlaylist(cleanId);
      await _reloadSilently();
      return _currentPlaylist;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Playlist?> fetchFromUrl(String input) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentPlaylist = await _repository.getFromUrl(input);
      await _reloadSilently();
      return _currentPlaylist;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadSilently() async {
    try {
      _playlists = await _repository.getSavedPlaylists();
    } catch (e) {
      dev.log('Failed to reload playlists silently: $e', name: 'PlaylistProvider');
    }
  }

  Future<void> loadSavedPlaylists() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _playlists = await _repository.getSavedPlaylists();
    } catch (e) {
      _error = 'Failed to load saved playlists';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCachedPlaylist(String playlistId) async {
    try {
      final cached = await _repository.getCachedPlaylist(playlistId);
      if (cached != null) {
        _currentPlaylist = cached;
        notifyListeners();
      }
    } catch (e) {
      dev.log('Failed to load cached playlist $playlistId: $e',
          name: 'PlaylistProvider');
    }
  }

  Future<List<Track>?> getCachedTracks(String playlistId) async {
    try {
      return _repository.getCachedTracks(playlistId);
    } catch (e) {
      dev.log('Failed to get cached tracks for $playlistId: $e',
          name: 'PlaylistProvider');
      return null;
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _repository.deletePlaylist(playlistId);
    _playlists.removeWhere((p) => p.id == playlistId);
    if (_currentPlaylist?.id == playlistId) {
      _currentPlaylist = null;
    }
    notifyListeners();
  }

  String _extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.containsKey('list')) {
      final id = uri.queryParameters['list'];
      if (id != null && id.isNotEmpty) return id;
    }
    return trimmed;
  }

  Future<String> exportPlaylists(String format) async {
    final playlists = await _repository.getSavedPlaylists();
    final data = <Map<String, dynamic>>[];
    for (final p in playlists) {
      final tracks = await _repository.getCachedTracks(p.id);
      data.add({
        'id': p.id,
        'title': p.title,
        'author': p.author,
        'thumbnailUrl': p.thumbnailUrl,
        'videoCount': p.videoCount,
        'tracks': tracks.map((t) => {
          'id': t.id,
          'title': t.title,
          'author': t.author,
          'durationSeconds': t.duration.inSeconds,
          'thumbnailUrl': t.thumbnailUrl,
        }).toList(),
      });
    }
    final export = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'playlists': data,
    };

    String content;
    String ext;
    switch (format) {
      case 'xml':
        ext = 'xml';
        content = _toXml(export);
        break;
      case 'md':
        ext = 'md';
        content = _toMarkdown(playlists);
        break;
      default:
        ext = 'json';
        content = const JsonEncoder.withIndent('  ').convert(export);
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ytmusix_export.$ext');
    await file.writeAsString(content);
    return file.path;
  }

  Future<int> importPlaylists(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final trimmed = content.trim();
    int count = 0;

    if (trimmed.startsWith('{')) {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final playlists = json['playlists'] as List<dynamic>;
      for (final p in playlists) {
        final id = p['id'] as String;
        final url = 'https://www.youtube.com/playlist?list=$id';
        try {
          await fetchFromUrl(url);
          count++;
        } catch (e) {
          dev.log('Import failed for $id: $e', name: 'PlaylistProvider');
        }
      }
    } else if (trimmed.startsWith('<')) {
      final idRegex = RegExp(r'<id>([^<]+)</id>');
      for (final match in idRegex.allMatches(trimmed)) {
        final id = match.group(1)!;
        try {
          await fetchFromUrl('https://www.youtube.com/playlist?list=$id');
          count++;
        } catch (e) {
          dev.log('Import failed for $id: $e', name: 'PlaylistProvider');
        }
      }
    } else {
      final urlRegex = RegExp(r'https?://[^\s\)\]]+');
      for (final match in urlRegex.allMatches(trimmed)) {
        try {
          await fetchFromUrl(match.group(0)!);
          count++;
        } catch (e) {
          dev.log('Import failed: $e', name: 'PlaylistProvider');
        }
      }
    }
    return count;
  }

  String _toXml(Map<String, dynamic> data) {
    final buf = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
    buf.writeln('<ytmusix version="${data['version']}" exportedAt="${data['exportedAt']}">');
    for (final p in data['playlists'] as List<dynamic>) {
      buf.writeln('  <playlist>');
      buf.writeln('    <id>${p['id']}</id>');
      buf.writeln('    <title>${_xmlEscape(p['title'])}</title>');
      buf.writeln('    <author>${_xmlEscape(p['author'] ?? '')}</author>');
      buf.writeln('    <videoCount>${p['videoCount']}</videoCount>');
      final tracks = p['tracks'] as List<dynamic>?;
      if (tracks != null && tracks.isNotEmpty) {
        buf.writeln('    <tracks>');
        for (final t in tracks) {
          buf.writeln('      <track>');
          buf.writeln('        <id>${t['id']}</id>');
          buf.writeln('        <title>${_xmlEscape(t['title'])}</title>');
          buf.writeln('      </track>');
        }
        buf.writeln('    </tracks>');
      }
      buf.writeln('  </playlist>');
    }
    buf.writeln('</ytmusix>');
    return buf.toString();
  }

  String _xmlEscape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  String _toMarkdown(List<Playlist> playlists) {
    final buf = StringBuffer('# YTMusix Export\n\n');
    buf.writeln('Exported on ${DateTime.now().toLocal()}\n');
    for (final p in playlists) {
      buf.writeln('- [${p.title}](${"https://www.youtube.com/playlist?list=${p.id}"})');
    }
    return buf.toString();
  }

  Future<List<Track>> search(String query) async {
    try {
      return await _repository.search(query);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
