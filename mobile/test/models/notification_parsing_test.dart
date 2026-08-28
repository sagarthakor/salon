import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/notifications/data/models/app_notification.dart';
import 'package:salon_customer/features/notifications/data/models/notification_preference.dart';

void main() {
  group('AppNotification.fromJson', () {
    test('parses a booking notification with its typed deep-link payload', () {
      final notification = AppNotification.fromJson({
        'id': 'ntf_1',
        'type': 'booking.confirmed',
        'title': 'Booking confirmed',
        'body': 'Your booking at Salon A on 2026-09-01 at 09:00 is confirmed.',
        'data': {'deep_link': 'booking', 'booking_id': 'bk_1'},
        'is_read': false,
        'read_at': null,
        'created_at': '2026-08-27T10:00:00+00:00',
      });

      expect(notification.id, 'ntf_1');
      expect(notification.type, 'booking.confirmed');
      expect(notification.isRead, false);
      expect(notification.readAt, isNull);
      expect(notification.deepLink, 'booking');
      expect(notification.bookingId, 'bk_1');
    });

    test('deepLink/bookingId are null when data has no deep-link payload (e.g. a subscription notification)', () {
      final notification = AppNotification.fromJson({
        'id': 'ntf_2',
        'type': 'subscription.expired',
        'title': 'Subscription expired',
        'body': 'Your subscription has expired.',
        'data': {'deep_link': 'subscription'},
        'is_read': true,
        'read_at': '2026-08-27T11:00:00+00:00',
        'created_at': '2026-08-27T10:00:00+00:00',
      });

      expect(notification.deepLink, 'subscription');
      expect(notification.bookingId, isNull);
      expect(notification.isRead, true);
    });

    test('copyWith(isRead: true) marks read without mutating the original', () {
      final original = AppNotification.fromJson({
        'id': 'ntf_3',
        'type': 'booking.created',
        'title': 'Booking received',
        'body': 'body',
        'data': {},
        'is_read': false,
        'read_at': null,
        'created_at': '2026-08-27T10:00:00+00:00',
      });

      final read = original.copyWith(isRead: true, readAt: '2026-08-27T12:00:00+00:00');

      expect(original.isRead, false);
      expect(read.isRead, true);
      expect(read.readAt, '2026-08-27T12:00:00+00:00');
    });
  });

  group('NotificationPreferenceRow', () {
    test('fromJson parses the matrix row shape', () {
      final row = NotificationPreferenceRow.fromJson({
        'event_type': 'booking.cancelled',
        'channel': 'email',
        'enabled': false,
        'is_override': true,
      });

      expect(row.eventType, 'booking.cancelled');
      expect(row.channel, 'email');
      expect(row.enabled, false);
      expect(row.isOverride, true);
    });

    test('copyWith(enabled:) always marks the row as an override', () {
      const row = NotificationPreferenceRow(eventType: 'booking.created', channel: 'push', enabled: true, isOverride: false);

      final toggled = row.copyWith(enabled: false);

      expect(toggled.enabled, false);
      expect(toggled.isOverride, true);
    });
  });
}
