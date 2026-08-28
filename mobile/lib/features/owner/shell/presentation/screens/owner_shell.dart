import 'package:flutter/material.dart';

import '../../../bookings/presentation/screens/owner_bookings_list_screen.dart';
import '../../../customers/presentation/screens/customer_list_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_tab.dart';
import '../../../staff/presentation/screens/staff_list_screen.dart';
import 'more_tab.dart';

/// Owner/admin bottom-navigation shell — the equivalent of `HomeShell` for
/// the customer app, same `IndexedStack` pattern (see FLUTTER_ARCHITECTURE.md).
class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key});

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  int _index = 0;

  static const _tabs = [
    DashboardTab(),
    OwnerBookingsListScreen(),
    StaffListScreen(),
    CustomerListScreen(),
    MoreTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Staff'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Customers'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
