import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/models/loyalty_transaction.dart';
import '../providers/loyalty_providers.dart';

/// Customer-facing loyalty balance + ledger. Every value here comes
/// straight from the backend's ledger — never recomputed client-side (see
/// "Loyalty ledger" in LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md).
class LoyaltyScreen extends ConsumerStatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  ConsumerState<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends ConsumerState<LoyaltyScreen> {
  List<LoyaltyTransactionEntry>? _transactions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final transactions = await ref.read(customerLoyaltyRepositoryProvider).transactions();
      if (mounted) setState(() => _transactions = transactions);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(loyaltyAccountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty points')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(loyaltyAccountProvider);
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            accountAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.md), child: LoadingView()),
              error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load your loyalty account.'),
              data: (account) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${account.balance} points', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Lifetime earned: ${account.lifetimeEarned} · Lifetime redeemed: ${account.lifetimeRedeemed}'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('History', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            if (_error == null && _transactions == null) const LoadingView(),
            if (_transactions != null && _transactions!.isEmpty)
              const EmptyView(icon: Icons.history, message: 'No loyalty activity yet.'),
            if (_transactions != null)
              ..._transactions!.map(
                (t) => Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: ListTile(
                    leading: Icon(t.points >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline),
                    title: Text(t.description ?? t.type),
                    subtitle: Text(t.createdAt.split('T').first),
                    trailing: Text('${t.points >= 0 ? '+' : ''}${t.points}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
