import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/audio_quality.dart';

enum StreamSource { youtube, tidal }

class SettingsProvider extends ChangeNotifier {
  static const _keyPrebufferCount = 'prebufferCount';
  static const _keyAudioQuality = 'audioQuality'; // General legacy fallback
  static const _keyStreamSource = 'streamSource';
  static const _keySchemaVersion = 'schemaVersion';
  static const _keySourcePriority = 'sourcePriority';
  
  // Appearance
  static const _keyTheme = 'theme';
  
  // Interface
  static const _keyShowRecommendedSongs = 'showRecommendedSongs';
  static const _keyShowRecommendedAlbums = 'showRecommendedAlbums';
  static const _keyShowRecommendedArtists = 'showRecommendedArtists';
  static const _keyShowJumpBackIn = 'showJumpBackIn';
  static const _keyShowEditorsPicks = 'showEditorsPicks';
  static const _keyShuffleEditorsPicks = 'shuffleEditorsPicks';
  static const _keyDynamicAccentColor = 'dynamicAccentColor';
  static const _keyVisualizerStyle = 'visualizerStyle';
  static const _keyInvertSeekbarColor = 'invertSeekbarColor';
  static const _keySeekbarStyle = 'seekbarStyle';

  // Scrobbling
  static const _keyScrobbleThreshold = 'scrobbleThreshold';

  // Audio
  static const _keyYoutubeMusicQuality = 'youtubeMusicQuality';
  static const _keyTidalStreamingQuality = 'tidalStreamingQuality';
  static const _keyEnableSourceFallback = 'enableSourceFallback';

  // Search Sources
  static const _keySearchSourceYoutube = 'searchSourceYoutube';
  static const _keySearchSourceYTMusic = 'searchSourceYTMusic';
  static const _keySearchSourceTidal = 'searchSourceTidal';

  // Downloads
  static const _keyDownloadQuality = 'downloadQuality';
  static const _keyAndroidDownloadFolder = 'androidDownloadFolder';
  static const _keyBulkDownloadMethod = 'bulkDownloadMethod';
  static const _keyForceZipAsBlob = 'forceZipAsBlob';

  // Instances
  static const _keyTidalApiInstances = 'tidalApiInstances';
  static const _keyTidalStreamingInstances = 'tidalStreamingInstances';

  int _prebufferCount = 3;
  AudioQuality _audioQuality = AudioQuality.adaptive;
  StreamSource _streamSource = StreamSource.tidal;
  bool _enableSourceFallback = true;
  int _schemaVersion = 1;
  List<String> _sourcePriority = ['tidal', 'youtube_music', 'youtube'];

  List<String> _tidalApiInstances = [
    'https://tidal-api.geeked.wtf/api',
    'https://api.monochrome.tf',
  ];

  List<String> _tidalStreamingInstances = [
    'https://tidal-api.geeked.wtf/api',
    'https://api.monochrome.tf',
  ];

  String _theme = 'Dark';

  bool _showRecommendedSongs = true;
  bool _showRecommendedAlbums = true;
  bool _showRecommendedArtists = true;
  bool _showJumpBackIn = true;
  bool _showEditorsPicks = true;
  bool _shuffleEditorsPicks = false;
  bool _dynamicAccentColor = true;
  String _visualizerStyle = 'Bars';
  bool _invertSeekbarColor = false;
  String _seekbarStyle = 'Minimal';

  int _scrobbleThreshold = 75;

  String _youtubeMusicQuality = 'adaptive';
  String _tidalStreamingQuality = 'tidalHiRes';

  String _downloadQuality = 'AAC 320kbps';
  String _androidDownloadFolder = '/storage/emulated/0/Music/Monochrome';
  String _bulkDownloadMethod = 'ZIP Archive';
  bool _forceZipAsBlob = false;

  bool _searchSourceYoutube = true;
  bool _searchSourceYTMusic = true;
  bool _searchSourceTidal = true;

  int get prebufferCount => _prebufferCount;
  AudioQuality get audioQuality => _audioQuality;
  StreamSource get streamSource => _streamSource;
  bool get enableSourceFallback => _enableSourceFallback;
  int get schemaVersion => _schemaVersion;
  List<String> get sourcePriority => _sourcePriority;

  List<String> get tidalApiInstances => _tidalApiInstances;
  List<String> get tidalStreamingInstances => _tidalStreamingInstances;

  String get theme => _theme;

  bool get showRecommendedSongs => _showRecommendedSongs;
  bool get showRecommendedAlbums => _showRecommendedAlbums;
  bool get showRecommendedArtists => _showRecommendedArtists;
  bool get showJumpBackIn => _showJumpBackIn;
  bool get showEditorsPicks => _showEditorsPicks;
  bool get shuffleEditorsPicks => _shuffleEditorsPicks;
  bool get dynamicAccentColor => _dynamicAccentColor;
  String get visualizerStyle => _visualizerStyle;
  bool get invertSeekbarColor => _invertSeekbarColor;
  String get seekbarStyle {
    if (!['Gradient', 'Minimal', 'Wavy', 'Segmented'].contains(_seekbarStyle)) {
      return 'Minimal';
    }
    return _seekbarStyle;
  }

  int get scrobbleThreshold => _scrobbleThreshold;

  String get youtubeMusicQuality => _youtubeMusicQuality;
  String get tidalStreamingQuality => _tidalStreamingQuality;

  String get downloadQuality => _downloadQuality;
  String get androidDownloadFolder => _androidDownloadFolder;
  String get bulkDownloadMethod => _bulkDownloadMethod;
  bool get forceZipAsBlob => _forceZipAsBlob;

  bool get searchSourceYoutube => _searchSourceYoutube;
  bool get searchSourceYTMusic => _searchSourceYTMusic;
  bool get searchSourceTidal => _searchSourceTidal;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Migration System
    _schemaVersion = prefs.getInt(_keySchemaVersion) ?? 0;
    if (_schemaVersion < 1) {
      // v0 -> v1: Add source priority
      final defaultPriority = ['tidal', 'youtube_music', 'youtube'];
      await prefs.setStringList(_keySourcePriority, defaultPriority);
      await prefs.setInt(_keySchemaVersion, 1);
      _schemaVersion = 1;
    }

    _sourcePriority = prefs.getStringList(_keySourcePriority) ?? ['tidal', 'youtube_music', 'youtube'];

    _tidalApiInstances = prefs.getStringList(_keyTidalApiInstances) ?? [
      'https://tidal-api.geeked.wtf/api',
      'https://api.monochrome.tf',
    ];
    _tidalStreamingInstances = prefs.getStringList(_keyTidalStreamingInstances) ?? [
      'https://tidal-api.geeked.wtf/api',
      'https://api.monochrome.tf',
    ];

    _prebufferCount = prefs.getInt(_keyPrebufferCount) ?? 3;
    final qualityStr = prefs.getString(_keyAudioQuality);
    _audioQuality = qualityStr != null
        ? AudioQuality.values.firstWhere((q) => q.name == qualityStr,
            orElse: () => AudioQuality.adaptive)
        : AudioQuality.adaptive;
        
    final sourceStr = prefs.getString(_keyStreamSource);
    _streamSource = sourceStr != null
        ? StreamSource.values.firstWhere((s) => s.name == sourceStr,
            orElse: () => StreamSource.tidal)
        : StreamSource.tidal;
        
    _enableSourceFallback = prefs.getBool(_keyEnableSourceFallback) ?? true;
    
    _theme = prefs.getString(_keyTheme) ?? 'Dark';
    
    _showRecommendedSongs = prefs.getBool(_keyShowRecommendedSongs) ?? true;
    _showRecommendedAlbums = prefs.getBool(_keyShowRecommendedAlbums) ?? true;
    _showRecommendedArtists = prefs.getBool(_keyShowRecommendedArtists) ?? true;
    _showJumpBackIn = prefs.getBool(_keyShowJumpBackIn) ?? true;
    _showEditorsPicks = prefs.getBool(_keyShowEditorsPicks) ?? true;
    _shuffleEditorsPicks = prefs.getBool(_keyShuffleEditorsPicks) ?? false;
    _dynamicAccentColor = prefs.getBool(_keyDynamicAccentColor) ?? true;
    _visualizerStyle = prefs.getString(_keyVisualizerStyle) ?? 'Bars';
    _invertSeekbarColor = prefs.getBool(_keyInvertSeekbarColor) ?? false;
    _seekbarStyle = prefs.getString(_keySeekbarStyle) ?? 'Minimal';

    _searchSourceYoutube = prefs.getBool(_keySearchSourceYoutube) ?? true;
    _searchSourceYTMusic = prefs.getBool(_keySearchSourceYTMusic) ?? true;
    _searchSourceTidal = prefs.getBool(_keySearchSourceTidal) ?? true;

    _scrobbleThreshold = prefs.getInt(_keyScrobbleThreshold) ?? 75;

    _youtubeMusicQuality = prefs.getString(_keyYoutubeMusicQuality) ?? 'adaptive';
    _tidalStreamingQuality = prefs.getString(_keyTidalStreamingQuality) ?? 'tidalHiRes';

    _downloadQuality = prefs.getString(_keyDownloadQuality) ?? 'AAC 320kbps';
    _androidDownloadFolder = prefs.getString(_keyAndroidDownloadFolder) ?? '/storage/emulated/0/Music/Monochrome';
    _bulkDownloadMethod = prefs.getString(_keyBulkDownloadMethod) ?? 'ZIP Archive';
    _forceZipAsBlob = prefs.getBool(_keyForceZipAsBlob) ?? false;
        
    notifyListeners();
  }

  Future<void> setPrebufferCount(int count) async {
    _prebufferCount = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPrebufferCount, count);
    notifyListeners();
  }

  Future<void> setAudioQuality(AudioQuality quality) async {
    _audioQuality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioQuality, quality.name);
    notifyListeners();
  }

  Future<void> setStreamSource(StreamSource source) async {
    _streamSource = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStreamSource, source.name);
    notifyListeners();
  }

  Future<void> setSourcePriority(List<String> priority) async {
    _sourcePriority = priority;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keySourcePriority, priority);
    notifyListeners();
  }
  
  Future<void> setEnableSourceFallback(bool value) async {
    _enableSourceFallback = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableSourceFallback, value);
    notifyListeners();
  }
  
  Future<void> setTheme(String theme) async {
    _theme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, theme);
    notifyListeners();
  }

  Future<void> setBoolSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    switch (key) {
      case _keyShowRecommendedSongs: _showRecommendedSongs = value; break;
      case _keyShowRecommendedAlbums: _showRecommendedAlbums = value; break;
      case _keyShowRecommendedArtists: _showRecommendedArtists = value; break;
      case _keyShowJumpBackIn: _showJumpBackIn = value; break;
      case _keyShowEditorsPicks: _showEditorsPicks = value; break;
      case _keyShuffleEditorsPicks: _shuffleEditorsPicks = value; break;
      case _keyDynamicAccentColor: _dynamicAccentColor = value; break;
      case _keyForceZipAsBlob: _forceZipAsBlob = value; break;
      case _keySearchSourceYoutube: _searchSourceYoutube = value; break;
      case _keySearchSourceYTMusic: _searchSourceYTMusic = value; break;
      case _keySearchSourceTidal: _searchSourceTidal = value; break;
      case _keyInvertSeekbarColor: _invertSeekbarColor = value; break;
    }
    notifyListeners();
  }

  Future<void> setInvertSeekbarColor(bool value) async {
    return setBoolSetting(_keyInvertSeekbarColor, value);
  }

  Future<void> setVisualizerStyle(String style) async {
    return setStringSetting(_keyVisualizerStyle, style);
  }

  Future<void> setSeekbarStyle(String style) async {
    return setStringSetting(_keySeekbarStyle, style);
  }

  Future<void> setStringSetting(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    switch (key) {
      case _keyYoutubeMusicQuality: _youtubeMusicQuality = value; break;
      case _keyTidalStreamingQuality: _tidalStreamingQuality = value; break;
      case _keyDownloadQuality: _downloadQuality = value; break;
      case _keyAndroidDownloadFolder: _androidDownloadFolder = value; break;
      case _keyBulkDownloadMethod: _bulkDownloadMethod = value; break;
      case _keyVisualizerStyle: _visualizerStyle = value; break;
      case _keySeekbarStyle: _seekbarStyle = value; break;
    }
    notifyListeners();
  }

  Future<void> setIntSetting(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    if (key == _keyScrobbleThreshold) {
      _scrobbleThreshold = value;
    }
    notifyListeners();
  }

  Future<void> refreshTidalInstances() async {
    try {
      final response = await http.get(Uri.parse('https://monochrome.tf/instances.json')).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['api'] != null) {
          _tidalApiInstances = List<String>.from(data['api']);
        }
        if (data['streaming'] != null) {
          _tidalStreamingInstances = List<String>.from(data['streaming']);
        }
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_keyTidalApiInstances, _tidalApiInstances);
        await prefs.setStringList(_keyTidalStreamingInstances, _tidalStreamingInstances);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to refresh Tidal instances: $e');
    }
  }

  Future<void> addTidalApiInstance(String url) async {
    if (!_tidalApiInstances.contains(url)) {
      _tidalApiInstances.add(url);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyTidalApiInstances, _tidalApiInstances);
      notifyListeners();
    }
  }

  Future<void> removeTidalApiInstance(String url) async {
    _tidalApiInstances.remove(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyTidalApiInstances, _tidalApiInstances);
    notifyListeners();
  }

  Future<void> addTidalStreamingInstance(String url) async {
    if (!_tidalStreamingInstances.contains(url)) {
      _tidalStreamingInstances.add(url);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyTidalStreamingInstances, _tidalStreamingInstances);
      notifyListeners();
    }
  }

  Future<void> removeTidalStreamingInstance(String url) async {
    _tidalStreamingInstances.remove(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyTidalStreamingInstances, _tidalStreamingInstances);
    notifyListeners();
  }
}
