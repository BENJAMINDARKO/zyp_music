import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../core/services/update_service.dart';
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
  Timer? _debounce;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(), // Search navigator
  ];

  late final List<NavigatorObserver> _navigatorObservers;

  @override
  void initState() {
    super.initState();
    _navigatorObservers = List.generate(
      4,
      (index) => _TabNavigatorObserver(() {
        if (mounted) {
          setState(() {});
        }
      }),
    );
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.checkForUpdates(context);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchNotifier.dispose();
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
    final activeIndex = _isSearching ? 3 : _selectedIndex;
    final bool hasPushedRoute = _navigatorKeys[activeIndex].currentState?.canPop() ?? false;


    return WillPopScope(
      onWillPop: () async {
        final activeIndex = _isSearching ? 3 : _selectedIndex;
        final navigator = _navigatorKeys[activeIndex].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.maybePop();
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
      appBar: hasPushedRoute ? null : AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo.png', height: 36),
        ),
        leadingWidth: 52,
        title: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.magnifyingGlass, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search for tracks, artists...',
                    hintStyle: TextStyle(fontSize: 14, color: Colors.white54),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  onSubmitted: (value) {
                    setState(() {
                      _submittedQuery = value;
                    });
                    _searchNotifier.value = value;
                  },
                ),
              ),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(PhosphorIconsRegular.x, color: Colors.white54, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _submittedQuery = '';
                    });
                    _searchNotifier.value = '';
                  },
                ),
            ],
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
      observers: [_navigatorObservers[index]],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(
          builder: (context) => rootScreen,
        );
      },
    );
  }
}

class _TabNavigatorObserver extends NavigatorObserver {
  final VoidCallback onStateChanged;

  _TabNavigatorObserver(this.onStateChanged);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => onStateChanged());
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => onStateChanged());
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => onStateChanged());
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => onStateChanged());
  }
}
