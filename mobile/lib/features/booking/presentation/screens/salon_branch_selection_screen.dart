import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../salon/data/models/branch.dart';
import '../../../salon/presentation/providers/salon_providers.dart';

/// Step between picking a salon (the Customer Dashboard's discovery list)
/// and the existing, unchanged audience-selection screen — shows only that
/// salon's active branches, resolved entirely server-side from the salon id
/// (never a client-supplied tenant). See CUSTOMER_ARCHITECTURE.md, "Customer
/// discovery and first-time booking".
class SalonBranchSelectionScreen extends ConsumerStatefulWidget {
  const SalonBranchSelectionScreen({super.key, required this.salonId, this.salonName});

  final String salonId;
  final String? salonName;

  @override
  ConsumerState<SalonBranchSelectionScreen> createState() => _SalonBranchSelectionScreenState();
}

class _SalonBranchSelectionScreenState extends ConsumerState<SalonBranchSelectionScreen> {
  bool _autoSelected = false;

  void _selectBranch(Branch branch) {
    ref.read(selectedBranchProvider.notifier).state = branch;
    // "What service are you looking for?" — Men/Women/Unisex/Kids — comes
    // next, exactly as it already does from the Customer Dashboard.
    context.push('/booking/audience');
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(salonBranchesProvider(widget.salonId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.salonName ?? 'Select a branch')),
      body: branchesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: 'Could not load branches.',
          onRetry: () => ref.invalidate(salonBranchesProvider(widget.salonId)),
        ),
        data: (branches) {
          if (branches.isEmpty) {
            return const EmptyView(icon: Icons.storefront_outlined, message: 'This salon has no active branches right now.');
          }
          // A single-branch salon skips straight to audience selection —
          // there's nothing for the customer to actually choose here.
          if (branches.length == 1 && !_autoSelected) {
            _autoSelected = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _selectBranch(branches.first);
            });
            return const LoadingView();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: branches.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final branch = branches[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Text(branch.name),
                  subtitle: branch.address.isEmpty ? null : Text(branch.address.singleLine),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _selectBranch(branch),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
