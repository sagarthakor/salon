import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/providers.dart';
import '../../../../gallery/data/models/gallery_item.dart';
import '../../data/repositories/owner_gallery_repository.dart';

final ownerGalleryRepositoryProvider = Provider<OwnerGalleryRepository>(
  (ref) => OwnerGalleryRepository(ref.watch(apiClientProvider)),
);

final instagramConnectionProvider = FutureProvider.autoDispose<InstagramConnectionStatus>((ref) {
  return ref.watch(ownerGalleryRepositoryProvider).instagramStatus();
});

final ownerGalleryItemProvider = FutureProvider.autoDispose.family<GalleryItem, String>((ref, id) {
  return ref.watch(ownerGalleryRepositoryProvider).details(id);
});

class OwnerGalleryState {
  const OwnerGalleryState({this.items = const [], this.isLoading = true, this.error});

  final List<GalleryItem> items;
  final bool isLoading;
  final String? error;
}

/// Loads the owner's whole gallery (galleries are small and drag-reordering
/// needs every item, so this pages through until exhausted, capped at the
/// reorder endpoint's 500-item limit).
class OwnerGalleryController extends StateNotifier<OwnerGalleryState> {
  OwnerGalleryController(this._repository) : super(const OwnerGalleryState()) {
    load();
  }

  final OwnerGalleryRepository _repository;
  static const _perPage = 100;
  static const _maxPages = 5;

  Future<void> load() async {
    state = OwnerGalleryState(items: state.items, isLoading: true);
    try {
      final all = <GalleryItem>[];
      for (var page = 1; page <= _maxPages; page++) {
        final batch = await _repository.list(page: page, perPage: _perPage);
        all.addAll(batch);
        if (batch.length < _perPage) break;
      }
      if (!mounted) return;
      state = OwnerGalleryState(items: all, isLoading: false);
    } on ApiException catch (e) {
      if (!mounted) return;
      state = OwnerGalleryState(items: state.items, isLoading: false, error: e.message);
    }
  }

  /// Returns an error message, or null on success.
  Future<String?> setActive(GalleryItem item, bool active) async {
    try {
      final updated = await _repository.update(item.id, isActive: active);
      state = OwnerGalleryState(items: [for (final i in state.items) i.id == item.id ? updated : i], isLoading: false);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> delete(GalleryItem item) async {
    try {
      await _repository.delete(item.id);
      state = OwnerGalleryState(items: state.items.where((i) => i.id != item.id).toList(), isLoading: false);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Optimistically reorders, rolling back if the server rejects it.
  Future<String?> move(int oldIndex, int newIndex) async {
    final previous = state.items;
    final items = List<GalleryItem>.of(previous);
    items.insert(newIndex, items.removeAt(oldIndex));
    state = OwnerGalleryState(items: items, isLoading: false);
    try {
      await _repository.reorder(items.map((i) => i.id).toList());
      return null;
    } on ApiException catch (e) {
      state = OwnerGalleryState(items: previous, isLoading: false);
      return e.message;
    }
  }
}

final ownerGalleryControllerProvider = StateNotifierProvider.autoDispose<OwnerGalleryController, OwnerGalleryState>((ref) {
  return OwnerGalleryController(ref.watch(ownerGalleryRepositoryProvider));
});
