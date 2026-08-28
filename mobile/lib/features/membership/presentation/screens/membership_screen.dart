import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/models/customer_membership.dart';
import '../../data/models/membership_plan.dart';
import '../providers/membership_providers.dart';

/// Customer-facing membership screen: current status (if any) plus
/// available plans to purchase/renew. Every price/benefit shown here is the
/// server's own data — never fabricated client-side (see
/// LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md).
class MembershipScreen extends ConsumerWidget {
  const MembershipScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAsync = ref.watch(currentMembershipProvider);
    final plansAsync = ref.watch(membershipPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentMembershipProvider);
          ref.invalidate(membershipPlansProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            currentAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.md), child: LoadingView()),
              error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load your membership.'),
              data: (membership) => _CurrentMembershipCard(membership: membership),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Available plans', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            plansAsync.when(
              loading: () => const LoadingView(),
              error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load plans.'),
              data: (plans) => plans.isEmpty
                  ? const EmptyView(icon: Icons.card_membership_outlined, message: 'No membership plans are available yet.')
                  : Column(children: plans.map((p) => _PlanTile(plan: p)).toList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentMembershipCard extends StatelessWidget {
  const _CurrentMembershipCard({required this.membership});

  final CustomerMembership? membership;

  @override
  Widget build(BuildContext context) {
    final membership = this.membership;
    if (membership == null || !membership.isCurrentlyActive) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text('You do not have an active membership yet.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.card_membership),
                const SizedBox(width: AppSpacing.sm),
                Text(membership.plan?.name ?? 'Membership', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Active until ${membership.expiresAt.split('T').first}'),
            if (membership.plan != null) Text('Benefit: ${membership.plan!.discountLabel} off eligible services'),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan});

  final MembershipPlan plan;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text(plan.name),
        subtitle: Text('${plan.discountLabel} off · ${plan.durationDays} days'),
        trailing: FilledButton(
          onPressed: () => context.push('/membership/checkout/${plan.id}'),
          child: Text('${plan.currency} ${formatMoney(plan.price)}'),
        ),
      ),
    );
  }
}
