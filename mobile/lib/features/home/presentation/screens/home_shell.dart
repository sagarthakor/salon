import 'package:flutter/material.dart';

import '../../../../core/brand/brand_config.dart';
import '../../../booking/presentation/screens/my_bookings_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import 'branded_home_tab.dart';
import 'home_tab.dart';

/// Persistent bottom-navigation shell for the three authenticated tabs.
/// Deliberately a plain `IndexedStack` (not a go_router `ShellRoute`) to keep
/// routing simple for this phase's scope — each tab keeps its own scroll/tab
/// state alive when switching away and back.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // A branded single-salon app (see BrandConfig) has no discovery/search UI
  // — BrandedHomeTab replaces HomeTab's salon list with the fixed salon and
  // a direct "Book Now" entry point. The other two tabs are unchanged and
  // fully reused.
  static final List<Widget> _tabs = [
    BrandConfig.current.singleSalon ? const BrandedHomeTab() : const HomeTab(),
    const MyBookingsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
