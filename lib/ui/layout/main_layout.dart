import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../widgets/glass_sidebar.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
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
      const LibraryScreen(),
    ];
    
    return Scaffold(
      // Top AppBar for Mobile
      appBar: isDesktop ? null : AppBar(
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
            child: const Row(
              children: [
                Icon(Icons.search, color: Colors.white54, size: 20),
                SizedBox(width: 8),
                Text('Search for tracks, artists...', style: TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.white54),
            onPressed: () {},
          ),
        ],
      ),
      
      drawer: isDesktop ? null : GlassSidebar(
        selectedIndex: _selectedIndex,
        onItemSelected: (index) {
          setState(() => _selectedIndex = index);
          Navigator.of(context).pop(); // Close drawer on select
        },
      ),

      body: Stack(
        children: [
          Row(
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
        ],
      ),
      extendBody: true,
      bottomNavigationBar: const BottomPlayer(),
    );
  }
}
