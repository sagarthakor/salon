import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_status.dart';

void main() {
  group('Booking.fromJson', () {
    test('parses a full booking with items and status history (the show-endpoint shape)', () {
      final json = {
        'id': 'bk_1',
        'branch_id': 'br_1',
        'customer': {
          'id': 'cu_1',
          'user_id': 3,
          'name': 'Rahul',
          'phone': '9876543210',
          'status': 'active',
        },
        'booking_date': '2026-09-01',
        'start_time': '09:00',
        'end_time': '09:30',
        'status': 'pending',
        'subtotal': '300.00',
        'discount': '0.00',
        'tax': '0.00',
        'total': '300.00',
        'notes': null,
        'cancellation_reason': null,
        'cancelled_at': null,
        'items': [
          {
            'id': 1,
            'service_id': 'sv_1',
            'staff_id': 'st_1',
            'staff_name': 'Amit',
            'service_name': 'Haircut',
            'service_price': '300.00',
            'service_duration_minutes': 30,
            'quantity': 1,
            'start_time': '09:00',
            'end_time': '09:30',
            'subtotal': '300.00',
          },
        ],
        'status_history': [
          {'id': 1, 'from_status': null, 'to_status': 'pending', 'changed_by': null, 'reason': null, 'created_at': '2026-08-24T10:00:00Z'},
        ],
      };

      final booking = Booking.fromJson(json);

      expect(booking.id, 'bk_1');
      expect(booking.status, BookingStatus.pending);
      expect(booking.total, 300);
      expect(booking.customer?.name, 'Rahul');
      expect(booking.items, hasLength(1));
      expect(booking.items.first.staffName, 'Amit');
      expect(booking.items.first.servicePrice, 300);
      expect(booking.statusHistory, hasLength(1));
      expect(booking.statusHistory.first.toStatus, BookingStatus.pending);
      expect(booking.statusHistory.first.fromStatus, isNull);
    });

    test('parses a list-endpoint booking with no items/customer/history present', () {
      final json = {
        'id': 'bk_2',
        'branch_id': 'br_1',
        'booking_date': '2026-09-01',
        'start_time': '10:00',
        'end_time': '10:30',
        'status': 'confirmed',
        'subtotal': '500.00',
        'discount': '0.00',
        'tax': '0.00',
        'total': '500.00',
      };

      final booking = Booking.fromJson(json);

      expect(booking.status, BookingStatus.confirmed);
      expect(booking.customer, isNull);
      expect(booking.items, isEmpty);
      expect(booking.statusHistory, isEmpty);
    });
  });

  group('BookingStatus', () {
    test('fromApi maps every backend value', () {
      expect(BookingStatus.fromApi('pending'), BookingStatus.pending);
      expect(BookingStatus.fromApi('confirmed'), BookingStatus.confirmed);
      expect(BookingStatus.fromApi('checked_in'), BookingStatus.checkedIn);
      expect(BookingStatus.fromApi('in_service'), BookingStatus.inService);
      expect(BookingStatus.fromApi('completed'), BookingStatus.completed);
      expect(BookingStatus.fromApi('cancelled'), BookingStatus.cancelled);
      expect(BookingStatus.fromApi('no_show'), BookingStatus.noShow);
    });

    test('an unknown value throws rather than silently defaulting', () {
      expect(() => BookingStatus.fromApi('bogus'), throwsArgumentError);
    });

    test('isUpcoming / isActive / isTerminal partition the statuses correctly', () {
      expect(BookingStatus.pending.isUpcoming, isTrue);
      expect(BookingStatus.confirmed.isUpcoming, isTrue);
      expect(BookingStatus.checkedIn.isUpcoming, isFalse);
      expect(BookingStatus.checkedIn.isActive, isTrue);
      expect(BookingStatus.completed.isTerminal, isTrue);
      expect(BookingStatus.cancelled.isTerminal, isTrue);
      expect(BookingStatus.noShow.isTerminal, isTrue);
      expect(BookingStatus.pending.isTerminal, isFalse);
    });
  });
}
