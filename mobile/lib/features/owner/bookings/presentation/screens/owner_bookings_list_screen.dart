import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../booking/data/models/booking.dart';
import '../../../../booking/data/models/booking_status.dart';
import '../../../branches/presentation/providers/owner_branch_providers.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../providers/owner_bookings_controller.dart';
import '../providers/owner_booking_providers.dart';

class OwnerBookingsListScreen extends ConsumerWidget {
  const OwnerBookingsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ownerBookingsControllerProvider);
    final controller = ref.read(ownerBookingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings'),
        actions: [
          IconButton(
            icon: Icon(state.filters.isEmpty ? Icons.filter_list : Icons.filter_alt),
            onPressed: () => _openFilters(context, ref),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoadingFirstPage) return const LoadingView();
          if (state.error != null && state.bookings.isEmpty) {
            return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
          }
          if (state.bookings.isEmpty) {
            return RefreshIndicator(
              onRefresh: controller.loadFirstPage,
              child: ListView(
                children: const [SizedBox(height: 200, child: EmptyView(icon: Icons.event_busy, message: 'No bookings match these filters.'))],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: controller.loadFirstPage,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (state.hasMore &&
                    !state.isLoadingMore &&
                    notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                  controller.loadMore();
                }
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: state.bookings.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index >= state.bookings.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _OwnerBookingTile(booking: state.bookings[index]);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openFilters(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _FilterSheet(),
    );
  }
}

class _OwnerBookingTile extends StatelessWidget {
  const _OwnerBookingTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('${booking.bookingDate} · ${booking.startTime}'),
        subtitle: Text(booking.customer?.name ?? 'Total: ₹${booking.total}'),
        trailing: Chip(label: Text(booking.status.label)),
        onTap: () => context.push('/owner/bookings/${booking.id}'),
      ),
    );
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  String? _date;
  String? _status;
  String? _branchId;
  String? _staffId;

  @override
  void initState() {
    super.initState();
    final filters = ref.read(ownerBookingsControllerProvider).filters;
    _date = filters.date;
    _status = filters.status;
    _branchId = filters.branchId;
    _staffId = filters.staffId;
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(ownerBranchesProvider);
    final staffAsync = ref.watch(staffListProvider);
    final today = toApiDate(DateTime.now());
    final tomorrow = toApiDate(DateTime.now().add(const Duration(days: 1)));

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filter bookings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(label: const Text('Today'), selected: _date == today, onSelected: (_) => setState(() => _date = today)),
              ChoiceChip(
                label: const Text('Tomorrow'),
                selected: _date == tomorrow,
                onSelected: (_) => setState(() => _date = tomorrow),
              ),
              ChoiceChip(label: const Text('Any date'), selected: _date == null, onSelected: (_) => setState(() => _date = null)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String?>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any status')),
              ...BookingStatus.values.map((s) => DropdownMenuItem(value: s.apiValue, child: Text(s.label))),
            ],
            onChanged: (value) => setState(() => _status = value),
          ),
          const SizedBox(height: AppSpacing.md),
          branchesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (branches) => DropdownButtonFormField<String?>(
              initialValue: _branchId,
              decoration: const InputDecoration(labelText: 'Branch'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Any branch')),
                ...branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
              ],
              onChanged: (value) => setState(() => _branchId = value),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          staffAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (staff) => DropdownButtonFormField<String?>(
              initialValue: _staffId,
              decoration: const InputDecoration(labelText: 'Staff'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Any staff')),
                ...staff.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
              ],
              onChanged: (value) => setState(() => _staffId = value),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(ownerBookingsControllerProvider.notifier).setFilters(const OwnerBookingFilters());
                    Navigator.of(context).pop();
                  },
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    ref
                        .read(ownerBookingsControllerProvider.notifier)
                        .setFilters(OwnerBookingFilters(date: _date, status: _status, branchId: _branchId, staffId: _staffId));
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
