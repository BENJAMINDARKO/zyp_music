import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/constants/audio_quality.dart';
import '../providers/settings_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/download_provider.dart';
import '../../service/auth_service.dart';
import 'about_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  bool _hasCookies = false;

  @override
  void initState() {
    super.initState();
    _checkCookies();
  }

  Future<void> _checkCookies() async {
    final has = await _authService.hasCookies();
    setState(() => _hasCookies = has);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _buildPageHeader(context),
                const SizedBox(height: 28),
                _SettingsPanel(
                  title: 'Playback',
                  icon: Icons.tune_rounded,
                  children: [
                    _buildPrebufferSlider(settings),
                    const SizedBox(height: 22),
                    _buildQualitySelector(settings),
                  ],
                ),
                const SizedBox(height: 18),
                _SettingsPanel(
                  title: 'YouTube Login',
                  icon: Icons.account_circle_rounded,
                  children: [
                    _buildLoginStatus(),
                    const SizedBox(height: 16),
                    _buildLoginButton(),
                    if (_hasCookies) ...[
                      const SizedBox(height: 12),
                      _buildLogoutButton(),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Login cookies are saved to your device.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SettingsPanel(
                  title: 'Import / Export',
                  icon: Icons.import_export_rounded,
                  children: [_buildImportExportSection()],
                ),
                const SizedBox(height: 18),
                _SettingsPanel(
                  title: 'Storage',
                  icon: Icons.storage_rounded,
                  children: [_buildStorageSection()],
                ),
                const SizedBox(height: 18),
                _buildInfoButton(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPageHeader(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF191919),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        const SizedBox(width: 16),
        const Text(
          'Settings',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  ButtonStyle _softButtonStyle({Color? foregroundColor}) {
    return OutlinedButton.styleFrom(
      foregroundColor: foregroundColor ?? Colors.white,
      side: BorderSide(color: Colors.white.withAlpha(18)),
      backgroundColor: Colors.white.withAlpha(10),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _buildPrebufferSlider(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Pre-download ahead tracks',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
            Text(
              '${settings.prebufferCount}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: settings.prebufferCount.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          onChanged: (v) => settings.setPrebufferCount(v.round()),
        ),
        Text(
          'Number of upcoming tracks to pre-download (0 = disabled)',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildQualitySelector(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Audio quality',
          style: TextStyle(fontSize: 14, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AudioQuality.values.map((quality) {
            final isSelected = settings.audioQuality == quality;
            return ChoiceChip(
              selected: isSelected,
              label: Text(_qualityLabel(quality)),
              selectedColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.white.withAlpha(12),
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white.withAlpha(18),
                ),
              ),
              onSelected: (_) => settings.setAudioQuality(quality),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Text(
          _qualityDescription(settings.audioQuality),
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  String _qualityLabel(AudioQuality q) {
    switch (q) {
      case AudioQuality.low:
        return 'Low (~64 kbps)';
      case AudioQuality.medium:
        return 'Medium (~128 kbps)';
      case AudioQuality.high:
        return 'High (best available)';
    }
  }

  String _qualityDescription(AudioQuality q) {
    switch (q) {
      case AudioQuality.low:
        return 'Uses less data, fastest loading';
      case AudioQuality.medium:
        return 'Balanced quality and data usage';
      case AudioQuality.high:
        return 'Best audio quality, more data usage';
    }
  }

  Widget _buildLoginStatus() {
    return Row(
      children: [
        Icon(
          _hasCookies ? Icons.check_circle : Icons.cancel,
          color: _hasCookies ? Colors.greenAccent : Colors.grey,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          _hasCookies ? 'Logged in' : 'Not logged in',
          style: TextStyle(
            color: _hasCookies ? Colors.greenAccent : Colors.grey,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
          if (result == true) {
            await _checkCookies();
          }
        },
        icon: const Icon(Icons.login),
        label: const Text('Login with Google'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Future<void> _importPlaylists() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'md', 'xml', 'txt'],
      );
      if (result == null || result.files.single.path == null) return;
      if (!mounted) return;
      final provider = context.read<PlaylistProvider>();
      final count = await provider.importPlaylists(result.files.single.path!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported $count playlist(s)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportPlaylists(String format) async {
    try {
      final provider = context.read<PlaylistProvider>();
      final path = await provider.exportPlaylists(format);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to: $path'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildImportExportSection() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _importPlaylists,
            icon: const Icon(Icons.file_download),
            label: const Text('Import playlists from file'),
            style: _softButtonStyle(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showExportDialog(),
            icon: const Icon(Icons.file_upload),
            label: const Text('Export playlists'),
            style: _softButtonStyle(),
          ),
        ),
      ],
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export playlists'),
        content: const Text('Choose a format:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportPlaylists('json');
            },
            child: const Text('JSON'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportPlaylists('md');
            },
            child: const Text('Markdown'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportPlaylists('xml');
            },
            child: const Text('XML'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSection() {
    return FutureBuilder<int>(
      future: context.read<DownloadProvider>().getTotalCacheSize(),
      builder: (context, snapshot) {
        final sizeBytes = snapshot.data ?? 0;
        final sizeText = sizeBytes > 0
            ? _formatBytes(sizeBytes)
            : 'No cached data';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, size: 18, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  'Cached downloads: $sizeText',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: sizeBytes > 0
                    ? () => _clearAllDownloads(context)
                    : null,
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Clear all cached downloads'),
                style: _softButtonStyle(
                  foregroundColor: sizeBytes > 0
                      ? Colors.redAccent
                      : Colors.grey[700],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearAllDownloads(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all downloads?'),
        content: const Text(
          'Remove all downloaded audio files from your device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final provider = context.read<DownloadProvider>();
      final allPlaylistIds = context
          .read<PlaylistProvider>()
          .playlists
          .map((p) => p.id)
          .toList();
      for (final id in allPlaylistIds) {
        await provider.deleteDownloadedPlaylist(id);
      }
      setState(() {});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All cached downloads cleared')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildInfoButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AboutScreen()),
          );
        },
        icon: const Icon(Icons.info_outline, size: 18),
        label: const Text('About'),
        style: TextButton.styleFrom(foregroundColor: Colors.grey[400]),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () async {
          await _authService.clearCookies();
          await _checkCookies();
        },
        style: _softButtonStyle(foregroundColor: Colors.redAccent),
        child: const Text('Logout'),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsPanel({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}
