import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../providers/owner_branch_providers.dart';

class BranchDetailsScreen extends ConsumerWidget {
  const BranchDetailsScreen({super.key, required this.branchId});

  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchAsync = ref.watch(ownerBranchDetailsProvider(branchId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch'),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => context.push('/owner/branches/$branchId/edit')),
        ],
      ),
      body: branchAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load this branch.',
          onRetry: () => ref.invalidate(ownerBranchDetailsProvider(branchId)),
        ),
        data: (branch) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(branch.name, style: Theme.of(context).textTheme.titleMedium),
                        Chip(label: Text(branch.isActive ? 'Active' : 'Inactive')),
                      ],
                    ),
                    if (branch.phone != null) Text('Phone: ${branch.phone}'),
                    if (branch.email != null) Text('Email: ${branch.email}'),
                    if (!branch.address.isEmpty) Text('Address: ${branch.address.singleLine}'),
                    Text('Timezone: ${branch.timezone}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Working hours'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/owner/branches/$branchId/working-hours'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_busy),
                title: const Text('Holidays'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/owner/branches/$branchId/holidays'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
