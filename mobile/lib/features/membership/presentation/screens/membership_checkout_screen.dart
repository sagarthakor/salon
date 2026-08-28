import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/models/membership_checkout_order.dart';
import '../membership_gateway_checkout_launcher.dart';
import '../providers/membership_providers.dart';

/// Same server-authoritative pattern as `PaymentCheckoutScreen` (Phase 10):
/// open the gateway's own checkout UI, then only ever trust
/// `GET /customer/membership` (never a client-side "it worked" signal) —
/// see PaymentWebhookController for how that becomes true.
class MembershipCheckoutScreen extends ConsumerStatefulWidget {
  const MembershipCheckoutScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<MembershipCheckoutScreen> createState() => _MembershipCheckoutScreenState();
}

class _MembershipCheckoutScreenState extends ConsumerState<MembershipCheckoutScreen> with WidgetsBindingObserver {
  late Future<MembershipCheckoutOrder> _orderFuture;
  bool _isCheckingStatus = false;
  bool _hasOpenedGateway = false;
  String? _statusMessage;
  bool? _confirmed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _orderFuture = ref.read(customerMembershipRepositoryProvider).checkout(widget.planId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasOpenedGateway && _confirmed != true) {
      _checkStatus();
    }
  }

  Future<void> _openGateway(MembershipCheckoutOrder order) async {
    _hasOpenedGateway = true;
    final opened = await openMembershipGatewayCheckout(order);
    if (!opened && mounted) {
      setState(() => _statusMessage = 'Could not open the payment page. Please try again.');
    }
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isCheckingStatus = true;
      _statusMessage = null;
    });
    try {
      final membership = await ref.read(customerMembershipRepositoryProvider).current();
      ref.invalidate(currentMembershipProvider);
      if (membership != null && membership.isCurrentlyActive) {
        setState(() {
          _confirmed = true;
          _isCheckingStatus = false;
        });
        return;
      }
      setState(() {
        _isCheckingStatus = false;
        _statusMessage = "We haven't received confirmation yet. If you completed the payment, please wait a moment and check again.";
      });
    } on ApiException catch (e) {
      setState(() {
        _isCheckingStatus = false;
        _statusMessage = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed == true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Membership active')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: AppSpacing.md),
                const Text('Your membership is now active.', textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(label: 'Done', onPressed: () => context.go('/membership')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Complete payment')),
      body: FutureBuilder<MembershipCheckoutOrder>(
        future: _orderFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return ErrorView(message: error is ApiException ? error.message : 'Could not start checkout.');
          }
          final order = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.planName, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text('${order.currency} ${formatMoney(order.amount)}', style: Theme.of(context).textTheme.headlineSmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Pay with Razorpay', onPressed: () => _openGateway(order)),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: _isCheckingStatus ? null : _checkStatus,
                child: _isCheckingStatus
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("I've completed the payment"),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_statusMessage!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          );
        },
      ),
    );
  }
}
