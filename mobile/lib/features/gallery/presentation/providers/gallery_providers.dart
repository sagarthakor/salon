import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/providers.dart';
import '../../data/models/gallery_item.dart';
import '../../data/repositories/gallery_repository.dart';

const galleryPageSize = 12;

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) => GalleryRepository(ref.watch(apiClientProvider)));

class GalleryListState {
  const GalleryListState({
    this.items = const [],
    this.category,
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.loadMoreError,
  });

  final List<GalleryItem> items;
  final String? category;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;

  /// Set only when the first page failed (full-screen error + retry).
  final String? error;

  /// Set when a later page failed; the already-loaded grid stays visible.
  final String? loadMoreError;

  GalleryListState copyWith({
    List<GalleryItem>? items,
    String? category,
    bool clearCategory = false,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return GalleryListState(
      items: items ?? this.items,
      category: clearCategory ? null : (category ?? this.category),
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      loadMoreError: clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// Incremental loading of one branch's gallery. Mirrors the pagination
/// convention used elsewhere in the app (`hasMore` = a full page came back).
class GalleryListController extends StateNotifier<GalleryListState> {
  GalleryListController(this._repository, this.branchId) : super(const GalleryListState()) {
    loadFirstPage();
  }

  final GalleryRepository _repository;
  final String branchId;
  int _page = 1;
  int _generation = 0;

  Future<void> setCategory(String? category) async {
    state = state.copyWith(category: category, clearCategory: category == null);
    await loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    final generation = ++_generation;
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, items: const [], clearError: true, clearLoadMoreError: true, hasMore: true);
    try {
      final items = await _repository.list(branchId, page: 1, perPage: galleryPageSize, category: state.category);
      if (generation != _generation || !mounted) return;
      state = state.copyWith(items: items, isLoadingFirstPage: false, hasMore: items.length == galleryPageSize);
    } on ApiException catch (e) {
      if (generation != _generation || !mounted) return;
      state = state.copyWith(isLoadingFirstPage: false, error: e.message);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingFirstPage || state.isLoadingMore || !state.hasMore || state.error != null) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    try {
      final next = await _repository.list(branchId, page: _page + 1, perPage: galleryPageSize, category: state.category);
      if (generation != _generation || !mounted) return;
      _page += 1;
      state = state.copyWith(items: [...state.items, ...next], isLoadingMore: false, hasMore: next.length == galleryPageSize);
    } on ApiException catch (e) {
      if (generation != _generation || !mounted) return;
      state = state.copyWith(isLoadingMore: false, loadMoreError: e.message);
    }
  }
}

final galleryListControllerProvider = StateNotifierProvider.autoDispose.family<GalleryListController, GalleryListState, String>((
  ref,
  branchId,
) {
  return GalleryListController(ref.watch(galleryRepositoryProvider), branchId);
});
