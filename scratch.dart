import 'dart:io';

void main() {
  final files = [
    'lib/ui/screens/playlist_screen.dart',
    'lib/ui/screens/artist_screen.dart',
    'lib/ui/screens/playing_screen.dart',
    'lib/ui/screens/library_screen.dart',
    'lib/ui/widgets/miniplayer_queue_view.dart'
  ];

  for (final file in files) {
    var f = File(file);
    if (!f.existsSync()) continue;
    var content = f.readAsStringSync();

    bool changed = false;

    // Add imports
    if (!content.contains('explicit_icon.dart')) {
      content = content.replaceFirst('import ', "import '../widgets/explicit_icon.dart';\nimport '../widgets/playing_track_mask.dart';\nimport ");
      // Handle the fact that some screens might be in different directories
      if (file.contains('widgets/')) {
        content = content.replaceAll("import '../widgets/explicit_icon.dart';", "import 'explicit_icon.dart';");
        content = content.replaceAll("import '../widgets/playing_track_mask.dart';", "import 'playing_track_mask.dart';");
      }
      changed = true;
    }

    // Replace ListTile wrapping
    // This is tricky because we need to parse the AST. Instead we can do a simple regex for title: Text(track.title...
    // Actually, it's easier to just regex replace `title: Text(track.title` -> `title: Row(children: [Expanded(child: Text(track.title`), etc.
    // And to wrap ListTile with PlayingTrackMask, it's better to just regex replace `return ListTile(` with `return PlayingTrackMask(track: track, child: ListTile(` if there is a `track` variable in scope. But we also need to add the closing `)`. 
  }
}
