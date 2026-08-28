import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/subscription_repository.dart';
import 'billing_providers.dart';

const _perPage = 20;

class PaymentHistoryState {
  const PaymentHistoryState({
    this.payments = const [],
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<Payment> payments;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  PaymentHistoryState copyWith({
    List<Payment>? payments,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return PaymentHistoryState(
      payments: payments ?? this.payments,
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Same "did the last page come back full" load-more heuristic as every
/// other paginated list in this app (see MOBILE_API_INTEGRATION.md).
class PaymentHistoryController extends StateNotifier<PaymentHistoryState> {
  PaymentHistoryController(this._repository) : super(const PaymentHistoryState()) {
    loadFirstPage();
  }

  final SubscriptionRepository _repository;
  int _page = 1;

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final payments = await _repository.payments(page: _page, perPage: _perPage);
      state = PaymentHistoryState(payments: payments, isLoadingFirstPage: false, hasMore: payments.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await _repository.payments(page: _page + 1, perPage: _perPage);
      _page += 1;
      state = state.copyWith(payments: [...state.payments, ...next], isLoadingMore: false, hasMore: next.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.message);
    }
  }
}

final paymentHistoryControllerProvider = StateNotifierProvider.autoDispose<PaymentHistoryController, PaymentHistoryState>((ref) {
  return PaymentHistoryController(ref.watch(subscriptionRepositoryProvider));
});
