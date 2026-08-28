import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../salon/presentation/providers/salon_providers.dart';
import '../../../services/data/models/salon_service.dart';
import '../../../services/data/models/service_audience.dart';
import '../../../services/data/models/service_category.dart';
import '../../../services/presentation/providers/service_providers.dart';
import '../../../services/presentation/service_instagram_launcher.dart';
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

    final audience = ref.watch(selectedAudienceProvider);
    final providerKey = (branchId: branch.id, audience: audience);
    final servicesAsync = ref.watch(branchServicesProvider(providerKey));
    final flowState = ref.watch(bookingFlowControllerProvider);
    final matchingAudiences = ServiceAudience.values.where((a) => a.apiValue == audience);
    final audienceLabel = matchingAudiences.isEmpty ? null : matchingAudiences.first.label;

    return Scaffold(
      appBar: AppBar(title: Text(audienceLabel == null ? branch.name : '${branch.name} · $audienceLabel')),
      body: servicesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: 'Could not load services for this branch.',
          onRetry: () => ref.invalidate(branchServicesProvider(providerKey)),
        ),
        data: (branchServices) {
          if (branchServices.services.isEmpty) {
            return EmptyView(
              icon: Icons.content_cut,
              message: audienceLabel == null
                  ? 'This branch has no bookable services yet.'
                  : 'No $audienceLabel services here yet. Please check back soon or choose another option.',
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
      child: InkWell(
        onTap: () => ref.read(bookingFlowControllerProvider.notifier).toggleService(service),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: selected, onChanged: (_) => ref.read(bookingFlowControllerProvider.notifier).toggleService(service)),
              _ServiceThumbnail(imageUrl: service.imageUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.name, style: Theme.of(context).textTheme.titleMedium),
                      if (service.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          service.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (service.instagramUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: InkWell(
                            onTap: () => openInstagramUrl(Uri.parse(service.instagramUrl!)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_circle_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Watch Service Video',
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('₹${service.price}\n${service.durationMinutes} min', textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceThumbnail extends StatelessWidget {
  const _ServiceThumbnail({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    if (imageUrl == null) {
      return _placeholder(context, size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context, size),
      ),
    );
  }

  Widget _placeholder(BuildContext context, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.content_cut, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
