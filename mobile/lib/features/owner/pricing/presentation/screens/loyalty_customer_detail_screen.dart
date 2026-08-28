import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../loyalty/data/models/loyalty_account.dart';
import '../../../../loyalty/data/models/loyalty_transaction.dart';
import '../providers/owner_pricing_providers.dart';

/// Owner view of one customer's loyalty balance/history, with an authorized
/// manual adjustment action — every adjustment requires a reason and always
/// produces an auditable ledger row (see LoyaltyService::adjust(), never a
/// direct balance overwrite).
class LoyaltyCustomerDetailScreen extends ConsumerStatefulWidget {
  const LoyaltyCustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<LoyaltyCustomerDetailScreen> createState() => _LoyaltyCustomerDetailScreenState();
}

class _LoyaltyCustomerDetailScreenState extends ConsumerState<LoyaltyCustomerDetailScreen> {
  LoyaltyAccount? _account;
  List<LoyaltyTransactionEntry>? _transactions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = ref.read(ownerLoyaltyRepositoryProvider);
      final account = await repository.account(widget.customerId);
      final transactions = await repository.transactions(widget.customerId);
      if (mounted) {
        setState(() {
          _account = account;
          _transactions = transactions;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _showAdjustDialog() async {
    final pointsController = TextEditingController();
    final reasonController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Adjust balance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pointsController,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(labelText: 'Points (use a negative number to deduct)'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason')),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            PrimaryButton(
              label: 'Save',
              onPressed: () async {
                final points = int.tryParse(pointsController.text);
                if (points == null || points == 0 || reasonController.text.trim().isEmpty) {
                  setState(() => error = 'Enter a non-zero point value and a reason.');
                  return;
                }
                try {
                  await ref.read(ownerLoyaltyRepositoryProvider).adjust(widget.customerId, points: points, reason: reasonController.text.trim());
                  if (context.mounted) Navigator.of(context).pop();
                  await _load();
                } on ApiException catch (e) {
                  setState(() => error = e.message);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty account'),
        actions: [IconButton(icon: const Icon(Icons.edit), tooltip: 'Adjust balance', onPressed: _showAdjustDialog)],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _account == null
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_account!.balance} points', style: Theme.of(context).textTheme.headlineMedium),
                          Text('Lifetime earned: ${_account!.lifetimeEarned} · Lifetime redeemed: ${_account!.lifetimeRedeemed}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('History', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (_transactions!.isEmpty) const EmptyView(icon: Icons.history, message: 'No loyalty activity yet.'),
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
