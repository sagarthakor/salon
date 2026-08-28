import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../customers/presentation/providers/owner_customer_list_controller.dart';
import '../providers/owner_pricing_providers.dart';

class OwnerMembershipsScreen extends ConsumerWidget {
  const OwnerMembershipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membershipsAsync = ref.watch(ownerMembershipsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Customer memberships')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGrantDialog(context, ref),
        icon: const Icon(Icons.card_membership),
        label: const Text('Grant'),
      ),
      body: membershipsAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load memberships.',
          onRetry: () => ref.invalidate(ownerMembershipsProvider),
        ),
        data: (memberships) {
          if (memberships.isEmpty) {
            return const EmptyView(icon: Icons.card_membership_outlined, message: 'No customer memberships yet.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ownerMembershipsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: memberships.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final membership = memberships[index];
                return Card(
                  child: ListTile(
                    title: Text(membership.plan?.name ?? 'Membership'),
                    subtitle: Text('${membership.status} · expires ${membership.expiresAt.split('T').first} · ${membership.source}'),
                    trailing: membership.isCurrentlyActive
                        ? IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            tooltip: 'Cancel membership',
                            onPressed: () async {
                              await ref.read(ownerMembershipRepositoryProvider).cancel(membership.id);
                              ref.invalidate(ownerMembershipsProvider);
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showGrantDialog(BuildContext context, WidgetRef ref) async {
    String? customerId;
    String? planId;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final customersAsync = ref.watch(ownerCustomerListControllerProvider);
          final plansAsync = ref.watch(ownerMembershipPlansProvider);
          return AlertDialog(
            title: const Text('Grant a membership'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: customerId,
                  decoration: const InputDecoration(labelText: 'Customer'),
                  items: customersAsync.customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setState(() => customerId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                plansAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('Could not load plans.'),
                  data: (plans) => DropdownButtonFormField<String>(
                    initialValue: planId,
                    decoration: const InputDecoration(labelText: 'Plan'),
                    items: plans.where((p) => p.isActive).map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                    onChanged: (v) => setState(() => planId = v),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              PrimaryButton(
                label: 'Grant',
                onPressed: () async {
                  if (customerId == null || planId == null) {
                    setState(() => error = 'Select a customer and a plan.');
                    return;
                  }
                  try {
                    await ref.read(ownerMembershipRepositoryProvider).grant(customerId: customerId!, membershipPlanId: planId!);
                    ref.invalidate(ownerMembershipsProvider);
                    if (context.mounted) Navigator.of(context).pop();
                  } on ApiException catch (e) {
                    setState(() => error = e.message);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
