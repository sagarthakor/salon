import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/plan.dart';
import '../providers/billing_providers.dart';

/// Every plan (name, price, billing interval, trial length) comes from
/// `GET /subscription/plans` — never hard-coded. Tapping a plan only ever
/// sends its `id` onward to checkout; the price shown here and the price
/// actually charged both come from the same database row. See
/// SAAS_BILLING_ARCHITECTURE.md.
class PlanSelectionScreen extends ConsumerWidget {
  const PlanSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(subscriptionPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a plan')),
      body: plansAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: 'Could not load plans.',
          onRetry: () => ref.invalidate(subscriptionPlansProvider),
        ),
        data: (plans) {
          if (plans.isEmpty) {
            return const EmptyView(icon: Icons.card_membership_outlined, message: 'No plans are available right now.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: plans.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _PlanTile(plan: plans[index]),
          );
        },
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.name, style: Theme.of(context).textTheme.titleMedium),
            if (plan.description != null && plan.description!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(plan.description!),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(plan.billingSummary, style: Theme.of(context).textTheme.headlineSmall),
            if (plan.trialDays > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('${plan.trialDays}-day free trial', style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => context.push('/owner/subscription/checkout/${plan.id}'),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }
}
