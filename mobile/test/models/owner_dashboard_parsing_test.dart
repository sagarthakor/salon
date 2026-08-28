import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/owner/dashboard/data/models/dashboard_summary.dart';

void main() {
  group('DashboardSummary.fromJson', () {
    test('parses every real, server-computed field including a next appointment', () {
      final summary = DashboardSummary.fromJson({
        'date': '2026-08-23',
        'bookings': {'total': 5, 'pending': 1, 'confirmed': 2, 'in_service': 1, 'completed': 1, 'cancelled': 0},
        'revenue_today': '1250.50',
        'next_appointment': {
          'id': 'bk-1',
          'booking_date': '2026-08-23',
          'start_time': '14:30',
          'status': 'confirmed',
          'customer_name': 'Rahul Sharma',
        },
        'staff': {'active': 4, 'on_leave_today': 1},
        'customers': {'total': 120, 'new_this_month': 8},
      });

      expect(summary.date, '2026-08-23');
      expect(summary.totalBookingsToday, 5);
      expect(summary.countFor('confirmed'), 2);
      expect(summary.countFor('no_show'), 0, reason: 'a status absent from the payload must default to zero, not throw');
      expect(summary.revenueToday, 1250.50);
      expect(summary.activeStaff, 4);
      expect(summary.staffOnLeaveToday, 1);
      expect(summary.totalCustomers, 120);
      expect(summary.newCustomersThisMonth, 8);
      expect(summary.nextAppointment, isNotNull);
      expect(summary.nextAppointment!.customerName, 'Rahul Sharma');
      expect(summary.nextAppointment!.startTime, '14:30');
    });

    test('parses a day with no upcoming appointment as null, not a fabricated placeholder', () {
      final summary = DashboardSummary.fromJson({
        'date': '2026-08-23',
        'bookings': {'total': 0},
        'revenue_today': 0,
        'next_appointment': null,
        'staff': {'active': 0, 'on_leave_today': 0},
        'customers': {'total': 0, 'new_this_month': 0},
      });

      expect(summary.nextAppointment, isNull);
      expect(summary.totalBookingsToday, 0);
      expect(summary.revenueToday, 0);
    });
  });

  group('NextAppointment.fromJson', () {
    test('customer_name is optional (walk-in / unnamed booking)', () {
      final appointment = NextAppointment.fromJson({
        'id': 'bk-2',
        'booking_date': '2026-08-24',
        'start_time': '09:00',
        'status': 'pending',
      });

      expect(appointment.customerName, isNull);
      expect(appointment.status, 'pending');
    });
  });
}
