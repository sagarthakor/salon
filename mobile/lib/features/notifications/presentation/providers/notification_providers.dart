import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/app_notification.dart';
import '../../data/repositories/device_token_repository.dart';
import '../../data/repositories/notification_preference_repository.dart';
import '../../data/repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(apiClientProvider)),
);

final notificationPreferenceRepositoryProvider = Provider<NotificationPreferenceRepository>(
  (ref) => NotificationPreferenceRepository(ref.watch(apiClientProvider)),
);

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>(
  (ref) => DeviceTokenRepository(ref.watch(apiClientProvider)),
);

/// Re-fetch with `ref.invalidate(unreadNotificationCountProvider)` after any
/// action that could change it (mark read, mark all read, a new notification
/// arriving) — there is no push-driven live update in this phase.
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(notificationRepositoryProvider).unreadCount();
});

const _perPage = 20;

class NotificationListState {
  const NotificationListState({
    this.notifications = const [],
    this.isLoadingFirstPage = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<AppNotification> notifications;
  final bool isLoadingFirstPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  NotificationListState copyWith({
    List<AppNotification>? notifications,
    bool? isLoadingFirstPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return NotificationListState(
      notifications: notifications ?? this.notifications,
      isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationListController extends StateNotifier<NotificationListState> {
  NotificationListController(this._ref, this._repository) : super(const NotificationListState()) {
    loadFirstPage();
  }

  final Ref _ref;
  final NotificationRepository _repository;
  int _page = 1;

  Future<void> loadFirstPage() async {
    _page = 1;
    state = state.copyWith(isLoadingFirstPage: true, clearError: true);
    try {
      final notifications = await _repository.list(page: _page, perPage: _perPage);
      state = state.copyWith(notifications: notifications, isLoadingFirstPage: false, hasMore: notifications.length == _perPage);
    } on Object catch (e) {
      state = state.copyWith(isLoadingFirstPage: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = await _repository.list(page: _page + 1, perPage: _perPage);
      _page += 1;
      state = state.copyWith(notifications: [...state.notifications, ...next], isLoadingMore: false, hasMore: next.length == _perPage);
    } on Object catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  Future<void> markRead(String id) async {
    final updated = await _repository.markRead(id);
    state = state.copyWith(notifications: [for (final n in state.notifications) n.id == id ? updated : n]);
    _ref.invalidate(unreadNotificationCountProvider);
  }

  Future<void> markAllRead() async {
    await _repository.markAllRead();
    state = state.copyWith(notifications: [for (final n in state.notifications) n.copyWith(isRead: true)]);
    _ref.invalidate(unreadNotificationCountProvider);
  }
}

final notificationListControllerProvider =
    StateNotifierProvider.autoDispose<NotificationListController, NotificationListState>((ref) {
      return NotificationListController(ref, ref.watch(notificationRepositoryProvider));
    });
