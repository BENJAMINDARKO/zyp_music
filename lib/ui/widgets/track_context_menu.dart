import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../../core/theme/app_theme.dart';
import '../../core/utils/thumbnail_url.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../core/services/hybrid_cache_service.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import 'auto_dj_mode_picker.dart';
import 'add_to_playlist_modal.dart';
import 'aurora_glass.dart';

class TrackContextMenu {
  static void show(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        final playlistProvider = sheetContext.watch<PlaylistProvider>();
        final playerProvider = sheetContext.watch<PlayerProvider>();
        final downloadProvider = sheetContext.watch<DownloadProvider>();
        final hybridCache = sheetContext.watch<HybridCacheService>();

        final isDownloaded = downloadProvider.downloadedTrackIds.contains(track.id);
        final isExported = downloadProvider.exportedTrackIds.contains(track.id);
        final isExporting = downloadProvider.activeExports.containsKey(track.id);
        final isCached = hybridCache.isCached(track.id) ||
            hybridCache.isDownloadedInSqlite(track.id) ||
            isDownloaded;

        final screenHeight = MediaQuery.of(sheetContext).size.height;
        final bool isSmallScreen = screenHeight < 760;

        final screenWidth = MediaQuery.of(sheetContext).size.width;
        final double sheetWidth = (screenWidth > 430 ? 430.0 : screenWidth) * 0.85;

        return Padding(
          padding: EdgeInsets.only(
            bottom: 12 + MediaQuery.of(sheetContext).padding.bottom,
            top: 56 + MediaQuery.of(sheetContext).padding.top,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: sheetWidth,
              child: AuroraGlass(
                borderRadius: 36,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  // Handle
                  Container(
                    width: 58,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),

                  // Header: artwork | title/artist/album | close
                  Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.28),
                              blurRadius: 40,
                              offset: const Offset(0, 18),
                            ),
                            BoxShadow(
                              color: ZypAuroraColors.cyan.withOpacity(0.12),
                              blurRadius: 42,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: (track.thumbnailUrl?.isNotEmpty ?? false)
                              ? Image.network(
                                  rewriteThumbnailSize(track.thumbnailUrl),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _fallbackCover(72),
                                )
                              : _fallbackCover(72),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -1.0,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.author ?? 'Unknown Artist',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.62),
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (track.album?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: ZypAuroraColors.cyan.withOpacity(0.10),
                                  border: Border.all(color: ZypAuroraColors.cyan.withOpacity(0.16)),
                                ),
                                child: Text(
                                  track.album!.toUpperCase(),
                                  style: const TextStyle(
                                    color: ZypAuroraColors.cyan,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => Navigator.pop(sheetContext),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.11)),
                            color: Colors.white.withOpacity(0.06),
                          ),
                          child: const Center(
                            child: Icon(
                              PhosphorIconsRegular.caretDown,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Quick Actions Grid (Add to Queue & Favorite)
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            playerProvider.appendToQueue([track]);
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to queue')),
                            );
                          },
                          child: Container(
                            height: isSmallScreen ? 76 : 92,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: const LinearGradient(
                                colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ZypAuroraColors.cyan.withOpacity(0.18),
                                  blurRadius: 34,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(PhosphorIconsRegular.listPlus, color: Color(0xFF080711), size: 24),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Add to Queue',
                                    style: TextStyle(
                                      color: const Color(0xFF080711),
                                      fontSize: isSmallScreen ? 12 : 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            playlistProvider.toggleFavorite(
                              track,
                              downloadProvider: downloadProvider,
                            );
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(playlistProvider.isFavorite(track.id) ? 'Removed from Favorites' : 'Added to Favorites')),
                            );
                          },
                          child: Container(
                            height: isSmallScreen ? 76 : 92,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.10)),
                              color: Colors.white.withOpacity(0.065),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: -36,
                                  bottom: -40,
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: ZypAuroraColors.pink.withOpacity(0.18),
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        playlistProvider.isFavorite(track.id)
                                            ? PhosphorIconsFill.heart
                                            : PhosphorIconsRegular.heart,
                                        color: playlistProvider.isFavorite(track.id)
                                            ? ZypAuroraColors.pink
                                            : Colors.white,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Favourite',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isSmallScreen ? 12 : 13,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Option Groups
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      children: [
                        // Group 1: Playlist & Station
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.10)),
                            color: Colors.white.withOpacity(0.05),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              _buildOptionRow(
                                title: 'Add to Playlist',
                                subtitle: 'Save this track to one of your prism vaults',
                                icon: PhosphorIconsRegular.playlist,
                                glowColor: ZypAuroraColors.cyan,
                                showBorder: true,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  AddToPlaylistModal.show(context, track);
                                },
                              ),
                              _buildOptionRow(
                                title: 'Create Station',
                                subtitle: 'Start Auto DJ recommended station from this song',
                                icon: PhosphorIconsRegular.broadcast,
                                glowColor: ZypAuroraColors.violet,
                                showBorder: false,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  AutoDJModePicker.show(context, seedTrack: track);
                                },
                              ),
                            ],
                          ),
                        ),

                        // Group 2: Navigation
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.10)),
                            color: Colors.white.withOpacity(0.05),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              _buildOptionRow(
                                title: 'Go to Album',
                                subtitle: (track.album != null && track.album!.isNotEmpty)
                                    ? track.album!
                                    : 'Search Album',
                                icon: PhosphorIconsRegular.disc,
                                glowColor: ZypAuroraColors.peach,
                                showBorder: track.author != null && track.author!.isNotEmpty,
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  final albumTitle = (track.album != null && track.album!.isNotEmpty)
                                      ? track.album!
                                      : track.title;
                                  final artistName = (track.author ?? '').trim();
                                  final query = artistName.isNotEmpty
                                      ? '$albumTitle $artistName'
                                      : albumTitle;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Searching for album...'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );

                                  final res = await playlistProvider.searchAlbums(query);
                                  if (res.isNotEmpty && context.mounted) {
                                    final normalizedArtist = artistName.toLowerCase();
                                    final match = normalizedArtist.isNotEmpty
                                        ? res.cast<dynamic>().firstWhere(
                                              (a) {
                                                final albumArtist = (a.author ?? a.artist ?? '').toString().toLowerCase();
                                                return albumArtist.contains(normalizedArtist) ||
                                                    normalizedArtist.contains(albumArtist);
                                              },
                                              orElse: () => res.first,
                                            )
                                        : res.first;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AlbumScreen(albumId: match.id),
                                      ),
                                    );
                                  } else if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Album details not found')),
                                    );
                                  }
                                },
                              ),
                              if (track.author != null && track.author!.isNotEmpty)
                                _buildOptionRow(
                                  title: 'Go to Artist',
                                  subtitle: track.author!,
                                  icon: PhosphorIconsRegular.microphone,
                                  glowColor: ZypAuroraColors.cyan,
                                  showBorder: false,
                                  onTap: () async {
                                    Navigator.pop(sheetContext);
                                    final artist = await playlistProvider.findCorrectArtist(
                                      track.author!,
                                      track.album,
                                    );
                                    if (artist != null && context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ArtistScreen(artistId: artist.id),
                                        ),
                                      );
                                    } else if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Artist details not found')),
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),

                        // Group 3: Storage
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.10)),
                            color: Colors.white.withOpacity(0.05),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              _buildOptionRow(
                                title: 'Download',
                                subtitle: isDownloaded
                                    ? 'Available offline on this device'
                                    : 'Download to offline vault',
                                icon: isDownloaded
                                    ? PhosphorIconsFill.checkCircle
                                    : PhosphorIconsRegular.downloadSimple,
                                iconColor: isDownloaded ? ZypAuroraColors.cyan : null,
                                glowColor: ZypAuroraColors.cyan,
                                showBorder: true,
                                onTap: () {
                                  if (!isDownloaded) {
                                    downloadProvider.downloadTrack(track, 'downloads');
                                    Navigator.pop(sheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Download started')),
                                    );
                                  } else {
                                    Navigator.pop(sheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Already downloaded')),
                                    );
                                  }
                                },
                              ),
                              _buildOptionRow(
                                title: 'Export to Folder',
                                subtitle: isExported
                                    ? 'Saved offline to external storage'
                                    : isExporting
                                        ? 'Exporting in progress...'
                                        : 'Save as .m4a with album art to external folder',
                                icon: isExported
                                    ? PhosphorIconsFill.checkCircle
                                    : PhosphorIconsRegular.download,
                                iconColor: isExported ? ZypAuroraColors.cyan : null,
                                glowColor: ZypAuroraColors.violet,
                                showBorder: false,
                                onTap: () {
                                  if (isExported) {
                                    downloadProvider.unexportTrack(track);
                                    Navigator.pop(sheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Removed from exports')),
                                    );
                                  } else if (!isExporting) {
                                    downloadProvider.exportTrack(track);
                                    Navigator.pop(sheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Exporting to folder...')),
                                    );
                                  } else {
                                    Navigator.pop(sheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Currently exporting')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        // Group 4: Danger zone (Remove from cache & Suggest less)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.10)),
                            color: Colors.white.withOpacity(0.05),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              if (isCached)
                                _buildOptionRow(
                                  title: 'Remove from Cache',
                                  subtitle: 'Frees local storage; track will re-download next time',
                                  icon: PhosphorIconsRegular.trash,
                                  isDanger: true,
                                  showBorder: true,
                                  onTap: () async {
                                    Navigator.pop(sheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Removing "${track.title}" from cache…')),
                                    );
                                    await downloadProvider.removeTrackFromCache(track);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Removed "${track.title}" from cache')),
                                      );
                                    }
                                  },
                                ),
                              _buildOptionRow(
                                title: 'Suggest Less',
                                subtitle: 'Reduce similar recommendations in Mood Orbit',
                                icon: PhosphorIconsRegular.thumbsDown,
                                isDanger: true,
                                showBorder: false,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('We will recommend less of "${track.title}"')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  static Widget _fallbackCover(double size) {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: Center(
        child: Icon(PhosphorIconsRegular.musicNote, color: Colors.white30, size: size * 0.4),
      ),
    );
  }

  static Widget _buildOptionRow({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    Color? glowColor,
    required VoidCallback onTap,
    bool isDanger = false,
    bool showBorder = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: showBorder
                ? Border(
                    bottom: BorderSide(
                      color: Colors.white.withOpacity(0.07),
                      width: 1,
                    ),
                  )
                : null,
          ),
          child: Stack(
            children: [
              if (glowColor != null)
                Positioned(
                  right: -48,
                  bottom: -54,
                  child: Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: glowColor.withOpacity(0.10),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
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
                              color: isDanger ? const Color(0xFFFF5B6E) : Colors.white,
                              letterSpacing: -0.35,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDanger
                                  ? const Color(0xFFFF5B6E).withOpacity(0.7)
                                  : Colors.white.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isDanger
                              ? const Color(0xFFFF5B6E).withOpacity(0.2)
                              : Colors.white.withOpacity(0.09),
                        ),
                        color: isDanger
                            ? const Color(0xFFFF5B6E).withOpacity(0.1)
                            : Colors.white.withOpacity(0.065),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          color: isDanger ? const Color(0xFFFF5B6E) : (iconColor ?? Colors.white.withOpacity(0.68)),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
