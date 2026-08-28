import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../data/models/invoice.dart';
import '../../data/repositories/subscription_repository.dart';
import 'billing_providers.dart';

const _perPage = 20;

class InvoiceHistoryState {
  const InvoiceHistoryState({
    this.invoices = const [],
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<Invoice> invoices;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  InvoiceHistoryState copyWith({
    List<Invoice>? invoices,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return InvoiceHistoryState(
      invoices: invoices ?? this.invoices,
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class InvoiceHistoryController extends StateNotifier<InvoiceHistoryState> {
  InvoiceHistoryController(this._repository) : super(const InvoiceHistoryState()) {
    loadFirstPage();
  }

  final SubscriptionRepository _repository;
  int _page = 1;

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final invoices = await _repository.invoices(page: _page, perPage: _perPage);
      state = InvoiceHistoryState(invoices: invoices, isLoadingFirstPage: false, hasMore: invoices.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await _repository.invoices(page: _page + 1, perPage: _perPage);
      _page += 1;
      state = state.copyWith(invoices: [...state.invoices, ...next], isLoadingMore: false, hasMore: next.length == _perPage);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.message);
    }
  }
}

final invoiceHistoryControllerProvider = StateNotifierProvider.autoDispose<InvoiceHistoryController, InvoiceHistoryState>((ref) {
  return InvoiceHistoryController(ref.watch(subscriptionRepositoryProvider));
});
