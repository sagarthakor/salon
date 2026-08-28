import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../salon/presentation/providers/salon_providers.dart';
import '../../../services/data/models/salon_service.dart';
import '../../../services/data/models/service_category.dart';
import '../../../services/presentation/providers/service_providers.dart';
import '../providers/booking_providers.dart';
import 'booking_flow_scaffold.dart';

/// Step 1 of the booking flow: pick one or more services for the branch
/// selected on the home screen. `Select Branch → Select Service(s)` per
/// BOOKING_ENGINE.md's customer flow.
class BookingServiceSelectionScreen extends ConsumerStatefulWidget {
  const BookingServiceSelectionScreen({super.key});

  @override
  ConsumerState<BookingServiceSelectionScreen> createState() => _BookingServiceSelectionScreenState();
}

class _BookingServiceSelectionScreenState extends ConsumerState<BookingServiceSelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final branch = ref.read(selectedBranchProvider);
      final flow = ref.read(bookingFlowControllerProvider);
      if (branch != null && flow.branch?.id != branch.id) {
        ref.read(bookingFlowControllerProvider.notifier).selectBranch(branch);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(selectedBranchProvider);
    if (branch == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const ErrorView(message: 'No branch selected. Please go back and choose a branch.'),
      );
    }

    final servicesAsync = ref.watch(branchServicesProvider(branch.id));
    final flowState = ref.watch(bookingFlowControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(branch.name)),
      body: servicesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: 'Could not load services for this branch.',
          onRetry: () => ref.invalidate(branchServicesProvider(branch.id)),
        ),
        data: (branchServices) {
          if (branchServices.services.isEmpty) {
            return const EmptyView(
              icon: Icons.content_cut,
              message: 'This branch has no bookable services yet.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: branchServices.categories
                .where((c) => branchServices.forCategory(c.id).isNotEmpty)
                .map(
                  (category) => _CategorySection(
                    category: category,
                    services: branchServices.forCategory(category.id),
                  ),
                )
                .toList(),
          );
        },
      ),
      bottomNavigationBar: BookingFlowBottomBar(
        summaryLabel: flowState.selectedServices.isEmpty
            ? 'Select at least one service'
            : '${flowState.selectedServices.length} service(s) · ₹${flowState.estimatedTotal} · ${flowState.estimatedDurationMinutes} min',
        buttonLabel: 'Next',
        onPressed: flowState.canProceedPastServices ? () => context.push('/booking/schedule') : null,
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.services});

  final ServiceCategory category;
  final List<SalonService> services;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          ...services.map((service) => _ServiceTile(service: service)),
        ],
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  const _ServiceTile({required this.service});

  final SalonService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      bookingFlowControllerProvider.select((s) => s.selectedServices.any((sel) => sel.id == service.id)),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: CheckboxListTile(
        value: selected,
        onChanged: (_) => ref.read(bookingFlowControllerProvider.notifier).toggleService(service),
        title: Text(service.name),
        subtitle: service.description == null ? null : Text(service.description!),
        secondary: Text('₹${service.price}\n${service.durationMinutes} min', textAlign: TextAlign.right),
        isThreeLine: service.description != null,
      ),
    );
  }
}
