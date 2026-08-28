import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/booking/data/models/availability.dart';

void main() {
  group('AvailabilityResult.fromJson', () {
    test('parses slots and the additive staff-name list together', () {
      final json = {
        'date': '2026-09-01',
        'duration_minutes': 30,
        'buffer_minutes': 0,
        'slots': [
          {'start_time': '09:00', 'end_time': '09:30', 'staff_ids': ['st_1', 'st_2']},
          {'start_time': '09:15', 'end_time': '09:45', 'staff_ids': ['st_2']},
        ],
        'staff': [
          {'id': 'st_1', 'name': 'Amit'},
          {'id': 'st_2', 'name': 'Priya'},
        ],
      };

      final result = AvailabilityResult.fromJson(json);

      expect(result.slots, hasLength(2));
      expect(result.slots.first.staffIds, ['st_1', 'st_2']);
      expect(result.staffNameFor('st_1'), 'Amit');
      expect(result.staffNameFor('st_2'), 'Priya');
      expect(result.staffNameFor('unknown'), isNull);
    });

    test('handles an empty-slots response (branch closed / holiday / no eligible staff)', () {
      final json = {
        'date': '2026-09-01',
        'duration_minutes': 30,
        'buffer_minutes': 0,
        'slots': <dynamic>[],
        'staff': <dynamic>[],
      };

      final result = AvailabilityResult.fromJson(json);

      expect(result.slots, isEmpty);
      expect(result.staff, isEmpty);
    });

    test('tolerates a missing staff key for backward compatibility', () {
      final json = {
        'date': '2026-09-01',
        'duration_minutes': 30,
        'buffer_minutes': 0,
        'slots': <dynamic>[],
      };

      final result = AvailabilityResult.fromJson(json);

      expect(result.staff, isEmpty);
    });
  });
}
