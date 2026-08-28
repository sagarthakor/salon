import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../data/models/booking_pricing.dart';
import '../providers/booking_flow_state.dart';
import '../providers/booking_providers.dart';
import 'booking_flow_scaffold.dart';

/// Step 3: final review before submitting. Reiterates that pricing shown
/// here is an estimate — the server computes and owns the authoritative
/// total, which is what the confirmation screen displays.
class BookingSummaryScreen extends ConsumerStatefulWidget {
  const BookingSummaryScreen({super.key});

  @override
  ConsumerState<BookingSummaryScreen> createState() => _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends ConsumerState<BookingSummaryScreen> {
  final _notesController = TextEditingController();
  final _couponController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    _couponController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flowState = ref.watch(bookingFlowControllerProvider);
    final controller = ref.read(bookingFlowControllerProvider.notifier);
    final pricing = flowState.pricing;

    return Scaffold(
      appBar: AppBar(title: const Text('Review your booking')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (flowState.submissionError != null) _ErrorBanner(message: flowState.submissionError!),
          _SummaryCard(flowState: flowState),
          if (flowState.requiresPhone) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              "It looks like this is your first time booking with this salon — we just need a phone number to set up your customer profile.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              onChanged: controller.setPhone,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 3,
            onChanged: controller.setNotes,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  decoration: const InputDecoration(labelText: 'Coupon code (optional)'),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: controller.setCouponCode,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonal(
                onPressed: flowState.isPricingLoading ? null : controller.previewPricing,
                child: flowState.isPricingLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Apply'),
              ),
            ],
          ),
          if (flowState.pricingError != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(flowState.pricingError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (pricing != null) ...[
            const SizedBox(height: AppSpacing.md),
            _PricingCard(pricing: pricing),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'The salon confirms the final price, staff assignment, and appointment time. '
            'Amounts shown here are an estimate — the server always recalculates the final total.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      bottomNavigationBar: BookingFlowBottomBar(
        summaryLabel: 'Total (estimated): ₹${pricing?.total ?? flowState.estimatedTotal}',
        buttonLabel: 'Confirm',
        isLoading: flowState.isSubmitting,
        onPressed: flowState.canConfirm
            ? () async {
                final success = await controller.confirmBooking();
                if (!context.mounted) return;
                if (success) {
                  context.push('/booking/confirmation');
                }
              }
            : null,
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.pricing});

  final BookingPricing pricing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(label: 'Subtotal', value: '₹${pricing.subtotal}'),
            if (pricing.couponDiscount > 0) _Row(label: 'Coupon', value: '-₹${pricing.couponDiscount}'),
            if (pricing.membershipDiscount > 0) _Row(label: 'Membership', value: '-₹${pricing.membershipDiscount}'),
            if (pricing.loyaltyDiscount > 0) _Row(label: 'Loyalty (${pricing.loyaltyPointsRedeemed} pts)', value: '-₹${pricing.loyaltyDiscount}'),
            const Divider(),
            _Row(label: 'Total', value: '₹${pricing.total}'),
            for (final message in pricing.messages) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.flowState});

  final BookingFlowState flowState;

  @override
  Widget build(BuildContext context) {
    final slot = flowState.selectedSlot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(label: 'Branch', value: flowState.branch?.name ?? '—'),
            const Divider(),
            _Row(
              label: 'Services',
              value: flowState.selectedServices.map((s) => s.name).join(', '),
            ),
            const Divider(),
            _Row(
              label: 'Staff',
              value: flowState.staffMode == StaffSelectionMode.any
                  ? 'Any available'
                  : (flowState.availability?.staffNameFor(flowState.selectedStaffId ?? '') ?? 'Selected staff'),
            ),
            const Divider(),
            _Row(
              label: 'Date',
              value: flowState.date != null ? toApiDate(flowState.date!) : '—',
            ),
            const Divider(),
            _Row(
              label: 'Time',
              value: slot != null
                  ? '${toDisplayTime(slot.startTime)} – ${toDisplayTime(slot.endTime)}'
                  : '—',
            ),
            const Divider(),
            _Row(label: 'Duration', value: '${flowState.estimatedDurationMinutes} min'),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
