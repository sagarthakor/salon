import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../providers/owner_pricing_providers.dart';

class LoyaltySearchScreen extends ConsumerStatefulWidget {
  const LoyaltySearchScreen({super.key});

  @override
  ConsumerState<LoyaltySearchScreen> createState() => _LoyaltySearchScreenState();
}

class _LoyaltySearchScreenState extends ConsumerState<LoyaltySearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(loyaltySearchProvider(_query));

    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(labelText: 'Search by customer name or phone', prefixIcon: Icon(Icons.search)),
              onSubmitted: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: resultsAsync.when(
              loading: () => const LoadingView(),
              error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load loyalty accounts.'),
              data: (results) {
                if (results.isEmpty) {
                  return const EmptyView(icon: Icons.stars_outlined, message: 'No customers with a loyalty balance found.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return Card(
                      child: ListTile(
                        title: Text(result.customer?.name ?? 'Customer'),
                        subtitle: Text('${result.account.balance} points'),
                        onTap: result.customer != null ? () => context.push('/owner/loyalty/${result.customer!.id}') : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
