/// `Y-m-d` formatting matching exactly what the Laravel API expects/returns
/// for `date`/`booking_date` fields — deliberately not using `package:intl`'s
/// locale-aware formatting here, since this value is a wire format, not
/// user-facing display text.
String toApiDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime parseApiDate(String value) {
  final parts = value.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', // fixed-width, no locale dependency
];

/// A short human-readable date from an ISO-8601 timestamp (as returned by
/// the billing endpoints' `*_at` fields), e.g. `2026-08-24T11:50:18+00:00`
/// -> `24 Aug 2026`. Deliberately not `package:intl` — see [toApiDate].
String toDisplayDate(String isoString) {
  final date = DateTime.parse(isoString).toLocal();
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}
