import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/money_format.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../providers/owner_pricing_providers.dart';

class MembershipPlanListScreen extends ConsumerWidget {
  const MembershipPlanListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(ownerMembershipPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Membership plans')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/owner/membership-plans/new'),
        child: const Icon(Icons.add),
      ),
      body: plansAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load membership plans.',
          onRetry: () => ref.invalidate(ownerMembershipPlansProvider),
        ),
        data: (plans) {
          if (plans.isEmpty) {
            return const EmptyView(icon: Icons.card_membership_outlined, message: 'No membership plans yet. Tap + to add one.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ownerMembershipPlansProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: plans.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final plan = plans[index];
                return Card(
                  child: ListTile(
                    title: Text(plan.name),
                    subtitle: Text('${plan.currency} ${formatMoney(plan.price)} · ${plan.durationDays} days · ${plan.discountLabel} off'),
                    trailing: Chip(label: Text(plan.isActive ? 'Active' : 'Inactive')),
                    onTap: () => context.push('/owner/membership-plans/${plan.id}/edit'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
