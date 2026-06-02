import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/constants/app_constants.dart';
import '../widgets/pixel_logo.dart';
import 'licenses_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final version = snapshot.data?.version ?? '1.0.0';
            final build = snapshot.data?.buildNumber ?? '1';
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _PageHeader(
                  title: 'About',
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171717),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withAlpha(14)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            const LogoWithHeadset(size: 104),
                            const SizedBox(height: 18),
                            const Text(
                              AppConstants.appName,
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Version $version ($build)',
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      const _InfoRow(
                        icon: Icons.music_note_rounded,
                        title: 'YouTube Music Streamer',
                        body:
                            'Stream audio from public YouTube playlists, single videos, and mixes.',
                      ),
                      const SizedBox(height: 14),
                      const _InfoRow(
                        icon: Icons.cloud_off_rounded,
                        title: 'Offline-first playback',
                        body:
                            'Downloaded tracks play from local cache before using the network.',
                      ),
                      const SizedBox(height: 14),
                      const _InfoRow(
                        icon: Icons.shield_outlined,
                        title: 'Personal use',
                        body:
                            'For personal, educational use only. Not affiliated with YouTube.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _ActionTile(
                  icon: Icons.article_rounded,
                  title: 'Open source licenses',
                  subtitle: 'Flutter, plugins, and package notices',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LicensesScreen()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _PageHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
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
            onPressed: onBack,
          ),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoRow({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(14)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
