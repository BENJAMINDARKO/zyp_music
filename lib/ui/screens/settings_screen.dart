import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../presentation/providers/miniplayer_visibility_provider.dart';
import '../../core/utils/app_logger.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../presentation/providers/settings_provider.dart';
import '../../core/constants/audio_quality.dart';
import '../../service/oauth_service.dart';
import 'youtube_login_webview.dart';
import '../../core/services/audio_cache_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<MiniplayerVisibilityProvider>().hide();
    });
  }

  @override
  void dispose() {
    Future.microtask(() {
      if (mounted) context.read<MiniplayerVisibilityProvider>().show();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          elevation: 0,
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Color(0xFFEAB308),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            dividerColor: Color(0xFF2A2A2A),
            tabs: [
              Tab(text: "Appearance"),
              Tab(text: "Interface"),
              Tab(text: "Scrobbling"),
              Tab(text: "Audio"),
              Tab(text: "Downloads"),
              Tab(text: "Connections"),
              Tab(text: "System"),
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
                _buildConnectionsTab(provider, context),
                _buildSystemTab(provider, context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppearanceTab(SettingsProvider provider) {
    final themes = ['System', 'Black', 'White', 'Dark', 'Ocean', 'Purple', 'Forest', 'Mocha', 'Machiatto', 'Frappé'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Theme'),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: themes.map((t) {
            final isSelected = provider.theme == t;
            return ChoiceChip(
              label: Text(t, style: TextStyle(color: isSelected ? Colors.black : Colors.white)),
              selected: isSelected,
              selectedColor: const Color(0xFFEAB308),
              backgroundColor: const Color(0xFF1F1F1F),
              onSelected: (selected) {
                if (selected) provider.setTheme(t);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
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
        _buildSwitchTile('Show Recommended Songs', provider.showRecommendedSongs, (v) => provider.setBoolSetting('showRecommendedSongs', v)),
        _buildSwitchTile('Show Recommended Albums', provider.showRecommendedAlbums, (v) => provider.setBoolSetting('showRecommendedAlbums', v)),
        _buildSwitchTile('Show Recommended Artists', provider.showRecommendedArtists, (v) => provider.setBoolSetting('showRecommendedArtists', v)),
        _buildSwitchTile('Show Jump Back In', provider.showJumpBackIn, (v) => provider.setBoolSetting('showJumpBackIn', v)),
        _buildSwitchTile('Show Editor\'s Picks', provider.showEditorsPicks, (v) => provider.setBoolSetting('showEditorsPicks', v)),
        _buildSwitchTile('Shuffle Editor\'s Picks', provider.shuffleEditorsPicks, (v) => provider.setBoolSetting('shuffleEditorsPicks', v)),
        const SizedBox(height: 24),
        _buildSectionHeader('Search Sources'),
        _buildSwitchTile('YouTube', provider.searchSourceYoutube, (v) => provider.setBoolSetting('searchSourceYoutube', v)),
        _buildSwitchTile('YouTube Music', provider.searchSourceYTMusic, (v) => provider.setBoolSetting('searchSourceYTMusic', v)),
        _buildSwitchTile('Tidal', provider.searchSourceTidal, (v) => provider.setBoolSetting('searchSourceTidal', v)),
        const SizedBox(height: 24),
        _buildSectionHeader('System & Storage'),
        ListTile(
          title: const Text('Disable Battery Optimization', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Prevent Android from killing the app in the background to ensure uninterrupted playback.', style: TextStyle(color: Colors.white54)),
          trailing: const Icon(Icons.battery_alert, color: Colors.white54),
          onTap: () async {
            if (await Permission.ignoreBatteryOptimizations.isDenied) {
              await Permission.ignoreBatteryOptimizations.request();
            }
          },
        ),
        ListTile(
          title: const Text('Clear Cache & Reset Data', style: TextStyle(color: Colors.red)),
          subtitle: const Text('Removes all downloaded audio cache and resets user settings to default.', style: TextStyle(color: Colors.white54)),
          trailing: const Icon(Icons.delete_forever, color: Colors.red),
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
          title: const Text('Last.fm', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Not connected', style: TextStyle(color: Colors.white54)),
          trailing: ElevatedButton(
            onPressed: () {
              OAuthService().connectLastFm();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F1F1F)),
            child: const Text('CONNECT', style: TextStyle(color: Colors.white)),
          ),
        ),
        ListTile(
          title: const Text('Libre.fm', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Not connected', style: TextStyle(color: Colors.white54)),
          trailing: ElevatedButton(
            onPressed: () {
              OAuthService().connectLibreFm();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F1F1F)),
            child: const Text('CONNECT', style: TextStyle(color: Colors.white)),
          ),
        ),
        ListTile(
          title: const Text('ListenBrainz', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Not connected', style: TextStyle(color: Colors.white54)),
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
        _buildSectionHeader('Streaming Engine'),
        _buildDropdownSetting<StreamSource>(
          title: 'Default Audio Source',
          subtitle: 'Choose which engine to use for playback.',
          value: provider.streamSource,
          items: const [
            DropdownMenuItem(value: StreamSource.youtube, child: Text('YouTube Music')),
            DropdownMenuItem(value: StreamSource.tidal, child: Text('Tidal')),
          ],
          onChanged: (val) {
            if (val != null) provider.setStreamSource(val);
          },
        ),
        SwitchListTile(
          title: const Text('Enable Source Fallback', style: TextStyle(color: Colors.white)),
          subtitle: const Text('If the default engine fails to load a stream, attempt to find and play it on the other engine.', style: TextStyle(color: Colors.white54)),
          value: provider.enableSourceFallback,
          activeColor: const Color(0xFFEAB308),
          onChanged: (val) {
            provider.setEnableSourceFallback(val);
          },
        ),
        const SizedBox(height: 24),
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
          title: 'Tidal Streaming Quality',
          subtitle: 'Quality for Tidal streaming.',
          value: provider.tidalStreamingQuality,
          items: [
            const DropdownMenuItem(value: 'tidalLow', child: Text('AAC 96kbps (Low)')),
            const DropdownMenuItem(value: 'tidalHigh', child: Text('AAC 320kbps (High)')),
            const DropdownMenuItem(value: 'tidalLossless', child: Text('Lossless 16-bit')),
            const DropdownMenuItem(value: 'tidalHiRes', child: Text('HiRes 24-bit Lossless')),
          ],
          onChanged: (val) {
            if (val != null) provider.setStringSetting('tidalStreamingQuality', val);
          },
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Caching & Prebuffer'),
        _buildSliderSetting(
          title: 'Pre-buffer Count',
          subtitle: 'Number of upcoming tracks to preload.',
          value: provider.prebufferCount.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          label: provider.prebufferCount.toString(),
          onChanged: (val) {
            provider.setPrebufferCount(val.toInt());
          },
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Accounts'),
        ListTile(
          title: const Text('YouTube', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Not connected', style: TextStyle(color: Colors.white54)),
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
          title: const Text('Android Download Folder', style: TextStyle(color: Colors.white)),
          subtitle: Text(provider.androidDownloadFolder, style: const TextStyle(color: Colors.white54)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.clear, color: Colors.white54), onPressed: () {}),
              IconButton(
                icon: const Icon(Icons.folder, color: Colors.white54),
                onPressed: () async {
                  String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
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

  Widget _buildConnectionsTab(SettingsProvider provider, BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('Tidal API Instances'),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54),
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshing instances from remote...')));
                await provider.refreshTidalInstances();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Instances refreshed!')));
                }
              },
            ),
          ],
        ),
        ...provider.tidalApiInstances.map((url) => ListTile(
          title: Text(url, style: const TextStyle(color: Colors.white)),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => provider.removeTidalApiInstance(url),
          ),
        )),
        ListTile(
          title: const Text('Add API Instance...', style: TextStyle(color: Color(0xFFEAB308))),
          leading: const Icon(Icons.add, color: Color(0xFFEAB308)),
          onTap: () => _showAddInstanceDialog(context, provider, true),
        ),
        
        const SizedBox(height: 24),
        _buildSectionHeader('Tidal Streaming Instances'),
        ...provider.tidalStreamingInstances.map((url) => ListTile(
          title: Text(url, style: const TextStyle(color: Colors.white)),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => provider.removeTidalStreamingInstance(url),
          ),
        )),
        ListTile(
          title: const Text('Add Streaming Instance...', style: TextStyle(color: Color(0xFFEAB308))),
          leading: const Icon(Icons.add, color: Color(0xFFEAB308)),
          onTap: () => _showAddInstanceDialog(context, provider, false),
        ),
      ],
    );
  }

  void _showAddInstanceDialog(BuildContext context, SettingsProvider provider, bool isApi) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: Text(isApi ? 'Add API Instance' : 'Add Streaming Instance', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'https://...',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text('ADD', style: TextStyle(color: Color(0xFFEAB308))),
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                if (isApi) {
                  provider.addTidalApiInstance(url);
                } else {
                  provider.addTidalStreamingInstance(url);
                }
              }
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSystemTab(SettingsProvider provider, BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Diagnostics'),
        ListTile(
          title: const Text('Export Application Logs', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Share the raw text logs to help debug issues.', style: TextStyle(color: Colors.white54)),
          trailing: const Icon(Icons.share, color: Colors.white),
          onTap: () async {
            final file = AppLogger.logFile;
            if (file != null && await file.exists()) {
              await Share.shareXFiles([XFile(file.path)], text: 'Monochrome App Logs');
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
      title: Text(title, style: const TextStyle(color: Colors.white)),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFFEAB308),
      inactiveTrackColor: Colors.white24,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFEAB308),
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
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
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
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
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
          title: Text(title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
          trailing: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        SliderTheme(
          data: const SliderThemeData(
            activeTrackColor: Color(0xFFEAB308),
            inactiveTrackColor: Colors.white24,
            thumbColor: Color(0xFFEAB308),
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
}
