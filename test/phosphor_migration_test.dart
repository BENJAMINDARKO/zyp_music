import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrated UI files contain no Icons.* references', () async {
    final migratedFiles = [
      'lib/ui/layout/main_layout.dart',
      'lib/ui/widgets/glass_sidebar.dart',
      'lib/ui/widgets/global_background.dart',
      'lib/ui/widgets/bottom_player.dart',
      'lib/ui/widgets/miniplayer_queue_view.dart',
      'lib/ui/widgets/miniplayer_timer_view.dart',
      'lib/ui/screens/playing_screen.dart',
      'lib/ui/widgets/synced_lyrics_widget.dart',
      'lib/ui/widgets/track_context_menu.dart',
      'lib/ui/widgets/album_context_menu.dart',
      'lib/ui/widgets/playlist_picker_dialog.dart',
      'lib/ui/widgets/add_to_playlist_modal.dart',
      'lib/ui/widgets/auto_dj_mode_picker.dart',
      'lib/ui/widgets/track_download_icon.dart',
      'lib/ui/widgets/album_download_icon.dart',
      'lib/ui/widgets/custom_audio_seekbar.dart',
      'lib/ui/widgets/seekbar_connector.dart',
      'lib/ui/widgets/audio_visualizer.dart',
      'lib/ui/screens/home_screen.dart',
      'lib/ui/screens/library_screen.dart',
      'lib/ui/screens/search_screen.dart',
      'lib/ui/screens/settings_screen.dart',
      'lib/ui/screens/album_screen.dart',
      'lib/ui/screens/artist_screen.dart',
      'lib/ui/screens/playlist_screen.dart',
      'lib/ui/screens/youtube_login_webview.dart',
    ];

    final remaining = <String>[];
    final iconPattern = RegExp(r'\bIcons\.\w+');

    for (final path in migratedFiles) {
      final file = File(path);
      if (!file.existsSync()) {
        remaining.add('$path (FILE NOT FOUND)');
        continue;
      }
      final content = await file.readAsString();
      final matches = iconPattern.allMatches(content);
      for (final match in matches) {
        remaining.add('$path: ${match.group(0)}');
      }
    }

    expect(remaining, isEmpty,
        reason: 'Found unmigrated Icons.* references:\n${remaining.join('\n')}');
  });
}
