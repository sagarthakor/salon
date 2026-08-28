import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/booking/data/models/booking_status.dart';

void main() {
  group('BookingStatus.apiValue', () {
    test('is the exact inverse of fromApi for every status', () {
      for (final status in BookingStatus.values) {
        expect(BookingStatus.fromApi(status.apiValue), status);
      }
    });
  });

  group('BookingStatus.nextActions', () {
    test('mirrors App\\Enums\\BookingStatus::canTransitionTo for every active status', () {
      expect(BookingStatus.pending.nextActions, [BookingStatus.confirmed, BookingStatus.cancelled]);
      expect(BookingStatus.confirmed.nextActions, [BookingStatus.checkedIn, BookingStatus.cancelled, BookingStatus.noShow]);
      expect(BookingStatus.checkedIn.nextActions, [BookingStatus.inService, BookingStatus.cancelled]);
      expect(BookingStatus.inService.nextActions, [BookingStatus.completed, BookingStatus.cancelled]);
    });

    test('terminal statuses offer no further actions', () {
      expect(BookingStatus.completed.nextActions, isEmpty);
      expect(BookingStatus.cancelled.nextActions, isEmpty);
      expect(BookingStatus.noShow.nextActions, isEmpty);
    });
  });

  group('isUpcoming / isActive / isTerminal', () {
    test('classify every status consistently with each other', () {
      for (final status in BookingStatus.values) {
        // isTerminal and isActive are mutually exclusive, and every status is one or the other.
        expect(status.isActive != status.isTerminal, isTrue, reason: '$status must be exactly one of active/terminal');
      }
      expect(BookingStatus.pending.isUpcoming, isTrue);
      expect(BookingStatus.confirmed.isUpcoming, isTrue);
      expect(BookingStatus.checkedIn.isUpcoming, isFalse);
    });
  });
}
