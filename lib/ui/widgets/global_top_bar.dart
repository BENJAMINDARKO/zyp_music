import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';

class GlobalTopBar extends StatelessWidget implements PreferredSizeWidget {
  const GlobalTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Image.asset('assets/logo.png', height: 36),
      ),
      leadingWidth: 52,
      title: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchScreen())
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.magnifyingGlass, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text('Search for tracks, artists...', style: TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(PhosphorIconsRegular.gear),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen())
            );
          },
        ),
      ],
    );
  }
}
