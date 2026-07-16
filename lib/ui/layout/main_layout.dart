import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../core/theme/app_theme.dart';
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
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.checkForUpdates(context);
        UpdateService.startPeriodicCheck(context);
      }
    });
  }

  @override
  void dispose() {
    UpdateService.stopPeriodicCheck();
    super.dispose();
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  String _getTabTitle(int index) {
    switch (index) {
      case 0:
        return 'Home';
      case 1:
        return 'Echo Search';
      case 2:
        return 'Mood Orbit';
      case 3:
        return 'Wave Library';
      default:
        return 'Home';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final bool hasPushedRoute = _navigatorKeys[_selectedIndex].currentState?.canPop() ?? false;

    return WillPopScope(
      onWillPop: () async {
        final navigator = _navigatorKeys[_selectedIndex].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.maybePop();
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
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    ZypAuroraColors.cyan,
                    ZypAuroraColors.violet,
                    ZypAuroraColors.pink,
                    ZypAuroraColors.peach,
                    ZypAuroraColors.cyan,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x599F7AEA),
                    blurRadius: 34,
                    offset: Offset(0, 14),
                  )
                ],
              ),
              child: Center(
                child: Image.asset('assets/logo.png', height: 26, width: 26, errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white)),
              ),
            ),
          ),
          leadingWidth: 52,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ZYP GLASSSTREAM',
                style: TextStyle(
                  color: ZypAuroraColors.cyan,
                  fontSize: 10,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _getTabTitle(_selectedIndex),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                ),
              ),
            ],
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
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  if (isDesktop)
                    GlassSidebar(
                      selectedIndex: _selectedIndex,
                      onItemSelected: _selectTab,
                      onSettingsTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsScreen())
                        );
                      },
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: [
                        _buildTabNavigator(0, const HomeScreen()),
                        _buildTabNavigator(1, const SearchScreen()),
                        _buildTabNavigator(2, const MusicNowScreen()),
                        _buildTabNavigator(3, const LibraryScreen()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!isDesktop)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BottomPlayer(),
                      const SizedBox(height: 10),
                      _buildFloatingBottomNav(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingBottomNav() {
    final navItems = [
      {'icon': '✦', 'label': 'Home'},
      {'icon': '⌕', 'label': 'Search'},
      {'icon': '◒', 'label': 'Music'},
      {'icon': '≋', 'label': 'Library'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: ZypAuroraColors.glassSoft,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: ZypAuroraColors.stroke,
                width: 1,
              ),
            ),
            child: Row(
              children: List.generate(4, (index) {
                final item = navItems[index];
                final isSelected = _selectedIndex == index;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _selectTab(index),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      decoration: isSelected
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: RadialGradient(
                                center: const Alignment(0.0, -1.0),
                                radius: 0.58,
                                colors: [
                                  ZypAuroraColors.cyan.withOpacity(0.22),
                                  Colors.transparent,
                                ],
                              ),
                              color: Colors.white.withOpacity(0.10),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.09),
                                width: 1,
                              ),
                            )
                          : null,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item['icon']!,
                            style: TextStyle(
                              fontSize: 18,
                              color: isSelected ? Colors.white : Colors.white.withOpacity(0.54),
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            item['label']!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isSelected ? Colors.white : Colors.white.withOpacity(0.54),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
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
