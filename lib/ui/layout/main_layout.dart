import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../widgets/glass_sidebar.dart';
import '../screens/home_screen.dart';
import '../screens/music_now_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/library_screen.dart';
import '../widgets/bottom_player.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final List<Widget> screens = [
      const HomeScreen(),
      const MusicNowScreen(),
      const LibraryScreen(),
    ];

    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        elevation: 0,
        leading: GestureDetector(
          onTap: () => setState(() => _selectedIndex = 0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Image.asset('assets/logo.png', height: 36),
          ),
        ),
        leadingWidth: 52,
        title: GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
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
            key: const Key('settings-button'),
            icon: Icon(PhosphorIconsRegular.gear),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (isDesktop)
                  GlassSidebar(
                    selectedIndex: _selectedIndex,
                    onItemSelected: (index) {
                      setState(() => _selectedIndex = index);
                    },
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: screens,
                  ),
                ),
              ],
            ),
          ),
          const BottomPlayer(),
          if (!isDesktop)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                    width: 0.5,
                  ),
                ),
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) => setState(() => _selectedIndex = index),
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: Theme.of(context).colorScheme.onSurface,
                unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(PhosphorIconsRegular.house),
                    activeIcon: Icon(PhosphorIconsFill.house),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(PhosphorIconsRegular.musicNotesSimple),
                    activeIcon: Icon(PhosphorIconsFill.musicNotesSimple),
                    label: 'Music Now',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(PhosphorIconsRegular.bookOpen),
                    activeIcon: Icon(PhosphorIconsFill.bookOpen),
                    label: 'Library',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
