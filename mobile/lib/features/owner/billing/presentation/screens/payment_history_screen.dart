import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../core/utils/money_format.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/payment.dart';
import '../providers/payment_history_controller.dart';

/// Date, amount, currency, status, and payment reference only — never a
/// gateway secret (see `PaymentResource`).
class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(paymentHistoryControllerProvider);
    final controller = ref.read(paymentHistoryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Payment history')),
      body: Builder(
        builder: (context) {
          if (state.isLoadingFirstPage) return const LoadingView();
          if (state.error != null && state.payments.isEmpty) {
            return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
          }
          if (state.payments.isEmpty) {
            return const EmptyView(icon: Icons.receipt_long_outlined, message: 'No payments yet.');
          }
          return RefreshIndicator(
            onRefresh: controller.loadFirstPage,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (state.hasMore && !state.isLoadingMore && notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                  controller.loadMore();
                }
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: state.payments.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index >= state.payments.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _PaymentTile(payment: state.payments[index]);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('${payment.currency} ${formatMoney(payment.amount)}'),
        subtitle: Text(payment.createdAt != null ? toDisplayDate(payment.createdAt!) : payment.status),
        trailing: Chip(label: Text(payment.status)),
      ),
    );
  }
}
