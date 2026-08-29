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

/// Step 1 of the booking flow: an ecommerce-style catalog — browse service
/// "products" as cards, add them to a cart, then continue. Same
/// `Select Branch → Select Service(s)` step per BOOKING_ENGINE.md, just
/// presented the way a shopping app would rather than a checkbox list.
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
    final cartCount = flowState.selectedServices.length;
    final matchingAudiences = ServiceAudience.values.where((a) => a.apiValue == audience);
    final audienceLabel = matchingAudiences.isEmpty ? null : matchingAudiences.first.label;

    return Scaffold(
      appBar: AppBar(
        title: Text(audienceLabel == null ? branch.name : '${branch.name} · $audienceLabel'),
        actions: [
          IconButton(
            tooltip: 'Cart',
            onPressed: cartCount == 0 ? null : () => context.push('/booking/cart'),
            icon: Badge(
              label: Text('$cartCount'),
              isLabelVisible: cartCount > 0,
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
        ],
      ),
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
        summaryLabel: cartCount == 0
            ? 'Add services to get started'
            : '$cartCount service${cartCount == 1 ? '' : 's'} · ₹${flowState.estimatedTotal}',
        buttonLabel: 'View Cart',
        onPressed: cartCount == 0 ? null : () => context.push('/booking/cart'),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: services.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (context, index) => _ServiceCard(service: services[index]),
          ),
        ],
      ),
    );
  }
}

/// One "product" in the catalog — tap the card to see full details, tap the
/// Add/Added button to add or remove it from the cart directly.
class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({required this.service});

  final SalonService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      bookingFlowControllerProvider.select((s) => s.selectedServices.any((sel) => sel.id == service.id)),
    );
    final controller = ref.read(bookingFlowControllerProvider.notifier);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showServiceDetailSheet(context, service: service),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 1.3, child: ServiceImage(imageUrl: service.imageUrl)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.name,
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (service.description != null && service.description!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            service.description!,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('₹${service.price}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            Text('${service.durationMinutes} min', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        SizedBox(
                          width: double.infinity,
                          height: 34,
                          child: selected
                              ? OutlinedButton.icon(
                                  onPressed: () => controller.toggleService(service),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Added'),
                                )
                              : FilledButton.icon(
                                  onPressed: () => controller.toggleService(service),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add'),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the service-detail bottom sheet — the ecommerce "product page"
/// equivalent, reused by both the catalog card and (in future) anywhere
/// else a service needs a closer look.
void showServiceDetailSheet(BuildContext context, {required SalonService service}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ServiceDetailSheet(service: service),
  );
}

class _ServiceDetailSheet extends ConsumerWidget {
  const _ServiceDetailSheet({required this.service});

  final SalonService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      bookingFlowControllerProvider.select((s) => s.selectedServices.any((sel) => sel.id == service.id)),
    );
    final controller = ref.read(bookingFlowControllerProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(aspectRatio: 1.6, child: ServiceImage(imageUrl: service.imageUrl)),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(service.name, style: Theme.of(context).textTheme.headlineSmall),
              if (service.description != null && service.description!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(service.description!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(Icons.currency_rupee, size: 18, color: Theme.of(context).colorScheme.primary),
                  Text('${service.price}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: AppSpacing.lg),
                  Icon(Icons.schedule, size: 18, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text('${service.durationMinutes} min', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              if (service.instagramUrl != null) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => openInstagramUrl(Uri.parse(service.instagramUrl!)),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Watch Service Video'),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: selected
                    ? OutlinedButton.icon(
                        onPressed: () {
                          controller.toggleService(service);
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Added — tap to remove'),
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          controller.toggleService(service);
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Add to Cart'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared service image with a clean placeholder — never a broken-image
/// icon — reused by the catalog card, the detail sheet, and the cart.
class ServiceImage extends StatelessWidget {
  const ServiceImage({super.key, required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _placeholder(context);
    }
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.content_cut, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
