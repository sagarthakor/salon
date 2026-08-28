/// Day-of-week labels matching the backend's convention — `0 = Sunday` … `6 =
/// Saturday`, i.e. Carbon/PHP's `dayOfWeek`, adopted explicitly for the
/// booking engine in Phase 6 (see BOOKING_ENGINE.md) and reused by every
/// day-indexed schedule (branch hours, staff hours, staff breaks).
const List<String> dayOfWeekLabels = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

String dayOfWeekLabel(int day) => dayOfWeekLabels[day];
