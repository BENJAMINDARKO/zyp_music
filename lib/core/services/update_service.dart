import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import '../utils/app_logger.dart';

class UpdateService {
  static const String _repoUrl =
      'https://api.github.com/repos/BENJAMINDARKO/zyp_music/releases/latest';

  /// Check for updates and show dialog if a newer version is available.
  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      AppLogger.log(
        'Checking for updates. Current version: $currentVersion',
        name: 'UpdateService',
      );

      final response = await http.get(
        Uri.parse(_repoUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final String latestVersion = data['tag_name'] ?? '';
        final List<dynamic> assets = data['assets'] ?? [];

        if (latestVersion.isEmpty) return;

        AppLogger.log(
          'Latest version on GitHub: $latestVersion',
          name: 'UpdateService',
        );

        if (_isNewerVersion(currentVersion, latestVersion)) {
          // Find the first APK asset
          String? apkUrl;
          for (final asset in assets) {
            final String name = asset['name'] ?? '';
            if (name.endsWith('.apk')) {
              apkUrl = asset['browser_download_url'];
              break;
            }
          }

          if (apkUrl != null && context.mounted) {
            _showUpdateDialog(context, latestVersion, apkUrl);
          } else {
            AppLogger.log(
              'New version found but no APK asset is attached to the release.',
              name: 'UpdateService',
            );
          }
        } else {
          AppLogger.log('App is up to date.', name: 'UpdateService');
        }
      } else {
        AppLogger.log(
          'GitHub API returned status code: ${response.statusCode}',
          name: 'UpdateService',
        );
      }
    } catch (e) {
      AppLogger.log('Update check failed: $e', name: 'UpdateService');
    }
  }

  /// Compare two version strings component-by-component.
  /// E.g., '1.2.8' vs '1.2.9' -> returns true.
  static bool _isNewerVersion(String currentStr, String latestStr) {
    try {
      final cleanCurrent = currentStr.replaceAll(RegExp(r'^[vV]'), '').split('+')[0];
      final cleanLatest = latestStr.replaceAll(RegExp(r'^[vV]'), '').split('+')[0];

      final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final length = max(currentParts.length, latestParts.length);
      for (var i = 0; i < length; i++) {
        final currentPart = i < currentParts.length ? currentParts[i] : 0;
        final latestPart = i < latestParts.length ? latestParts[i] : 0;
        if (latestPart > currentPart) return true;
        if (currentPart > latestPart) return false;
      }
    } catch (e) {
      AppLogger.log('Error parsing version strings: $e', name: 'UpdateService');
    }
    return false;
  }

  /// Prompt the user to update.
  static void _showUpdateDialog(
    BuildContext context,
    String latestVersion,
    String downloadUrl,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false, // Force choice
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Update Available ($latestVersion)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'A new version of Zyp Music is available. Would you like to download and install it now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Later',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close prompt
                _showDownloadProgressDialog(context, downloadUrl);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Update Now'),
            ),
          ],
        );
      },
    );
  }

  /// Show progress dialog while downloading.
  static void _showDownloadProgressDialog(BuildContext context, String downloadUrl) {
    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
    final ValueNotifier<String> statusNotifier = ValueNotifier<String>('Initializing...');
    final navigator = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext progressContext) {
        return PopScope(
          canPop: false, // Disable back button during update
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Downloading Update',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: ValueListenableBuilder2<double, String>(
              first: progressNotifier,
              second: statusNotifier,
              builder: (context, progress, status, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress >= 0 ? progress / 100.0 : null,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (progress >= 0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${progress.toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    // Start download process using ota_update
    try {
      OtaUpdate()
          .execute(
        downloadUrl,
        destinationFilename: 'zyp_music_update.apk',
      )
          .listen(
        (OtaEvent event) {
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final double value = double.tryParse(event.value ?? '') ?? 0.0;
              progressNotifier.value = value;
              statusNotifier.value = 'Downloading files...';
              break;
            case OtaStatus.INSTALLING:
              statusNotifier.value = 'Launching package installer...';
              progressNotifier.value = -1.0; // Indeterminate
              // Close progress dialog since OS installer takes over the screen
              Future.delayed(const Duration(seconds: 1), () {
                try {
                  navigator.pop();
                } catch (_) {}
              });
              break;
            case OtaStatus.INSTALLATION_DONE:
              statusNotifier.value = 'Installation complete.';
              _closeProgressWithDelay(navigator);
              break;
            case OtaStatus.INSTALLATION_ERROR:
              statusNotifier.value = 'Installation failed.';
              _closeProgressWithDelay(navigator);
              break;
            case OtaStatus.CANCELED:
              statusNotifier.value = 'Update canceled.';
              _closeProgressWithDelay(navigator);
              break;
            case OtaStatus.ALREADY_RUNNING_ERROR:
              statusNotifier.value = 'An update is already running.';
              _closeProgressWithDelay(navigator);
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              statusNotifier.value = 'Permission to install packages not granted.';
              _closeProgressWithDelay(navigator);
              break;
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
              statusNotifier.value = 'Error downloading update: ${event.status.name}';
              _closeProgressWithDelay(navigator);
              break;
          }
        },
        onError: (error) {
          statusNotifier.value = 'Download error: $error';
          _closeProgressWithDelay(navigator);
        },
      );
    } catch (e) {
      statusNotifier.value = 'Failed to execute update: $e';
      _closeProgressWithDelay(navigator);
    }
  }

  static void _closeProgressWithDelay(NavigatorState navigator) {
    Future.delayed(const Duration(seconds: 3), () {
      try {
        navigator.pop();
      } catch (_) {}
    });
  }
}

/// Helper class to combine two ValueListenables
class ValueListenableBuilder2<A, B> extends StatelessWidget {
  final ValueNotifier<A> first;
  final ValueNotifier<B> second;
  final Widget Function(BuildContext context, A a, B b, Widget? child) builder;
  final Widget? child;

  const ValueListenableBuilder2({
    super.key,
    required this.first,
    required this.second,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, _) {
            return builder(context, a, b, child);
          },
        );
      },
    );
  }
}
