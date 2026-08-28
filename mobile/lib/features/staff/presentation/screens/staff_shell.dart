import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/staff_self_providers.dart';
import 'my_services_screen.dart';
import 'staff_appointments_screen.dart';
import 'staff_profile_screen.dart';
import 'staff_schedule_screen.dart';
import 'staff_today_tab.dart';

/// Staff bottom-navigation shell — the same `IndexedStack` pattern as
/// `HomeShell`/`OwnerShell` (see FLUTTER_ARCHITECTURE.md), but resolves the
/// signed-in staff member's own profile via [staffMeProvider] first: every
/// tab below needs the real, server-derived staff id, and a client never
/// supplies or guesses that id itself (see STAFF_APP_ARCHITECTURE.md).
class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final meAsync = ref.watch(staffMeProvider);

    return meAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Staff')),
        body: _AccountNotConfigured(
          message: error is ApiException && error.type == ApiErrorType.notFound
              ? 'No staff profile is linked to your account yet. Ask your salon owner to link it.'
              : (error is ApiException ? error.message : 'Could not load your staff profile.'),
          onRetry: () => ref.invalidate(staffMeProvider),
        ),
      ),
      data: (staff) {
        final tabs = [
          StaffTodayTab(staffId: staff.id),
          StaffAppointmentsScreen(staffId: staff.id),
          StaffScheduleScreen(staffId: staff.id),
          MyServicesScreen(staffId: staff.id),
          StaffProfileScreen(staff: staff),
        ];
        return Scaffold(
          body: IndexedStack(index: _index, children: tabs),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
              NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Appointments'),
              NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Schedule'),
              NavigationDestination(icon: Icon(Icons.content_cut_outlined), selectedIcon: Icon(Icons.content_cut), label: 'Services'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        );
      },
    );
  }
}

class _AccountNotConfigured extends ConsumerWidget {
  const _AccountNotConfigured({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
                const SizedBox(width: 12),
                TextButton(onPressed: () => ref.read(authControllerProvider.notifier).logout(), child: const Text('Log out')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
