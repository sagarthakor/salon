import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/models/booking.dart';
import '../providers/booking_providers.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myBookingsControllerProvider);
    final controller = ref.read(myBookingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Past')]),
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoadingFirstPage) return const LoadingView();
          if (state.error != null && state.bookings.isEmpty) {
            return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
          }
          final upcoming = state.bookings.where((b) => b.status.isUpcoming || b.status.isActive).toList();
          final past = state.bookings.where((b) => b.status.isTerminal).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _BookingList(
                bookings: upcoming,
                emptyMessage: 'No upcoming appointments.',
                hasMore: state.hasMore,
                isLoadingMore: state.isLoadingMore,
                onRefresh: controller.loadFirstPage,
                onLoadMore: controller.loadMore,
              ),
              _BookingList(
                bookings: past,
                emptyMessage: 'No past appointments yet.',
                hasMore: state.hasMore,
                isLoadingMore: state.isLoadingMore,
                onRefresh: controller.loadFirstPage,
                onLoadMore: controller.loadMore,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.bookings,
    required this.emptyMessage,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final List<Booking> bookings;
  final String emptyMessage;
  final bool hasMore;
  final bool isLoadingMore;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [SizedBox(height: 200, child: EmptyView(icon: Icons.event_note, message: emptyMessage))],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (hasMore &&
              !isLoadingMore &&
              notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
            onLoadMore();
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: bookings.length + (hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            if (index >= bookings.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _BookingTile(booking: bookings[index]);
          },
        ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('${booking.bookingDate} · ${booking.startTime}'),
        subtitle: Text('Total: ₹${booking.total}'),
        trailing: _StatusChip(booking: booking),
        onTap: () => context.push('/bookings/${booking.id}'),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = booking.status.isTerminal
        ? (booking.status.label == 'Cancelled' ? scheme.error : scheme.outline)
        : scheme.primary;
    return Chip(label: Text(booking.status.label), backgroundColor: color.withValues(alpha: 0.12));
  }
}
