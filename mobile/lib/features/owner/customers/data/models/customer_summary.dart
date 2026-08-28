/// Mirrors the `summary` object inside `GET /customers/{customer}/summary`
/// (real, booking-derived data as of Phase 8 — see CUSTOMER_ARCHITECTURE.md
/// and OWNER_APP_ARCHITECTURE.md for how each field is computed).
class CustomerSummary {
  const CustomerSummary({
    required this.totalVisits,
    required this.completedAppointments,
    required this.cancelledAppointments,
    required this.noShowCount,
    required this.totalSpent,
    this.lastVisitAt,
    this.upcomingAppointment,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> json) => CustomerSummary(
    totalVisits: json['total_visits'] as int,
    completedAppointments: json['completed_appointments'] as int,
    cancelledAppointments: json['cancelled_appointments'] as int,
    noShowCount: json['no_show_count'] as int,
    totalSpent: num.parse(json['total_spent'].toString()),
    lastVisitAt: json['last_visit_at'] as String?,
    upcomingAppointment: json['upcoming_appointment'] != null
        ? UpcomingAppointmentSummary.fromJson(json['upcoming_appointment'] as Map<String, dynamic>)
        : null,
  );

  final int totalVisits;
  final int completedAppointments;
  final int cancelledAppointments;
  final int noShowCount;
  final num totalSpent;
  final String? lastVisitAt;
  final UpcomingAppointmentSummary? upcomingAppointment;
}

class UpcomingAppointmentSummary {
  const UpcomingAppointmentSummary({required this.id, required this.bookingDate, required this.startTime, required this.status});

  factory UpcomingAppointmentSummary.fromJson(Map<String, dynamic> json) => UpcomingAppointmentSummary(
    id: json['id'] as String,
    bookingDate: json['booking_date'] as String,
    startTime: json['start_time'] as String,
    status: json['status'] as String,
  );

  final String id;
  final String bookingDate;
  final String startTime;
  final String status;
}
