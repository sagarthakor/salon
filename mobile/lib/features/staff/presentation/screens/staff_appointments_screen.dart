import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../booking/data/models/booking.dart';
import '../../../owner/bookings/presentation/providers/owner_bookings_controller.dart';
import '../providers/staff_booking_providers.dart';

/// My Appointments — Upcoming / Today / Past, grouped client-side from one
/// real, already-authorized fetch (`BookingRepository.ownerBookings(staffId:
/// ...)`, the exact same descending list the backend already returns — no
/// server-side date-range filter exists here, matching how the customer
/// app's own `MyBookingsScreen` already splits Upcoming/Past from a single
/// list; see STAFF_APP_ARCHITECTURE.md). The `staff_id` filter is what
/// actually scopes this to the signed-in staff member — grouping by date
/// only reorganizes an already-narrowed, already-authorized result.
class StaffAppointmentsScreen extends ConsumerStatefulWidget {
  const StaffAppointmentsScreen({super.key, required this.staffId});

  final String staffId;

  @override
  ConsumerState<StaffAppointmentsScreen> createState() => _StaffAppointmentsScreenState();
}

class _StaffAppointmentsScreenState extends ConsumerState<StaffAppointmentsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(staffAppointmentsControllerProvider(widget.staffId));
    final controller = ref.read(staffAppointmentsControllerProvider(widget.staffId).notifier);
    final today = toApiDate(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Appointments'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Today'), Tab(text: 'Past')]),
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoadingFirstPage) return const LoadingView();
          if (state.error != null && state.bookings.isEmpty) {
            return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
          }
          final upcoming = state.bookings
              .where((b) => b.bookingDate.compareTo(today) > 0 && (b.status.isUpcoming || b.status.isActive))
              .toList();
          final todayList = state.bookings.where((b) => b.bookingDate == today).toList();
          final past = state.bookings
              .where((b) => b.bookingDate.compareTo(today) < 0 || b.status.isTerminal)
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _AppointmentList(bookings: upcoming, emptyMessage: 'No upcoming appointments.', state: state, controller: controller),
              _AppointmentList(bookings: todayList, emptyMessage: 'No appointments today.', state: state, controller: controller),
              _AppointmentList(bookings: past, emptyMessage: 'No past appointments yet.', state: state, controller: controller),
            ],
          );
        },
      ),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({required this.bookings, required this.emptyMessage, required this.state, required this.controller});

  final List<Booking> bookings;
  final String emptyMessage;
  final OwnerBookingsState state;
  final OwnerBookingsController controller;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.loadFirstPage,
        child: ListView(
          children: [SizedBox(height: 200, child: EmptyView(icon: Icons.event_note, message: emptyMessage))],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.loadFirstPage,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (state.hasMore && !state.isLoadingMore && notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
            controller.loadMore();
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: bookings.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => _AppointmentTile(booking: bookings[index]),
        ),
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('${booking.bookingDate} · ${booking.startTime}'),
        subtitle: Text(booking.customer?.name ?? booking.items.map((i) => i.serviceName).join(', ')),
        trailing: Chip(label: Text(booking.status.label)),
        onTap: () => context.push('/staff/appointments/${booking.id}'),
      ),
    );
  }
}
