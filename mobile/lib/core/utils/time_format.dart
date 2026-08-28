/// Converts a `HH:mm` wire-format time (as returned by the availability and
/// booking APIs) into a friendly 12-hour display string, e.g. `09:00` → `9:00 AM`.
String toDisplayTime(String hhmm) {
  final parts = hhmm.split(':');
  final hour24 = int.parse(parts[0]);
  final minute = parts[1];
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:$minute $period';
}
