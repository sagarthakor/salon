/// Mirrors `App\Http\Controllers\Api\V1\DashboardController::summary` —
/// `GET /dashboard/summary` (Phase 8). Every field is a real, server-computed
/// value; see OWNER_APP_ARCHITECTURE.md for exactly how each is derived.
class DashboardSummary {
  const DashboardSummary({
    required this.date,
    required this.bookingCounts,
    required this.revenueToday,
    this.nextAppointment,
    required this.activeStaff,
    required this.staffOnLeaveToday,
    required this.totalCustomers,
    required this.newCustomersThisMonth,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) => DashboardSummary(
    date: json['date'] as String,
    bookingCounts: Map<String, int>.from(json['bookings'] as Map),
    revenueToday: num.parse(json['revenue_today'].toString()),
    nextAppointment: json['next_appointment'] != null
        ? NextAppointment.fromJson(json['next_appointment'] as Map<String, dynamic>)
        : null,
    activeStaff: (json['staff'] as Map)['active'] as int,
    staffOnLeaveToday: (json['staff'] as Map)['on_leave_today'] as int,
    totalCustomers: (json['customers'] as Map)['total'] as int,
    newCustomersThisMonth: (json['customers'] as Map)['new_this_month'] as int,
  );

  final String date;
  final Map<String, int> bookingCounts;
  final num revenueToday;
  final NextAppointment? nextAppointment;
  final int activeStaff;
  final int staffOnLeaveToday;
  final int totalCustomers;
  final int newCustomersThisMonth;

  int countFor(String status) => bookingCounts[status] ?? 0;

  int get totalBookingsToday => bookingCounts['total'] ?? 0;
}

class NextAppointment {
  const NextAppointment({
    required this.id,
    required this.bookingDate,
    required this.startTime,
    required this.status,
    this.customerName,
  });

  factory NextAppointment.fromJson(Map<String, dynamic> json) => NextAppointment(
    id: json['id'] as String,
    bookingDate: json['booking_date'] as String,
    startTime: json['start_time'] as String,
    status: json['status'] as String,
    customerName: json['customer_name'] as String?,
  );

  final String id;
  final String bookingDate;
  final String startTime;
  final String status;
  final String? customerName;
}
