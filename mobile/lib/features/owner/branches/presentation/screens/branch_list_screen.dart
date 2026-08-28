import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../salon/data/models/branch.dart';
import '../providers/owner_branch_providers.dart';

class BranchListScreen extends ConsumerWidget {
  const BranchListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(ownerBranchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Branches')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/owner/branches/new'),
        child: const Icon(Icons.add),
      ),
      body: branchesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load branches.',
          onRetry: () => ref.invalidate(ownerBranchesProvider),
        ),
        data: (branches) {
          if (branches.isEmpty) {
            return const EmptyView(icon: Icons.storefront_outlined, message: 'No branches yet. Tap + to add one.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ownerBranchesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: branches.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _BranchTile(branch: branches[index]),
            ),
          );
        },
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.storefront),
        title: Text(branch.name),
        subtitle: branch.address.isEmpty ? null : Text(branch.address.singleLine),
        trailing: Chip(label: Text(branch.isActive ? 'Active' : 'Inactive')),
        onTap: () => context.push('/owner/branches/${branch.id}'),
      ),
    );
  }
}
