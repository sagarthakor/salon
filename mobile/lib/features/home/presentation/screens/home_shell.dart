import 'package:flutter/material.dart';

import '../../../booking/presentation/screens/my_bookings_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
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

  static const _tabs = [HomeTab(), MyBookingsScreen(), ProfileScreen()];

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
