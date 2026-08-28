import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/date_format.dart';
import '../../../../../core/utils/money_format.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/invoice.dart';
import '../providers/invoice_history_controller.dart';

/// Invoice number, billing period, amount, status, issued/paid dates. No PDF
/// generation exists in this app yet — out of scope for this phase (Phase
/// 10 §38: "do not create an unrelated PDF subsystem unless genuinely
/// required").
class InvoiceHistoryScreen extends ConsumerWidget {
  const InvoiceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(invoiceHistoryControllerProvider);
    final controller = ref.read(invoiceHistoryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Invoice history')),
      body: Builder(
        builder: (context) {
          if (state.isLoadingFirstPage) return const LoadingView();
          if (state.error != null && state.invoices.isEmpty) {
            return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
          }
          if (state.invoices.isEmpty) {
            return const EmptyView(icon: Icons.description_outlined, message: 'No invoices yet.');
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
                itemCount: state.invoices.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index >= state.invoices.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _InvoiceTile(invoice: state.invoices[index]);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(invoice.invoiceNumber),
        subtitle: Text(invoice.issuedAt != null ? toDisplayDate(invoice.issuedAt!) : '${invoice.currency} ${formatMoney(invoice.total)}'),
        trailing: Chip(label: Text(invoice.status)),
      ),
    );
  }
}
