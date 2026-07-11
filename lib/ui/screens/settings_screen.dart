import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../presentation/providers/miniplayer_visibility_provider.dart';
import '../../core/utils/app_logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../presentation/providers/settings_provider.dart';
import '../../service/oauth_service.dart';
import 'youtube_login_webview.dart';
import '../../core/services/audio_cache_service.dart';
import '../../core/services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          elevation: 0,
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelColor: Theme.of(context).colorScheme.onSurface,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
            dividerColor: Color(0xFF2A2A2A),
            tabs: [
              Tab(text: "Appearance"),
              Tab(text: "Interface"),
              Tab(text: "Scrobbling"),
              Tab(text: "Audio"),
              Tab(text: "Downloads"),
              Tab(text: "System"),
              Tab(text: "About"),
            ],
          ),
        ),
        body: Consumer<SettingsProvider>(
          builder: (context, provider, child) {
            return TabBarView(
              children: [
                _buildAppearanceTab(provider),
                _buildInterfaceTab(provider, context),
                _buildScrobblingTab(provider, context),
                _buildAudioTab(provider, context),
                _buildDownloadsTab(provider, context),
                _buildSystemTab(provider, context),
                _buildAboutTab(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppearanceTab(SettingsProvider provider) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Colors'),
        _buildSwitchTile(
          'Dynamic Accent Color',
          provider.dynamicAccentColor,
          (v) => provider.setBoolSetting('dynamicAccentColor', v),
        ),
        _buildSwitchTile(
          'Invert Seekbar Color',
          provider.invertSeekbarColor,
          (v) => provider.setInvertSeekbarColor(v),
        ),
        const SizedBox(height: 24),

        _buildDropdownSetting<String>(
          title: 'Seekbar Style',
          subtitle: 'Choose the visual style of the audio progress bar.',
          value: provider.seekbarStyle,
          items: const [
            DropdownMenuItem(value: 'Gradient', child: Text('Gradient')),
            DropdownMenuItem(value: 'Minimal', child: Text('Minimal')),
            DropdownMenuItem(value: 'Wavy', child: Text('Wavy')),
            DropdownMenuItem(value: 'Segmented', child: Text('Segmented')),
          ],
          onChanged: (val) {
            if (val != null) provider.setSeekbarStyle(val);
          },
        ),
      ],
    );
  }

  Widget _buildInterfaceTab(SettingsProvider provider, BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Home Screen Elements'),
        _buildSwitchTile('Show Suggested Songs', provider.showRecommendedSongs, (v) => provider.setBoolSetting('showRecommendedSongs', v)),
        _buildSwitchTile('Show Featured Albums', provider.showRecommendedAlbums, (v) => provider.setBoolSetting('showRecommendedAlbums', v)),
        _buildSwitchTile('Show Favourite Artists', provider.showRecommendedArtists, (v) => provider.setBoolSetting('showRecommendedArtists', v)),
        _buildSwitchTile('Show Liked Songs', provider.showJumpBackIn, (v) => provider.setBoolSetting('showJumpBackIn', v)),
        _buildSwitchTile('Show Global Hot', provider.showEditorsPicks, (v) => provider.setBoolSetting('showEditorsPicks', v)),
        _buildSwitchTile('Shuffle Global Hot', provider.shuffleEditorsPicks, (v) => provider.setBoolSetting('shuffleEditorsPicks', v)),
        const SizedBox(height: 24),
        _buildSectionHeader('Music Now Elements'),
        _buildSwitchTile('Show Trending Now', provider.showTrendingNow, (v) => provider.setBoolSetting('showTrendingNow', v)),
        _buildSwitchTile('Show Suggested Artists', provider.showSuggestedArtists, (v) => provider.setBoolSetting('showSuggestedArtists', v)),
        _buildSwitchTile('Show Start Listening', provider.showStartListening, (v) => provider.setBoolSetting('showStartListening', v)),
        _buildSwitchTile('Show Top Artists', provider.showTopArtists, (v) => provider.setBoolSetting('showTopArtists', v)),
        _buildSwitchTile('Show Popular Albums & Singles', provider.showPopularAlbums, (v) => provider.setBoolSetting('showPopularAlbums', v)),
        const SizedBox(height: 24),
        _buildSectionHeader('Search Sources'),
        _buildSwitchTile('YouTube', provider.searchSourceYoutube, (v) => provider.setBoolSetting('searchSourceYoutube', v)),
        _buildSwitchTile('YouTube Music', provider.searchSourceYTMusic, (v) => provider.setBoolSetting('searchSourceYTMusic', v)),
      ],
    );
  }


  Widget _buildScrobblingTab(SettingsProvider provider, BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Scrobble Threshold'),
        _buildSliderSetting(
          title: 'Scrobble Threshold',
          subtitle: 'Percentage of track played before scrobbling.',
          value: provider.scrobbleThreshold.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          label: '${provider.scrobbleThreshold}%',
          onChanged: (val) {
            provider.setIntSetting('scrobbleThreshold', val.toInt());
          },
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Services'),
        ListTile(
          title: const Text('Last.fm'),
          subtitle: Text('Not connected', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: ElevatedButton(
            onPressed: () {
              OAuthService().connectLastFm();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F1F1F)),
            child: const Text('CONNECT', style: TextStyle(color: Colors.white)),
          ),
        ),
        ListTile(
          title: const Text('Libre.fm'),
          subtitle: Text('Not connected', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: ElevatedButton(
            onPressed: () {
              OAuthService().connectLibreFm();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F1F1F)),
            child: const Text('CONNECT', style: TextStyle(color: Colors.white)),
          ),
        ),
        ListTile(
          title: const Text('ListenBrainz'),
          subtitle: Text('Not connected', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: ElevatedButton(
            onPressed: () {
              OAuthService().connectListenBrainz();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F1F1F)),
            child: const Text('CONNECT', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioTab(SettingsProvider provider, BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Streaming Quality'),
        _buildDropdownSetting<String>(
          title: 'YouTube Music Quality',
          subtitle: 'Quality for YouTube streaming.',
          value: provider.youtubeMusicQuality,
          items: [
            const DropdownMenuItem(value: 'adaptive', child: Text('Adaptive (Auto)')),
            const DropdownMenuItem(value: 'yt48', child: Text('48 kbps Opus — data-saver')),
            const DropdownMenuItem(value: 'yt128', child: Text('128 kbps AAC — normal')),
            const DropdownMenuItem(value: 'yt256', child: Text('256 kbps AAC — high')),
          ],
          onChanged: (val) {
            if (val != null) provider.setStringSetting('youtubeMusicQuality', val);
          },
        ),
        _buildDropdownSetting<String>(
          title: 'Explicit Content Filter',
          subtitle: 'Choose which versions of tracks to play.',
          value: provider.explicitFilter,
          items: [
            const DropdownMenuItem(value: 'both', child: Text('Both')),
            const DropdownMenuItem(value: 'clean', child: Text('Clean Only')),
            const DropdownMenuItem(value: 'explicit', child: Text('Explicit Only')),
          ],
          onChanged: (val) {
            if (val != null) provider.setStringSetting('explicitFilter', val);
          },
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Caching & Prebuffer'),
        _buildSliderSetting(
          title: 'Pre-buffer Count',
          subtitle: 'Number of upcoming tracks to preload (1-5).',
          value: provider.prebufferCountClamped.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          label: provider.prebufferCountClamped.toString(),
          onChanged: (val) {
            provider.setPrebufferCount(val.toInt());
          },
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Accounts'),
        ListTile(
          title: const Text('YouTube'),
          subtitle: Text('Not connected', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const YoutubeLoginWebview()));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F1F1F)),
            child: const Text('CONNECT', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadsTab(SettingsProvider provider, BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Download Settings'),
        _buildDropdownSetting<String>(
          title: 'Download Quality',
          subtitle: 'Quality format for downloaded files.',
          value: provider.downloadQuality,
          items: [
            const DropdownMenuItem(value: 'AAC 320kbps', child: Text('AAC 320kbps')),
            const DropdownMenuItem(value: 'FLAC Lossless', child: Text('FLAC Lossless')),
            const DropdownMenuItem(value: 'M4A 128kbps', child: Text('M4A 128kbps')),
          ],
          onChanged: (val) {
            if (val != null) provider.setStringSetting('downloadQuality', val);
          },
        ),
        ListTile(
          title: const Text('Android Download Folder'),
          subtitle: Text(provider.androidDownloadFolder, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(PhosphorIconsRegular.x, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                onPressed: () {
                  provider.setStringSetting('androidDownloadFolder', '');
                },
              ),
              IconButton(
                icon: Icon(PhosphorIconsRegular.folderSimple, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                onPressed: () async {
                  if (await Permission.manageExternalStorage.isDenied) {
                    await Permission.manageExternalStorage.request();
                  }
                  if (await Permission.storage.isDenied) {
                    await Permission.storage.request();
                  }
                  
                  final Directory rootDir = Platform.isAndroid 
                      ? Directory('/storage/emulated/0') 
                      : await getApplicationDocumentsDirectory();

                  String? selectedDirectory = await FilesystemPicker.open(
                    title: 'Save to folder',
                    context: context,
                    rootDirectory: rootDir,
                    fsType: FilesystemType.folder,
                    pickText: 'Save here',
                    folderIconColor: Theme.of(context).colorScheme.primary,
                  );

                  if (selectedDirectory != null) {
                    provider.setStringSetting('androidDownloadFolder', selectedDirectory);
                  }
                },
              ),
            ],
          ),
        ),
        _buildDropdownSetting<String>(
          title: 'Bulk Download Method',
          subtitle: 'How to handle downloading multiple items.',
          value: provider.bulkDownloadMethod,
          items: [
            const DropdownMenuItem(value: 'ZIP Archive', child: Text('ZIP Archive')),
            const DropdownMenuItem(value: 'Individual Files', child: Text('Individual Files')),
          ],
          onChanged: (val) {
            if (val != null) provider.setStringSetting('bulkDownloadMethod', val);
          },
        ),
        _buildSwitchTile('Force ZIP as Blob', provider.forceZipAsBlob, (v) => provider.setBoolSetting('forceZipAsBlob', v)),
      ],
    );
  }

  Widget _buildSystemTab(SettingsProvider provider, BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Spotify API Integration'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Add your Spotify Client ID and Secret to enable accurate BPM, Energy, and Genre tracking for the Smart DJ engine.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: TextFormField(
            initialValue: provider.spotifyClientId,
            decoration: const InputDecoration(
              labelText: 'Spotify Client ID',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => provider.setSpotifyClientId(val),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: TextFormField(
            initialValue: provider.spotifyClientSecret,
            decoration: const InputDecoration(
              labelText: 'Spotify Client Secret',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            onChanged: (val) => provider.setSpotifyClientSecret(val),
          ),
        ),
        const Divider(height: 32),
        const Divider(height: 32),
        _buildSectionHeader('System & Storage'),
        ListTile(
          title: const Text('Disable Battery Optimization'),
          subtitle: Text('Prevent Android from killing the app in the background to ensure uninterrupted playback.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: Icon(PhosphorIconsRegular.batteryWarning, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
          onTap: () async {
            if (await Permission.ignoreBatteryOptimizations.isDenied) {
              await Permission.ignoreBatteryOptimizations.request();
            }
          },
        ),
        ListTile(
          title: const Text('Check for Updates'),
          subtitle: Text('Check if a newer version of ZYPMusic is available on GitHub.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: Icon(PhosphorIconsRegular.downloadSimple, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
          onTap: () => UpdateService.checkForUpdatesManual(context),
        ),
        ListTile(
          title: const Text('Clear Cache & Reset Data', style: TextStyle(color: Colors.red)),
          subtitle: Text('Removes all downloaded audio cache and resets user settings to default.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: const Icon(PhosphorIconsRegular.trash, color: Colors.red),
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1F1F1F),
                title: const Text('Clear Cache?', style: TextStyle(color: Colors.white)),
                content: const Text('This will delete all cached audio and reset settings. This action cannot be undone.', style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                    child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                  TextButton(
                    child: const Text('CLEAR', style: TextStyle(color: Colors.red)),
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              if (Platform.isAndroid) {
                try {
                  const channel = MethodChannel('com.benjamindarko.monochrome/system');
                  await channel.invokeMethod('clearAppData');
                } catch (e) {
                  // Fallback if channel invocation fails
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  await AudioCacheService().clearCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cache cleared. Please restart the app.')),
                    );
                  }
                }
              } else {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                await AudioCacheService().clearCache();
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache cleared. Please restart the app to apply default settings.')),
                  );
                }
              }
            }
          },
        ),
        const Divider(height: 32),
        _buildSectionHeader('Diagnostics'),
        ListTile(
          title: const Text('Export Application Logs'),
          subtitle: Text('Share the raw text logs to help debug issues.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: Icon(PhosphorIconsRegular.shareNetwork, color: Theme.of(context).colorScheme.onSurface),
          onTap: () async {
            final file = AppLogger.logFile;
            if (file != null && await file.exists()) {
              await Share.shareXFiles([XFile(file.path)], text: 'ZYPMusic App Logs');
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log file not found or empty.')));
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
      activeColor: Theme.of(context).colorScheme.primary,
      inactiveTrackColor: Colors.white24,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDropdownSetting<T>({
    required String title,
    required String subtitle,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(color: Colors.white),
            icon: const Icon(PhosphorIconsRegular.caretDown, color: Colors.white54),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
      title: Text(title),
          subtitle: Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          trailing: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.white24,
            thumbColor: Theme.of(context).colorScheme.primary,
            valueIndicatorTextStyle: TextStyle(color: Colors.black),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildAboutTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    PhosphorIconsRegular.musicNotes,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'ZYP Music',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version 1.3.1',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _buildSectionHeader('About the Project'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'ZYP Music is a premium open-source native audio streaming application designed for Android. It features high-fidelity YouTube audio streaming, robust offline caching and download capabilities, gapless crossfade transitions, synchronized lyrics, and smart Auto DJ seed recommendations for endless music playback.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Links'),
        ListTile(
          title: const Text('GitHub Repository'),
          subtitle: Text(
            'github.com/BENJAMINDARKO/zyp_music',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
          ),
          leading: Icon(PhosphorIconsRegular.githubLogo, color: Theme.of(context).colorScheme.onSurface),
          trailing: Icon(PhosphorIconsRegular.arrowSquareOut, color: Theme.of(context).colorScheme.primary),
          onTap: () async {
            final uri = Uri.parse('https://github.com/BENJAMINDARKO/zyp_music');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open repository link.')),
                );
              }
            }
          },
        ),
      ],
    );
  }
}
