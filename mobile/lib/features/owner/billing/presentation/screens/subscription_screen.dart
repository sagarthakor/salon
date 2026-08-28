import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/subscription.dart';
import '../providers/billing_providers.dart';

/// The owner app's billing home — always reachable regardless of
/// subscription status (Phase 10 §40: "Owner/Admin must be able to access
/// billing even when subscription is expired... Do NOT redirect expired
/// owners to login"). Every price/date shown here comes straight from the
/// backend; nothing is hard-coded — see SAAS_BILLING_ARCHITECTURE.md.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionAsync = ref.watch(subscriptionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(subscriptionProvider),
        child: subscriptionAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: 400,
                child: ErrorView(message: 'Could not load your subscription.', onRetry: () => ref.invalidate(subscriptionProvider)),
              ),
            ],
          ),
          data: (subscription) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _StatusBanner(subscription: subscription),
              const SizedBox(height: AppSpacing.lg),
              if (subscription.plan != null) _PlanCard(subscription: subscription),
              const SizedBox(height: AppSpacing.lg),
              _ActionButtons(subscription: subscription),
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Payment history'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/owner/subscription/payments'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Invoice history'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/owner/subscription/invoices'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (subscription.status) {
      'active' || 'trialing' => scheme.primaryContainer,
      'past_due' || 'grace_period' => scheme.tertiaryContainer,
      _ => scheme.errorContainer,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Chip(label: Text(subscription.statusLabel)),
              if (subscription.cancelAtPeriodEnd) ...[
                const SizedBox(width: AppSpacing.sm),
                const Chip(label: Text('Cancels at period end')),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(subscription.statusMessage),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final plan = subscription.plan!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(plan.billingSummary, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            if (subscription.status == 'trialing' && subscription.trialEndsAt != null)
              Text('Trial ends ${toDisplayDate(subscription.trialEndsAt!)}'),
            if (subscription.currentPeriodEnd != null)
              Text('${subscription.cancelAtPeriodEnd ? 'Access ends' : 'Next billing date'}: ${toDisplayDate(subscription.currentPeriodEnd!)}'),
            if (subscription.status == 'grace_period' && subscription.graceEndsAt != null)
              Text('Renew by ${toDisplayDate(subscription.graceEndsAt!)} to avoid losing access.'),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsRenewal = ['past_due', 'grace_period', 'cancelled', 'expired'].contains(subscription.status);
    final canCancel = !subscription.isTerminal && !subscription.cancelAtPeriodEnd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subscription.status == 'trialing')
          FilledButton(
            onPressed: () => context.push('/owner/subscription/plans'),
            child: const Text('Subscribe now'),
          ),
        if (needsRenewal)
          FilledButton(
            onPressed: () => context.push('/owner/subscription/plans'),
            child: const Text('Renew subscription'),
          ),
        if (canCancel) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => _confirmCancel(context, ref),
            child: const Text('Cancel subscription'),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel subscription?'),
        content: const Text('Your salon will keep full access until the end of the current billing period, then the subscription will end.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep subscription')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Cancel subscription')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(subscriptionRepositoryProvider).cancel();
      ref.invalidate(subscriptionProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
