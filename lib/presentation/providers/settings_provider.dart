import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/audio_quality.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyPrebufferCount = 'prebufferCount';
  static const _keyAudioQuality = 'audioQuality'; // General legacy fallback

  // Appearance
  static const _keyTheme = 'theme';
  
  // Interface
  static const _keyShowRecommendedSongs = 'showRecommendedSongs';
  static const _keyShowRecommendedAlbums = 'showRecommendedAlbums';
  static const _keyShowRecommendedArtists = 'showRecommendedArtists';
  static const _keyShowJumpBackIn = 'showJumpBackIn';
  static const _keyShowEditorsPicks = 'showEditorsPicks';
  static const _keyShuffleEditorsPicks = 'shuffleEditorsPicks';
  static const _keyShowTrendingNow = 'showTrendingNow';
  static const _keyShowSuggestedArtists = 'showSuggestedArtists';
  static const _keyShowStartListening = 'showStartListening';
  static const _keyShowTopArtists = 'showTopArtists';
  static const _keyShowPopularAlbums = 'showPopularAlbums';
  static const _keyDynamicAccentColor = 'dynamicAccentColor';
  static const _keyVisualizerStyle = 'visualizerStyle';
  static const _keyInvertSeekbarColor = 'invertSeekbarColor';
  static const _keySeekbarStyle = 'seekbarStyle';

  // Scrobbling
  static const _keyScrobbleThreshold = 'scrobbleThreshold';

  // Audio
  static const _keyYoutubeMusicQuality = 'youtubeMusicQuality';
  static const _keyYoutubeMusicFormat = 'youtubeMusicFormat';

  // Search Sources
  static const _keySearchSourceYoutube = 'searchSourceYoutube';
  static const _keySearchSourceYTMusic = 'searchSourceYTMusic';
  static const _keyExplicitFilter = 'explicitFilter';

  // Downloads
  static const _keyDownloadQuality = 'downloadQuality';
  static const _keyAndroidDownloadFolder = 'androidDownloadFolder';
  static const _keyBulkDownloadMethod = 'bulkDownloadMethod';
  static const _keyForceZipAsBlob = 'forceZipAsBlob';

  // Spotify API Integration
  static const _keySpotifyClientId = 'spotifyClientId';
  static const _keySpotifyClientSecret = 'spotifyClientSecret';

  // Region
  static const _keyPreferredGl = 'preferredGl';
  static const List<Map<String, String>> countryOptions = [
    {'code': 'GH', 'name': 'Ghana'},
    {'code': 'NG', 'name': 'Nigeria'},
    {'code': 'KE', 'name': 'Kenya'},
    {'code': 'ZA', 'name': 'South Africa'},
    {'code': 'TZ', 'name': 'Tanzania'},
    {'code': 'UG', 'name': 'Uganda'},
    {'code': 'ZM', 'name': 'Zambia'},
    {'code': 'ZW', 'name': 'Zimbabwe'},
    {'code': 'US', 'name': 'United States'},
    {'code': 'GB', 'name': 'United Kingdom'},
    {'code': 'DE', 'name': 'Germany'},
    {'code': 'FR', 'name': 'France'},
    {'code': 'BR', 'name': 'Brazil'},
    {'code': 'IN', 'name': 'India'},
    {'code': 'JP', 'name': 'Japan'},
    {'code': 'AU', 'name': 'Australia'},
    {'code': 'CA', 'name': 'Canada'},
  ];

  int _prebufferCount = 3;
  AudioQuality _audioQuality = AudioQuality.adaptive;

  // Hard caps the Settings > Audio > Caching & PreBuffer slider.
  // The Hive-driven preload loop reads this on every queue change.
  static const int minPrebufferCount = 1;
  static const int maxPrebufferCount = 5;

  String _theme = 'Dark';

  bool _showRecommendedSongs = true;
  bool _showRecommendedAlbums = true;
  bool _showRecommendedArtists = true;
  bool _showJumpBackIn = true;
  bool _showEditorsPicks = true;
  bool _shuffleEditorsPicks = false;

  // Music Now Tab
  bool _showTrendingNow = true;
  bool _showSuggestedArtists = true;
  bool _showStartListening = true;
  bool _showTopArtists = true;
  bool _showPopularAlbums = true;
  bool _dynamicAccentColor = true;
  String _visualizerStyle = 'Bars';
  bool _invertSeekbarColor = false;
  String _seekbarStyle = 'Minimal';

  int _scrobbleThreshold = 75;

  String _youtubeMusicQuality = 'adaptive';
  String _youtubeMusicFormat = 'Any';

  String _downloadQuality = 'AAC 320kbps';
  String _androidDownloadFolder = '/storage/emulated/0/Music/ZYPMusic';
  String _bulkDownloadMethod = 'ZIP Archive';
  bool _forceZipAsBlob = false;

  bool _searchSourceYoutube = true;
  bool _searchSourceYTMusic = true;
  String _explicitFilter = 'both';

  String _spotifyClientId = '';
  String _spotifyClientSecret = '';

  String? _preferredGl;

  int get prebufferCount => _prebufferCount;
  AudioQuality get audioQuality => _audioQuality;

  String get spotifyClientId => _spotifyClientId;
  String get spotifyClientSecret => _spotifyClientSecret;

  String? get preferredGl => _preferredGl;

  /// Returns the prebuffer count clamped to the supported 1..5 range.
  int get prebufferCountClamped =>
      _prebufferCount.clamp(minPrebufferCount, maxPrebufferCount);

  String get theme => _theme;

  bool get showRecommendedSongs => _showRecommendedSongs;
  bool get showRecommendedAlbums => _showRecommendedAlbums;
  bool get showRecommendedArtists => _showRecommendedArtists;
  bool get showJumpBackIn => _showJumpBackIn;
  bool get showEditorsPicks => _showEditorsPicks;
  bool get shuffleEditorsPicks => _shuffleEditorsPicks;
  bool get showTrendingNow => _showTrendingNow;
  bool get showSuggestedArtists => _showSuggestedArtists;
  bool get showStartListening => _showStartListening;
  bool get showTopArtists => _showTopArtists;
  bool get showPopularAlbums => _showPopularAlbums;

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
  String get youtubeMusicFormat => _youtubeMusicFormat;

  String get downloadQuality => _downloadQuality;
  String get androidDownloadFolder => _androidDownloadFolder;
  String get bulkDownloadMethod => _bulkDownloadMethod;
  bool get forceZipAsBlob => _forceZipAsBlob;

  bool get searchSourceYoutube => _searchSourceYoutube;
  bool get searchSourceYTMusic => _searchSourceYTMusic;
  String get explicitFilter => _explicitFilter;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _prebufferCount = (prefs.getInt(_keyPrebufferCount) ?? 3)
        .clamp(minPrebufferCount, maxPrebufferCount);
    final qualityStr = prefs.getString(_keyAudioQuality);
    _audioQuality = qualityStr != null
        ? AudioQuality.values.firstWhere((q) => q.name == qualityStr,
            orElse: () => AudioQuality.adaptive)
        : AudioQuality.adaptive;
        
    _theme = prefs.getString(_keyTheme) ?? 'Dark';
    
    _showRecommendedSongs = prefs.getBool(_keyShowRecommendedSongs) ?? true;
    _showRecommendedAlbums = prefs.getBool(_keyShowRecommendedAlbums) ?? true;
    _showRecommendedArtists = prefs.getBool(_keyShowRecommendedArtists) ?? true;
    _showJumpBackIn = prefs.getBool(_keyShowJumpBackIn) ?? true;
    _showEditorsPicks = prefs.getBool(_keyShowEditorsPicks) ?? true;
    _shuffleEditorsPicks = prefs.getBool(_keyShuffleEditorsPicks) ?? false;

    _showTrendingNow = prefs.getBool(_keyShowTrendingNow) ?? true;
    _showSuggestedArtists = prefs.getBool(_keyShowSuggestedArtists) ?? true;
    _showStartListening = prefs.getBool(_keyShowStartListening) ?? true;
    _showTopArtists = prefs.getBool(_keyShowTopArtists) ?? true;
    _showPopularAlbums = prefs.getBool(_keyShowPopularAlbums) ?? true;

    _dynamicAccentColor = prefs.getBool(_keyDynamicAccentColor) ?? true;
    _visualizerStyle = prefs.getString(_keyVisualizerStyle) ?? 'Bars';
    _invertSeekbarColor = prefs.getBool(_keyInvertSeekbarColor) ?? false;
    _seekbarStyle = prefs.getString(_keySeekbarStyle) ?? 'Minimal';

    _searchSourceYoutube = prefs.getBool(_keySearchSourceYoutube) ?? true;
    _searchSourceYTMusic = prefs.getBool(_keySearchSourceYTMusic) ?? true;
    _explicitFilter = prefs.getString(_keyExplicitFilter) ?? 'both';

    _scrobbleThreshold = prefs.getInt(_keyScrobbleThreshold) ?? 75;

    _youtubeMusicQuality = prefs.getString(_keyYoutubeMusicQuality) ?? 'adaptive';
    _youtubeMusicFormat = prefs.getString(_keyYoutubeMusicFormat) ?? 'Any';

    _downloadQuality = prefs.getString(_keyDownloadQuality) ?? 'AAC 320kbps';
    _androidDownloadFolder = prefs.getString(_keyAndroidDownloadFolder) ?? '/storage/emulated/0/Music/ZYPMusic';
    _bulkDownloadMethod = prefs.getString(_keyBulkDownloadMethod) ?? 'ZIP Archive';
    _forceZipAsBlob = prefs.getBool(_keyForceZipAsBlob) ?? false;
        
    _spotifyClientId = prefs.getString(_keySpotifyClientId) ?? '';
    _spotifyClientSecret = prefs.getString(_keySpotifyClientSecret) ?? '';

    final gl = prefs.getString(_keyPreferredGl);
    _preferredGl = (gl != null && gl.isNotEmpty) ? gl : null;

    notifyListeners();
  }

  Future<void> setSpotifyClientId(String id) async {
    _spotifyClientId = id.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpotifyClientId, _spotifyClientId);
    notifyListeners();
  }

  Future<void> setSpotifyClientSecret(String secret) async {
    _spotifyClientSecret = secret.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpotifyClientSecret, _spotifyClientSecret);
    notifyListeners();
  }

  Future<void> setPreferredGl(String code) async {
    _preferredGl = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreferredGl, code);
    notifyListeners();
  }

  Future<void> setPrebufferCount(int count) async {
    _prebufferCount = count.clamp(minPrebufferCount, maxPrebufferCount);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPrebufferCount, _prebufferCount);
    notifyListeners();
  }

  Future<void> setAudioQuality(AudioQuality quality) async {
    _audioQuality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioQuality, quality.name);
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
      case _keyShowTrendingNow: _showTrendingNow = value; break;
      case _keyShowSuggestedArtists: _showSuggestedArtists = value; break;
      case _keyShowStartListening: _showStartListening = value; break;
      case _keyShowTopArtists: _showTopArtists = value; break;
      case _keyShowPopularAlbums: _showPopularAlbums = value; break;
      case _keyDynamicAccentColor: _dynamicAccentColor = value; break;
      case _keyForceZipAsBlob: _forceZipAsBlob = value; break;
      case _keySearchSourceYoutube: _searchSourceYoutube = value; break;
      case _keySearchSourceYTMusic: _searchSourceYTMusic = value; break;
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
      case _keyYoutubeMusicFormat: _youtubeMusicFormat = value; break;
      case _keyDownloadQuality: _downloadQuality = value; break;
      case _keyAndroidDownloadFolder: _androidDownloadFolder = value; break;
      case _keyBulkDownloadMethod: _bulkDownloadMethod = value; break;
      case _keyExplicitFilter: _explicitFilter = value; break;
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
}
