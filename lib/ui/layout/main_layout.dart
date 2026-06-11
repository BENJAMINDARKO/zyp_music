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
  bool _isSearching = false;
  String _searchQuery = '';
  String _submittedQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<String> _searchNotifier = ValueNotifier<String>('');

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(), // Search navigator
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus) {
        setState(() => _isSearching = true);
      }
    });
  }

  @override
  void dispose() {
    _searchNotifier.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (_isSearching) {
      setState(() {
        _isSearching = false;
        _searchController.clear();
        _searchFocusNode.unfocus();
        _selectedIndex = index;
      });
      return;
    }
    if (_selectedIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;


    return WillPopScope(
      onWillPop: () async {
        final activeIndex = _isSearching ? 3 : _selectedIndex;
        final navigator = _navigatorKeys[activeIndex].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
          return false;
        }
        if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _searchFocusNode.unfocus();
          });
          return false;
        }
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return false;
        }
        return true;
      },
      child: Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo.png', height: 36),
        ),
        leadingWidth: 52,
        title: Container(
          height: 40,
          decoration: const ShapeDecoration(
            color: Colors.white10,
            shape: StadiumBorder(),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search for tracks, artists...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, color: Colors.white54, size: 20),
              border: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(PhosphorIconsRegular.x, color: Colors.white54, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _submittedQuery = '';
                        });
                      },
                    )
                  : null,
            ),
              onSubmitted: (value) {
                setState(() {
                  _submittedQuery = value;
                });
                _searchNotifier.value = value;
              },
            ),
        ),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.gear),
            onPressed: () {
              final activeIndex = _isSearching ? 3 : _selectedIndex;
              _navigatorKeys[activeIndex].currentState?.push(
                MaterialPageRoute(builder: (_) => const SettingsScreen())
              );
            },
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
                    onItemSelected: _selectTab,
                    onSettingsTap: () {
                      final activeIndex = _isSearching ? 3 : _selectedIndex;
                      _navigatorKeys[activeIndex].currentState?.push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen())
                      );
                    },
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _isSearching ? 3 : _selectedIndex,
                    children: [
                      _buildTabNavigator(0, const HomeScreen()),
                      _buildTabNavigator(1, const MusicNowScreen()),
                      _buildTabNavigator(2, const LibraryScreen()),
                      _buildTabNavigator(3, SearchScreen(
                        initialQuery: _submittedQuery,
                        searchNotifier: _searchNotifier,
                      )),
                    ],
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
                currentIndex: _isSearching ? 0 : _selectedIndex,
                onTap: _selectTab,
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: _isSearching ? Theme.of(context).colorScheme.onSurface.withOpacity(0.54) : Theme.of(context).colorScheme.onSurface,
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
      ),
    );
  }

  Widget _buildTabNavigator(int index, Widget rootScreen) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(
          builder: (context) => rootScreen,
        );
      },
    );
  }
}
