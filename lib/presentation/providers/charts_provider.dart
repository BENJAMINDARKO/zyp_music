import 'package:flutter/foundation.dart';
import '../../data/repositories/charts_repository_impl.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/video.dart';
import '../../../core/utils/app_logger.dart';

class ChartsProvider extends ChangeNotifier {
  final ChartsRepositoryImpl _repository;
  
  List<Track> _ghanaTopSongs = [];
  List<Track> _globalTopSongs = [];
  List<Album> _featuredAlbums = [];
  List<String> _ghanaTopArtists = [];
  
  bool _isLoadingGhana = false;
  bool _isLoadingGlobal = false;
  bool _isLoadingAlbums = false;

  List<Track> get ghanaTopSongs => _ghanaTopSongs;
  List<Track> get globalTopSongs => _globalTopSongs;
  List<Album> get featuredAlbums => _featuredAlbums;
  List<String> get ghanaTopArtists => _ghanaTopArtists;
  
  bool get isLoadingGhana => _isLoadingGhana;
  bool get isLoadingGlobal => _isLoadingGlobal;
  bool get isLoadingAlbums => _isLoadingAlbums;

  ChartsProvider(this._repository) {
    _init();
  }

  Future<String?> searchArtistId(String artistName) {
    return _repository.searchArtistId(artistName);
  }

  Future<void> _init() async {
    // Load all concurrently
    await Future.wait([
      fetchGhanaTopSongs(),
      fetchGlobalTopSongs(),
      fetchFeaturedAlbums(),
    ]);
  }

  Future<void> fetchGhanaTopSongs({bool forceRefresh = false}) async {
    _isLoadingGhana = true;
    notifyListeners();
    
    try {
      _ghanaTopSongs = await _repository.getGhanaTopSongs(forceRefresh: forceRefresh);
      _extractGhanaArtists();
    } catch (e) {
      AppLogger.log('Error fetching Ghana charts: $e', name: 'ChartsProvider');
    } finally {
      _isLoadingGhana = false;
      notifyListeners();
    }
  }

  void _extractGhanaArtists() {
    final Set<String> artists = {};
    for (final track in _ghanaTopSongs) {
      if (track.author != null && track.author!.isNotEmpty) {
        // Strip common prefixes or split by commas if needed, simple extract for now
        artists.add(track.author!);
      }
    }
    _ghanaTopArtists = artists.toList();
  }

  Future<void> fetchGlobalTopSongs({bool forceRefresh = false}) async {
    _isLoadingGlobal = true;
    notifyListeners();
    
    try {
      _globalTopSongs = await _repository.getGlobalTopSongs(forceRefresh: forceRefresh);
    } catch (e) {
      AppLogger.log('Error fetching Global charts: $e', name: 'ChartsProvider');
    } finally {
      _isLoadingGlobal = false;
      notifyListeners();
    }
  }

  Future<void> fetchFeaturedAlbums({bool forceRefresh = false}) async {
    _isLoadingAlbums = true;
    notifyListeners();
    
    try {
      _featuredAlbums = await _repository.getFeaturedAlbums(forceRefresh: forceRefresh);
    } catch (e) {
      AppLogger.log('Error fetching Featured Albums: $e', name: 'ChartsProvider');
    } finally {
      _isLoadingAlbums = false;
      notifyListeners();
    }
  }
}
