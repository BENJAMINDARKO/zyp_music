import 'dart:io';
import 'dart:ui';
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
import '../../presentation/providers/equalizer_provider.dart';
import '../../service/auth_service.dart';
import '../../service/oauth_service.dart';
import '../../service/listenbrainz_service.dart';
import '../../data/datasources/remote/youtube_remote_datasource.dart';
import 'youtube_login_webview.dart';
import '../../core/services/audio_cache_service.dart';
import '../../core/services/update_service.dart';
import 'equalizer_screen.dart';
import 'search_screen.dart';
import '../widgets/aurora_glass.dart';
import '../../core/theme/app_theme.dart';

enum SettingsCategory {
  look,
  homeUi,
  audio,
  downloads,
  connections,
  system,
  about,
}

extension SettingsCategoryLabel on SettingsCategory {
  String get label {
    switch (this) {
      case SettingsCategory.look:
        return 'Look';
      case SettingsCategory.homeUi:
        return 'Home & UI';
      case SettingsCategory.audio:
        return 'Audio';
      case SettingsCategory.downloads:
        return 'Downloads';
      case SettingsCategory.connections:
        return 'Connections';
      case SettingsCategory.system:
        return 'System';
      case SettingsCategory.about:
        return 'About';
    }
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  MiniplayerVisibilityProvider? _visibilityProvider;
  SettingsCategory _selectedCategory = SettingsCategory.look;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityProvider?.hide();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visibilityProvider ??= context.read<MiniplayerVisibilityProvider>();
  }

  @override
  void dispose() {
    _visibilityProvider?.show();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Orbs for background Aurora
              Positioned(
                top: 40,
                left: -20,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZypAuroraColors.pink.withOpacity(0.12),
                  ),
                ),
              ),
              Positioned(
                top: 250,
                right: -40,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZypAuroraColors.cyan.withOpacity(0.10),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // Custom Header Top Bar
                    _buildTopBar(),
                    
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          // Settings Hero Card
                          _buildHeroCard(),
                          const SizedBox(height: 16),

                          // Horizontal scrollable Category Tabs (sticky-like, placed at start of content list)
                          _buildCategoryTabs(),
                          const SizedBox(height: 10),

                          // Current category content
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.05),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(_selectedCategory),
                              child: _buildCategoryContent(provider),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SettingIconButton(
            icon: PhosphorIconsRegular.caretLeft,
            onTap: () => Navigator.of(context).pop(),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'ZYP CONTROL DECK',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                  color: ZypAuroraColors.cyan.withOpacity(0.85),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SettingIconButton(
            icon: PhosphorIconsRegular.magnifyingGlass,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return AuroraGlass(
      borderRadius: 34,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildHeroTag('UNIFIED'),
                    const SizedBox(width: 8),
                    _buildHeroTag('AURORA'),
                  ],
                ),
                const SizedBox(height: 12),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1.5,
                      height: 1.0,
                      fontFamily: 'Inter',
                    ),
                    children: [
                      const TextSpan(text: 'Tune the whole ', style: TextStyle(color: Colors.white)),
                      TextSpan(
                        text: 'experience.',
                        style: TextStyle(
                          foreground: Paint()
                            ..shader = const LinearGradient(
                              colors: [Colors.white, ZypAuroraColors.cyan, ZypAuroraColors.pink, ZypAuroraColors.peach],
                            ).createShader(const Rect.fromLTWH(0, 0, 300, 40)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Appearance, interface, audio, downloads, connections, system tools, and project info in one glass control deck.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 13,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Animated orb representation
          Container(
            width: 106,
            height: 106,
            transform: Matrix4.rotationZ(0.08),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              color: Colors.white.withOpacity(0.13),
              boxShadow: [
                BoxShadow(
                  color: ZypAuroraColors.violet.withOpacity(0.25),
                  blurRadius: 44,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                gradient: const SweepGradient(
                  colors: [ZypAuroraColors.cyan, ZypAuroraColors.violet, ZypAuroraColors.pink, ZypAuroraColors.peach, ZypAuroraColors.cyan],
                ),
              ),
              child: Center(
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF05040B).withOpacity(0.38),
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.17)),
        color: Colors.white.withOpacity(0.095),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: SettingsCategory.values.length,
        itemBuilder: (context, index) {
          final category = SettingsCategory.values[index];
          final isActive = _selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 9.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = category;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isActive ? Colors.transparent : Colors.white.withOpacity(0.11),
                  ),
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                        )
                      : null,
                  color: isActive ? null : Colors.white.withOpacity(0.065),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: ZypAuroraColors.cyan.withOpacity(0.16),
                            blurRadius: 28,
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  category.label,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF080711) : Colors.white.withOpacity(0.62),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryContent(SettingsProvider provider) {
    switch (_selectedCategory) {
      case SettingsCategory.look:
        return _buildLookContent(provider);
      case SettingsCategory.homeUi:
        return _buildHomeUiContent(provider);
      case SettingsCategory.audio:
        return _buildAudioContent(provider);
      case SettingsCategory.downloads:
        return _buildDownloadsContent(provider);
      case SettingsCategory.connections:
        return _buildConnectionsContent(provider);
      case SettingsCategory.system:
        return _buildSystemContent(provider);
      case SettingsCategory.about:
        return _buildAboutContent();
    }
  }

  // ---------------------------------------------------------------------------
  // Categories Page Builders
  // ---------------------------------------------------------------------------

  Widget _buildLookContent(SettingsProvider provider) {
    return Column(
      key: const ValueKey('look_content'),
      children: [
        SettingGroup(
          title: 'Color & motion',
          child: Column(
            children: [
              SettingRow(
                title: 'Dynamic Accent Color',
                subtitle: 'Tint Aurora surfaces from artwork and context.',
                glowColor: ZypAuroraColors.cyan,
                right: SettingSwitch(
                  value: provider.dynamicAccentColor,
                  onChanged: (v) => provider.setBoolSetting('dynamicAccentColor', v),
                ),
              ),
              SettingRow(
                title: 'Invert Seekbar Color',
                subtitle: 'Use light progress on darker artwork.',
                glowColor: ZypAuroraColors.violet,
                right: SettingSwitch(
                  value: provider.invertSeekbarColor,
                  onChanged: (v) => provider.setInvertSeekbarColor(v),
                ),
              ),
              SettingRow(
                title: 'Seekbar Style',
                subtitle: 'Default visual style for audio progress.',
                glowColor: ZypAuroraColors.pink,
                right: SettingSelectPill(
                  value: provider.seekbarStyle,
                  onTap: () => _showSeekbarStylePicker(provider),
                ),
              ),
              SettingRow(
                title: 'Glass Intensity',
                subtitle: 'Controls blur and opacity across the app.',
                glowColor: ZypAuroraColors.peach,
                right: SettingSelectPill(
                  value: 'High',
                  onTap: () {},
                ),
              ),
              SettingRow(
                title: 'Reduce Motion',
                subtitle: 'Minimize animated glows and transitions.',
                glowColor: ZypAuroraColors.lime,
                right: SettingSwitch(
                  value: false,
                  onChanged: (v) {},
                ),
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Theme presets',
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildPresetCard(
                    title: 'Aurora Default',
                    subtitle: 'Cyan, violet, pink, peach.',
                    glowColor: ZypAuroraColors.cyan,
                    isActive: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildPresetCard(
                    title: 'Warm Night',
                    subtitle: 'Peach, amber, soft violet.',
                    glowColor: ZypAuroraColors.peach,
                    isActive: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetCard({
    required String title,
    required String subtitle,
    required Color glowColor,
    required bool isActive,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isActive ? glowColor.withOpacity(0.35) : Colors.white.withOpacity(0.10),
        ),
        color: Colors.white.withOpacity(isActive ? 0.08 : 0.05),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -34,
            bottom: -40,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: glowColor.withOpacity(0.18),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.60),
                        fontSize: 11,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isActive ? 'Active' : 'Preview',
                  style: TextStyle(
                    color: isActive ? ZypAuroraColors.cyan : Colors.white.withOpacity(0.4),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeUiContent(SettingsProvider provider) {
    return Column(
      key: const ValueKey('home_ui_content'),
      children: [
        SettingGroup(
          title: 'Home modules',
          child: Column(
            children: [
              SettingRow(
                title: 'Show Suggested Songs',
                subtitle: 'Scrollable 2-column recommendation rail.',
                right: SettingSwitch(
                  value: provider.showRecommendedSongs,
                  onChanged: (v) => provider.setBoolSetting('showRecommendedSongs', v),
                ),
              ),
              SettingRow(
                title: 'Show Featured Albums',
                subtitle: 'Compact 2-row album rail.',
                right: SettingSwitch(
                  value: provider.showRecommendedAlbums,
                  onChanged: (v) => provider.setBoolSetting('showRecommendedAlbums', v),
                ),
              ),
              SettingRow(
                title: 'Show Favourite Artists',
                subtitle: 'Circular artist rail on Home.',
                right: SettingSwitch(
                  value: provider.showRecommendedArtists,
                  onChanged: (v) => provider.setBoolSetting('showRecommendedArtists', v),
                ),
              ),
              SettingRow(
                title: 'Show Liked Songs',
                subtitle: 'Compact row list.',
                right: SettingSwitch(
                  value: provider.showJumpBackIn,
                  onChanged: (v) => provider.setBoolSetting('showJumpBackIn', v),
                ),
              ),
              SettingRow(
                title: 'Show Global Hot',
                subtitle: 'Trending global feed.',
                right: SettingSwitch(
                  value: provider.showEditorsPicks,
                  onChanged: (v) => provider.setBoolSetting('showEditorsPicks', v),
                ),
              ),
              SettingRow(
                title: 'Shuffle Global Hot',
                subtitle: 'Randomize global chart order.',
                right: SettingSwitch(
                  value: provider.shuffleEditorsPicks,
                  onChanged: (v) => provider.setBoolSetting('shuffleEditorsPicks', v),
                ),
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Music Now modules',
          child: Column(
            children: [
              SettingRow(
                title: 'Show Trending Now',
                subtitle: 'Compact 3-row signal grid.',
                right: SettingSwitch(
                  value: provider.showTrendingNow,
                  onChanged: (v) => provider.setBoolSetting('showTrendingNow', v),
                ),
              ),
              SettingRow(
                title: 'Show Suggested Artists',
                subtitle: 'Circular artist discovery rail.',
                right: SettingSwitch(
                  value: provider.showSuggestedArtists,
                  onChanged: (v) => provider.setBoolSetting('showSuggestedArtists', v),
                ),
              ),
              SettingRow(
                title: 'Show Start Listening',
                subtitle: '2-column mood cards.',
                right: SettingSwitch(
                  value: provider.showStartListening,
                  onChanged: (v) => provider.setBoolSetting('showStartListening', v),
                ),
              ),
              SettingRow(
                title: 'Show Top Artists',
                subtitle: 'Circular artist rails under Music Now.',
                right: SettingSwitch(
                  value: provider.showTopArtists,
                  onChanged: (v) => provider.setBoolSetting('showTopArtists', v),
                ),
              ),
              SettingRow(
                title: 'Show Popular Albums & Singles',
                subtitle: 'Compact 2-row release rail.',
                right: SettingSwitch(
                  value: provider.showPopularAlbums,
                  onChanged: (v) => provider.setBoolSetting('showPopularAlbums', v),
                ),
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Search sources',
          child: Column(
            children: [
              SettingRow(
                title: 'YouTube',
                subtitle: 'Include YouTube results.',
                right: SettingSwitch(
                  value: provider.searchSourceYoutube,
                  onChanged: (v) => provider.setBoolSetting('searchSourceYoutube', v),
                ),
              ),
              SettingRow(
                title: 'YouTube Music',
                subtitle: 'Include YouTube Music results.',
                right: SettingSwitch(
                  value: provider.searchSourceYTMusic,
                  onChanged: (v) => provider.setBoolSetting('searchSourceYTMusic', v),
                ),
              ),
              SettingRow(
                title: 'Local Library',
                subtitle: 'Always search downloaded and saved music.',
                right: SettingSwitch(
                  value: true,
                  onChanged: (v) {},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAudioContent(SettingsProvider provider) {
    return Column(
      key: const ValueKey('audio_content'),
      children: [
        SettingGroup(
          title: 'Sound Tools',
          action: 'inline controls',
          child: Column(
            children: [
              const InlineEqualizerSettingCard(),
              SettingRow(
                title: 'Crossfade',
                subtitle: 'Smooth transition between tracks.',
                right: SettingSelectPill(
                  value: '8s',
                  onTap: () {},
                ),
              ),
              SettingRow(
                title: 'Playback Normalization',
                subtitle: 'Balance loud and quiet tracks automatically.',
                right: SettingSwitch(
                  value: false,
                  onChanged: (v) {},
                ),
              ),
              SettingRow(
                title: 'Audio Output Defaults',
                subtitle: 'Default behavior for speaker, Bluetooth, and wired outputs.',
                right: SettingIconButton(
                  icon: PhosphorIconsRegular.target,
                  onTap: () {},
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Audio Output Defaults tapped')),
                  );
                },
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Streaming',
          child: Column(
            children: [
              SettingRow(
                title: 'Streaming Quality',
                subtitle: 'Bitrate quality for YouTube streaming.',
                right: SettingSelectPill(
                  value: provider.youtubeMusicQuality == 'adaptive' ? 'Adaptive' : provider.youtubeMusicQuality.replaceAll('yt', '') + ' kbps',
                  onTap: () => _showBitratePicker(provider),
                ),
              ),
              SettingRow(
                title: 'Audio Streaming Format',
                subtitle: 'Preferred audio container format.',
                right: SettingSelectPill(
                  value: provider.youtubeMusicFormat == 'Any' ? 'Any' : provider.youtubeMusicFormat.toUpperCase(),
                  onTap: () => _showAudioFormatPicker(provider),
                ),
              ),
              SettingRow(
                title: 'Explicit Content Filter',
                subtitle: 'Choose which versions of tracks to play.',
                right: SettingSelectPill(
                  value: provider.explicitFilter == 'both' ? 'Both' : provider.explicitFilter == 'clean' ? 'Clean' : 'Explicit',
                  onTap: () => _showExplicitPicker(provider),
                ),
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Caching',
          child: SettingSlider(
            title: 'Pre-buffer Count',
            subtitle: 'Number of upcoming tracks to preload (1–5).',
            value: provider.prebufferCountClamped.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: provider.prebufferCountClamped.toString(),
            onChanged: (val) {
              provider.setPrebufferCount(val.toInt());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadsContent(SettingsProvider provider) {
    return Column(
      key: const ValueKey('downloads_content'),
      children: [
        SettingGroup(
          title: 'Download settings',
          child: Column(
            children: [
              SettingRow(
                title: 'Download Quality',
                subtitle: 'Quality format for downloaded files.',
                right: SettingSelectPill(
                  value: provider.downloadQuality,
                  onTap: () => _showDownloadQualityPicker(provider),
                ),
              ),
              SettingRow(
                title: 'Android Download Folder',
                subtitle: provider.androidDownloadFolder.isEmpty
                    ? 'Default download path'
                    : provider.androidDownloadFolder,
                right: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider.androidDownloadFolder.isNotEmpty) ...[
                      SettingIconButton(
                        icon: PhosphorIconsRegular.x,
                        onTap: () {
                          provider.setStringSetting('androidDownloadFolder', '');
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    SettingIconButton(
                      icon: PhosphorIconsRegular.folderSimple,
                      onTap: () async {
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
              SettingRow(
                title: 'Bulk Download Method',
                subtitle: 'How to handle downloading multiple items.',
                right: SettingSelectPill(
                  value: provider.bulkDownloadMethod,
                  onTap: () => _showBulkDownloadPicker(provider),
                ),
              ),
              SettingRow(
                title: 'Force ZIP as Blob',
                subtitle: 'Fallback export mode for restricted Android folders.',
                right: SettingSwitch(
                  value: provider.forceZipAsBlob,
                  onChanged: (v) => provider.setBoolSetting('forceZipAsBlob', v),
                ),
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Smart cache',
          child: Column(
            children: [
              SettingRow(
                title: 'Auto-cache favourites',
                subtitle: 'Keep liked tracks ready offline.',
                right: SettingSwitch(
                  value: true,
                  onChanged: (v) {},
                ),
              ),
              SettingRow(
                title: 'Cache limit',
                subtitle: 'Maximum audio cache size.',
                right: SettingSelectPill(
                  value: '4 GB',
                  onTap: () {},
                ),
              ),
              SettingRow(
                title: 'Clear temporary cache',
                subtitle: 'Remove generated temporary audio files.',
                right: SettingIconButton(
                  icon: PhosphorIconsRegular.trash,
                  onTap: () async {
                    await AudioCacheService().clearCache();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Temporary audio cache cleared!')),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionsContent(SettingsProvider provider) {
    return Column(
      key: const ValueKey('connections_content'),
      children: [
        SettingGroup(
          title: 'Scrobbling',
          child: Column(
            children: [
              SettingSlider(
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
              SettingRow(
                title: 'ListenBrainz',
                subtitle: 'Token-based scrobbling',
                right: _buildListenBrainzButton(context),
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Streaming accounts',
          child: Column(
            children: [
              FutureBuilder<bool>(
                future: AuthService().validateYoutubeCookies(),
                initialData: false,
                builder: (ctx, snap) {
                  final connected = snap.data ?? false;
                  return SettingRow(
                    title: 'YouTube',
                    subtitle: connected ? 'Connected' : 'Not connected',
                    right: connected
                        ? _buildDisconnectButton(
                            onTap: () async {
                              await AuthService().clearCookies();
                              await YoutubeRemoteDataSource.instance?.refreshNetworkClientHeaders();
                              setState(() {});
                            },
                          )
                        : _buildConnectButton(
                            onTap: () async {
                              final result = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(builder: (_) => const YoutubeLoginWebview()),
                              );
                              if (result == true) {
                                await YoutubeRemoteDataSource.instance?.refreshNetworkClientHeaders();
                                setState(() {});
                              }
                            },
                          ),
                  );
                },
              ),
              SettingRow(
                title: 'Spotify API Integration',
                subtitle: 'Used for BPM, energy, and genre tracking for Smart DJ.',
                right: const Icon(PhosphorIconsRegular.arrowUpRight, color: Colors.white54, size: 20),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextFormField(
                  initialValue: provider.spotifyClientId,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Spotify Client ID',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: ZypAuroraColors.cyan),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.04),
                  ),
                  onChanged: (val) => provider.setSpotifyClientId(val),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: TextFormField(
                  initialValue: provider.spotifyClientSecret,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Spotify Client Secret',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: ZypAuroraColors.cyan),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.04),
                  ),
                  onChanged: (val) => provider.setSpotifyClientSecret(val),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: const LinearGradient(
            colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
          ),
        ),
        alignment: Alignment.center,
        child: const Text(
          'CONNECT',
          style: TextStyle(
            color: Color(0xFF080711),
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildDisconnectButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Colors.redAccent.withOpacity(0.12),
          border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
        ),
        alignment: Alignment.center,
        child: const Text(
          'DISCONNECT',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildListenBrainzButton(BuildContext context) {
    return FutureBuilder<bool>(
      future: ListenBrainzService().hasToken(),
      builder: (ctx, snap) {
        final connected = snap.data ?? false;
        if (connected) {
          return GestureDetector(
            onTap: () => _showListenBrainzTokenDialog(context, hasToken: true),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
              ),
              alignment: Alignment.center,
              child: const Text(
                'DISCONNECT',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          );
        }
        return _buildConnectButton(
          onTap: () => _showListenBrainzTokenDialog(context, hasToken: false),
        );
      },
    );
  }

  Future<void> _showListenBrainzTokenDialog(BuildContext context,
      {required bool hasToken}) async {
    final controller = TextEditingController();
    if (hasToken) {
      controller.text = (await ListenBrainzService().getToken()) ?? '';
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ListenBrainz Token',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your ListenBrainz API token from\n'
              'https://listenbrainz.org/settings/',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Paste your token here',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF2A2A3E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (hasToken)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Disconnect',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save',
                style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      ),
    );

    if (saved == null) return;

    if (saved == false) {
      await ListenBrainzService().clearToken();
    } else {
      final token = controller.text.trim();
      if (token.isEmpty) return;
      await ListenBrainzService().setToken(token);
    }
    if (context.mounted) setState(() {});
  }

  Widget _buildSystemContent(SettingsProvider provider) {
    return Column(
      key: const ValueKey('system_content'),
      children: [
        SettingGroup(
          title: 'System & storage',
          child: Column(
            children: [
              SettingRow(
                title: 'Disable Battery Optimization',
                subtitle: 'Prevent Android from killing playback in the background.',
                right: SettingIconButton(
                  icon: PhosphorIconsRegular.batteryWarning,
                  onTap: () async {
                    if (await Permission.ignoreBatteryOptimizations.isDenied) {
                      await Permission.ignoreBatteryOptimizations.request();
                    }
                  },
                ),
              ),
              SettingRow(
                title: 'Check for Updates',
                subtitle: 'Check GitHub for a newer ZYP Music version.',
                right: SettingIconButton(
                  icon: PhosphorIconsRegular.downloadSimple,
                  onTap: () => UpdateService.checkForUpdatesManual(context),
                ),
              ),
              SettingRow(
                title: 'Music Region',
                subtitle: provider.preferredGl != null
                    ? SettingsProvider.countryOptions.firstWhere(
                        (c) => c['code'] == provider.preferredGl,
                        orElse: () => {'name': provider.preferredGl!},
                      )['name']!
                    : 'Not set',
                right: SettingIconButton(
                  icon: PhosphorIconsRegular.globeHemisphereWest,
                  onTap: () => _showRegionPicker(provider),
                ),
              ),
              SettingRow(
                title: 'Clear Cache & Reset Data',
                subtitle: 'Removes downloaded audio cache and resets settings.',
                danger: true,
                right: SettingIconButton(
                  icon: PhosphorIconsRegular.trash,
                  color: Colors.redAccent,
                  onTap: () => _handleClearCacheAndReset(),
                ),
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Diagnostics',
          child: Column(
            children: [
              SettingRow(
                title: 'Export Application Logs',
                subtitle: 'Share raw text logs to help debug issues.',
                right: SettingIconButton(
                  icon: PhosphorIconsRegular.shareNetwork,
                  onTap: () async {
                    final file = AppLogger.logFile;
                    if (file != null && await file.exists()) {
                      await Share.shareXFiles([XFile(file.path)], text: 'ZYPMusic App Logs');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Log file not found or empty.')),
                      );
                    }
                  },
                ),
              ),
              SettingRow(
                title: 'Debug audio pipeline',
                subtitle: 'Show playback engine and buffer diagnostics.',
                right: SettingSwitch(
                  value: false,
                  onChanged: (v) {},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleClearCacheAndReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AlertDialog(
          backgroundColor: const Color(0xFF161616).withOpacity(0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.08), width: 0.5),
          ),
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
      ),
    );

    if (confirm == true) {
      if (Platform.isAndroid) {
        try {
          const channel = MethodChannel('com.benjamindarko.monochrome/system');
          await channel.invokeMethod('clearAppData');
        } catch (e) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();
          await AudioCacheService().clearCache();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cache cleared. Please restart the app.')),
            );
          }
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        await AudioCacheService().clearCache();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cache cleared. Please restart the app to apply default settings.')),
          );
        }
      }
    }
  }

  Widget _buildAboutContent() {
    return Column(
      key: const ValueKey('about_content'),
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            color: Colors.white.withOpacity(0.05),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Container(
                width: 116,
                height: 86,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const SweepGradient(
                    colors: [ZypAuroraColors.cyan, ZypAuroraColors.violet, ZypAuroraColors.pink, ZypAuroraColors.peach, ZypAuroraColors.cyan],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ZypAuroraColors.violet.withOpacity(0.28),
                      blurRadius: 40,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Z',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'ZYP Music',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Version 1.3.1',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.62),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'About the project',
                style: TextStyle(
                  color: ZypAuroraColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'ZYP Music is a premium open-source native audio streaming application designed for Android. It features high-fidelity YouTube audio streaming, robust offline caching, gapless crossfade transitions, synchronized lyrics, and smart Auto-DJ recommendations.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 13,
                  height: 1.58,
                ),
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Creator',
          child: Column(
            children: [
              SettingRow(
                title: 'Benjamin Akuffo Darko',
                subtitle: 'Lead Developer & Creator',
                right: const Icon(PhosphorIconsRegular.user, color: Colors.white54),
              ),
              SettingRow(
                title: 'Antwi Isaac Benoah',
                subtitle: 'Co-Creator',
                right: const Icon(PhosphorIconsRegular.arrowUpRight, color: Colors.white54, size: 20),
                onTap: () async {
                  final uri = Uri.parse('https://github.com/iykex');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              SettingRow(
                title: 'NiiAbe',
                subtitle: 'Co-Creator',
                right: const Icon(PhosphorIconsRegular.arrowUpRight, color: Colors.white54, size: 20),
                onTap: () async {
                  final uri = Uri.parse('https://github.com/niiabe');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ),
        SettingGroup(
          title: 'Links',
          child: SettingRow(
            title: 'GitHub Repository',
            subtitle: 'github.com/BENJAMINDARKO/zyp_music',
            right: const Icon(PhosphorIconsRegular.arrowUpRight, color: Colors.white54, size: 20),
            onTap: () async {
              final uri = Uri.parse('https://github.com/BENJAMINDARKO/zyp_music');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Option Picker Sheets
  // ---------------------------------------------------------------------------

  void _showSeekbarStylePicker(SettingsProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSelectionSheet(
        title: 'Seekbar Style',
        options: ['Prism', 'Gradient', 'Minimal', 'Wavy', 'Segmented'],
        currentValue: provider.seekbarStyle,
        onSelected: (val) {
          provider.setSeekbarStyle(val);
        },
      ),
    );
  }

  void _showBitratePicker(SettingsProvider provider) {
    final Map<String, String> items = {
      'adaptive': 'Adaptive (Auto-switching)',
      'yt48': 'Low (~48-50 kbps)',
      'yt128': 'Medium (~128 kbps)',
      'yt256': 'High (~160-256 kbps)',
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSelectionSheet(
        title: 'Streaming Bitrate',
        options: items.keys.toList(),
        currentValue: provider.youtubeMusicQuality,
        displayMapper: (key) => items[key]!,
        onSelected: (val) {
          provider.setStringSetting('youtubeMusicQuality', val);
        },
      ),
    );
  }

  void _showAudioFormatPicker(SettingsProvider provider) {
    final Map<String, String> items = {
      'Any': 'Any (Best Compatible)',
      'm4a': 'M4A (AAC)',
      'webm': 'WebM (Opus)',
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSelectionSheet(
        title: 'Streaming Format',
        options: items.keys.toList(),
        currentValue: provider.youtubeMusicFormat,
        displayMapper: (key) => items[key]!,
        onSelected: (val) {
          provider.setStringSetting('youtubeMusicFormat', val);
        },
      ),
    );
  }

  void _showExplicitPicker(SettingsProvider provider) {
    final Map<String, String> items = {
      'both': 'Both',
      'clean': 'Clean Only',
      'explicit': 'Explicit Only',
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSelectionSheet(
        title: 'Explicit Content Filter',
        options: items.keys.toList(),
        currentValue: provider.explicitFilter,
        displayMapper: (key) => items[key]!,
        onSelected: (val) {
          provider.setStringSetting('explicitFilter', val);
        },
      ),
    );
  }

  void _showDownloadQualityPicker(SettingsProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSelectionSheet(
        title: 'Download Quality',
        options: const ['AAC 320kbps', 'FLAC Lossless', 'M4A 128kbps'],
        currentValue: provider.downloadQuality,
        onSelected: (val) {
          provider.setStringSetting('downloadQuality', val);
        },
      ),
    );
  }

  void _showBulkDownloadPicker(SettingsProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSelectionSheet(
        title: 'Bulk Download Method',
        options: const ['ZIP Archive', 'Individual Files'],
        currentValue: provider.bulkDownloadMethod,
        onSelected: (val) {
          provider.setStringSetting('bulkDownloadMethod', val);
        },
      ),
    );
  }

  void _showRegionPicker(SettingsProvider provider) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SettingsCountryPicker(provider: provider),
    );
    if (code != null) {
      await provider.setPreferredGl(code);
    }
  }

  Widget _buildSelectionSheet({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
    String Function(String)? displayMapper,
  }) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final displayStr = displayMapper != null ? displayMapper(opt) : opt;
                final isSelected = opt == currentValue;
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    title: Text(
                      displayStr,
                      style: TextStyle(
                        color: isSelected ? ZypAuroraColors.cyan : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(PhosphorIconsFill.checkCircle, color: ZypAuroraColors.cyan, size: 22)
                        : null,
                    onTap: () {
                      onSelected(opt);
                      Navigator.pop(context);
                    },
                  ),
                );
              }),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Custom Sub-components for Settings
// -----------------------------------------------------------------------------

class SettingGroup extends StatelessWidget {
  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onActionTap;

  const SettingGroup({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 22, 2, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: ZypAuroraColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              if (action != null)
                GestureDetector(
                  onTap: onActionTap,
                  child: Text(
                    action!,
                    style: const TextStyle(
                      color: ZypAuroraColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.09),
                Colors.white.withOpacity(0.035),
              ],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}

class SettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? right;
  final Color glowColor;
  final bool danger;
  final VoidCallback? onTap;

  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.right,
    this.glowColor = ZypAuroraColors.cyan,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.07),
                width: 1.0,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -48,
                bottom: -54,
                child: IgnorePointer(
                  child: Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (danger ? Colors.redAccent : glowColor).withOpacity(0.08),
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.35,
                            color: danger ? Colors.redAccent : Colors.white,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: danger
                                  ? Colors.redAccent.withOpacity(0.7)
                                  : Colors.white.withOpacity(0.62),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (right != null) ...[
                    const SizedBox(width: 14),
                    right!,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 58,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: value
              ? const LinearGradient(
                  colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                )
              : null,
          color: value ? null : Colors.white.withOpacity(0.16),
          border: value ? null : Border.all(color: Colors.white.withOpacity(0.35), width: 1),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: ZypAuroraColors.cyan.withOpacity(0.18),
                    blurRadius: 28,
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.all(4),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? const Color(0xFF081018) : Colors.white,
          ),
        ),
      ),
    );
  }
}

class SettingSelectPill extends StatelessWidget {
  final String value;
  final VoidCallback onTap;

  const SettingSelectPill({
    super.key,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 100, maxWidth: 200),
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          color: Colors.white.withOpacity(0.075),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              PhosphorIconsRegular.caretDown,
              color: Colors.white.withOpacity(0.86),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const SettingIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          color: Colors.white.withOpacity(0.065),
        ),
        child: Icon(
          icon,
          color: color ?? Colors.white.withOpacity(0.72),
          size: 20,
        ),
      ),
    );
  }
}

class SettingSlider extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  const SettingSlider({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.35,
                  color: Colors.white,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.62),
            ),
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: ZypAuroraColors.cyan,
              inactiveTrackColor: Colors.white.withOpacity(0.12),
              thumbColor: Colors.white,
              trackHeight: 10,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCountryPicker extends StatelessWidget {
  final SettingsProvider provider;
  const _SettingsCountryPicker({required this.provider});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Region',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Personalised music recommendations for your region',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...SettingsProvider.countryOptions.map((c) => Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(PhosphorIconsRegular.globeHemisphereWest,
                        color: Colors.white70),
                    title: Text(c['name']!, style: const TextStyle(color: Colors.white)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (provider.preferredGl == c['code'])
                          const Icon(PhosphorIconsFill.checkCircle,
                              color: ZypAuroraColors.cyan, size: 22),
                        const SizedBox(width: 8),
                        Text(c['code']!,
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, c['code']),
                  ),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InlineEqualizerSettingCard extends StatefulWidget {
  const InlineEqualizerSettingCard({super.key});

  @override
  State<InlineEqualizerSettingCard> createState() => _InlineEqualizerSettingCardState();
}

class _InlineEqualizerSettingCardState extends State<InlineEqualizerSettingCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  final List<String> _freqLabels = [
    '31', '45', '63', '90', '125', '180', '250', '355',
    '500', '710', '1k', '1.4k', '2k', '4k', '8k', '16k'
  ];

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EqualizerProvider>(
      builder: (context, provider, child) {
        final settings = provider.settings;
        final activePreset = provider.presets.firstWhere(
          (p) => p.id == settings.selectedPresetId,
          orElse: () => provider.presets.first,
        );

        final String activePresetName = settings.selectedPresetId == 'custom'
            ? 'Custom'
            : activePreset.name;
        final String activePresetDesc = settings.selectedPresetId == 'custom'
            ? 'Fine tuned manually'
            : activePreset.description;

        final allPresets = [
          ...provider.presets,
          const EqualizerPreset(
            id: 'custom',
            name: 'Custom',
            description: 'Your saved curve',
            bandGains: [2, 2, 3, 2, 1, 0, 0, 1, 2, 3, 3, 2, 1, 0, 1, 2],
            preamp: 0,
            bassBoost: 22,
            virtualizer: 20,
          )
        ];

        return Column(
          children: [
            SettingRow(
              title: 'Equalizer',
              subtitle: '16-band sound tuning. Expands in-place so it stays part of Settings.',
              onTap: _toggleExpand,
              right: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: settings.enabled
                          ? ZypAuroraColors.cyan.withOpacity(0.10)
                          : Colors.white.withOpacity(0.08),
                      border: Border.all(
                        color: settings.enabled
                            ? ZypAuroraColors.cyan.withOpacity(0.14)
                            : Colors.white.withOpacity(0.12),
                      ),
                    ),
                    child: Text(
                      settings.enabled ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: settings.enabled ? ZypAuroraColors.cyan : Colors.white60,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {}, // Prevent tap bubble from firing parent row onTap
                    child: SettingSwitch(
                      value: settings.enabled,
                      onChanged: (v) {
                        provider.setEnabled(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  RotationTransition(
                    turns: Tween<double>(begin: 0.0, end: 0.5).animate(_expandAnimation),
                    child: Icon(
                      PhosphorIconsRegular.caretDown,
                      color: Colors.white.withOpacity(0.72),
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: ClipRect(
                child: Column(
                  children: [
                    // 1. Short note
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        color: ZypAuroraColors.cyan.withOpacity(0.065),
                        border: Border.all(color: ZypAuroraColors.cyan.withOpacity(0.10)),
                      ),
                      child: Text(
                        'Everything lives in this one Settings card: presets, 16 bands, pre-amp, bass boost, virtualizer, limiter, and per-device EQ.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.70),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                    // 2. Compact curve preview
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.09),
                            Colors.white.withOpacity(0.035),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activePresetName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  activePresetDesc,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.62),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 96,
                            height: 44,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(16, (i) {
                                final gain = settings.bandGains[i];
                                final percent = 0.15 + (0.85 * (gain + 12) / 24.0);
                                return Container(
                                  width: 3.5,
                                  height: 44 * percent,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    gradient: const LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [ZypAuroraColors.pink, ZypAuroraColors.cyan],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ZypAuroraColors.cyan.withOpacity(0.18),
                                        blurRadius: 4,
                                      )
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 3. Preset chips rail
                    SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: allPresets.length,
                        itemBuilder: (context, index) {
                          final p = allPresets[index];
                          final isSelected = settings.selectedPresetId == p.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: GestureDetector(
                              onTap: () {
                                provider.selectPreset(p.id);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.10),
                                  ),
                                  gradient: isSelected
                                      ? const LinearGradient(
                                          colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                                        )
                                      : null,
                                  color: isSelected ? null : Colors.white.withOpacity(0.055),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  p.name,
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFF080711) : Colors.white.withOpacity(0.68),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // 4. Fine tune curve (16-band Editor)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        color: Colors.white.withOpacity(0.045),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Fine tune curve',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Row(
                                children: [
                                  _buildMiniBtn('Flat', () {
                                    provider.selectPreset('flat');
                                  }, isPrimary: false),
                                  const SizedBox(width: 8),
                                  _buildMiniBtn('Save', () {
                                    provider.saveCustomCurve();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Custom equalizer curve saved!'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }, isPrimary: true),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 144,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: 16,
                              itemBuilder: (context, index) {
                                final freq = _freqLabels[index];
                                final gainVal = settings.bandGains[index];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6.0),
                                  child: Container(
                                    width: 38,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: Colors.white.withOpacity(0.04),
                                      border: Border.all(color: Colors.white.withOpacity(0.065)),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${gainVal > 0 ? '+' : ''}${gainVal.round()}dB',
                                          style: TextStyle(
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white.withOpacity(0.70),
                                          ),
                                        ),
                                        Expanded(
                                          child: SliderTheme(
                                            data: SliderTheme.of(context).copyWith(
                                              activeTrackColor: ZypAuroraColors.cyan,
                                              inactiveTrackColor: Colors.white.withOpacity(0.10),
                                              thumbColor: Colors.white,
                                              trackHeight: 3,
                                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                            ),
                                            child: RotatedBox(
                                              quarterTurns: -1,
                                              child: Slider(
                                                value: gainVal,
                                                min: -12,
                                                max: 12,
                                                divisions: 24,
                                                onChanged: (newVal) {
                                                  provider.setBandGain(index, newVal);
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          freq,
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white.withOpacity(0.48),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 5, 6, 7. Utility sliders
                    _buildUtilitySlider(
                      title: 'Pre-amp',
                      value: settings.preamp,
                      min: -12,
                      max: 12,
                      divisions: 24,
                      displayValue: '${settings.preamp > 0 ? '+' : ''}${settings.preamp.round()}dB',
                      onChanged: (v) => provider.setPreamp(v),
                    ),
                    _buildUtilitySlider(
                      title: 'Bass boost',
                      value: settings.bassBoost,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      displayValue: '${settings.bassBoost.round()}%',
                      onChanged: (v) => provider.setBassBoost(v),
                    ),
                    _buildUtilitySlider(
                      title: 'Virtualizer',
                      value: settings.virtualizer,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      displayValue: '${settings.virtualizer.round()}%',
                      onChanged: (v) => provider.setVirtualizer(v),
                    ),
                    // 8, 9. Limiter, Per-device EQ
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildToggleCard(
                              title: 'Limiter',
                              subtitle: 'Prevent clipping from boosted bands.',
                              value: settings.limiterEnabled,
                              onChanged: (v) => provider.setLimiterEnabled(v),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: _buildToggleCard(
                              title: 'Per-device EQ',
                              subtitle: 'Remember curves per output.',
                              value: settings.perDeviceEnabled,
                              onChanged: (v) => provider.setPerDeviceEnabled(v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniBtn(String label, VoidCallback onTap, {required bool isPrimary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: isPrimary ? null : Border.all(color: Colors.white.withOpacity(0.10)),
          color: isPrimary ? null : Colors.white.withOpacity(0.06),
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary ? const Color(0xFF080711) : Colors.white.withOpacity(0.74),
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildUtilitySlider({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withOpacity(0.045),
        border: Border.all(color: Colors.white.withOpacity(0.075)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: ZypAuroraColors.cyan,
                inactiveTrackColor: Colors.white.withOpacity(0.10),
                thumbColor: Colors.white,
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              displayValue,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white.withOpacity(0.62),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withOpacity(0.045),
        border: Border.all(color: Colors.white.withOpacity(0.075)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withOpacity(0.62),
                  height: 1.25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SettingSwitch(
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
