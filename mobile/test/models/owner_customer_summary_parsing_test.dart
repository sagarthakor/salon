import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/owner/customers/data/models/customer_note_entry.dart';
import 'package:salon_customer/features/owner/customers/data/models/customer_summary.dart';

void main() {
  group('CustomerSummary.fromJson', () {
    test('parses real booking-derived totals (Phase 8 fix — never placeholder zeros)', () {
      final summary = CustomerSummary.fromJson({
        'total_visits': 6,
        'completed_appointments': 5,
        'cancelled_appointments': 1,
        'no_show_count': 0,
        'total_spent': '4599.00',
        'last_visit_at': '2026-08-01T10:00:00Z',
        'upcoming_appointment': {'id': 'bk-9', 'booking_date': '2026-08-30', 'start_time': '11:00', 'status': 'confirmed'},
      });

      expect(summary.totalVisits, 6);
      expect(summary.completedAppointments, 5);
      expect(summary.totalSpent, 4599.00);
      expect(summary.upcomingAppointment, isNotNull);
      expect(summary.upcomingAppointment!.status, 'confirmed');
    });

    test('a customer with no booking history parses to real, honest zeros', () {
      final summary = CustomerSummary.fromJson({
        'total_visits': 0,
        'completed_appointments': 0,
        'cancelled_appointments': 0,
        'no_show_count': 0,
        'total_spent': 0,
        'last_visit_at': null,
        'upcoming_appointment': null,
      });

      expect(summary.totalVisits, 0);
      expect(summary.lastVisitAt, isNull);
      expect(summary.upcomingAppointment, isNull);
    });
  });

  group('CustomerNoteEntry.fromJson', () {
    test('resolves the nested author name when present', () {
      final note = CustomerNoteEntry.fromJson({
        'id': 1,
        'body': 'Prefers evening slots.',
        'author': {'id': 2, 'name': 'Owner Admin'},
        'created_at': '2026-08-20T12:00:00Z',
      });

      expect(note.body, 'Prefers evening slots.');
      expect(note.authorName, 'Owner Admin');
    });

    test('author is optional', () {
      final note = CustomerNoteEntry.fromJson({'id': 2, 'body': 'No allergies on file.'});

      expect(note.authorName, isNull);
      expect(note.createdAt, isNull);
    });
  });
}
