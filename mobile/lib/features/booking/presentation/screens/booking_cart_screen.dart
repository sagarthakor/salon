import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../services/data/models/salon_service.dart';
import '../providers/booking_providers.dart';
import 'booking_flow_scaffold.dart';
import 'booking_service_selection_screen.dart' show ServiceImage;

/// The ecommerce-style cart step between picking services and choosing a
/// date/time — "Add services → Cart → Book appointment". Purely a view over
/// the existing [BookingFlowController] state (`selectedServices`); no new
/// pricing logic here at all — the server always recalculates and owns the
/// authoritative total when the booking is actually confirmed, exactly as
/// before this screen existed.
class BookingCartScreen extends ConsumerWidget {
  const BookingCartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flowState = ref.watch(bookingFlowControllerProvider);
    final controller = ref.read(bookingFlowControllerProvider.notifier);
    final services = flowState.selectedServices;

    return Scaffold(
      appBar: AppBar(title: const Text('Your Cart')),
      body: services.isEmpty
          ? const _EmptyCart()
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: services.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _CartRow(
                service: services[index],
                onRemove: () => controller.toggleService(services[index]),
              ),
            ),
      bottomNavigationBar: BookingFlowBottomBar(
        summaryLabel: services.isEmpty
            ? 'Your cart is empty'
            : '${services.length} service${services.length == 1 ? '' : 's'} · Total ₹${flowState.estimatedTotal}',
        buttonLabel: 'Continue to Appointment',
        onPressed: services.isEmpty ? null : () => context.push('/booking/schedule'),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.service, required this.onRemove});

  final SalonService service;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 56, height: 56, child: ServiceImage(imageUrl: service.imageUrl)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '₹${service.price} · ${service.durationMinutes} min',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Your cart is empty. Go back and add a service.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
