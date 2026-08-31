/// Curated list of common IANA timezone identifiers offered in the Salon and
/// Branch forms — not exhaustive, but broadly covers every populated region.
/// Backend validation (`SalonRequest`/`BranchRequest`) accepts any value
/// PHP's `timezone_identifiers_list()` recognizes, so this list is only a
/// convenience for picking a value in the UI, never an enforced allow-list.
///
/// A branch/salon's timezone is what AvailabilityService and BookingService
/// compare "now" against when deciding whether a same-day slot has already
/// passed — picking the wrong one here is a real customer-facing bug, not
/// just a display preference, so both the Salon and Branch forms require an
/// explicit choice rather than silently defaulting.
const List<String> kCommonTimezones = [
  'Asia/Kolkata',
  'Asia/Dhaka',
  'Asia/Karachi',
  'Asia/Colombo',
  'Asia/Kathmandu',
  'Asia/Dubai',
  'Asia/Riyadh',
  'Asia/Singapore',
  'Asia/Kuala_Lumpur',
  'Asia/Jakarta',
  'Asia/Bangkok',
  'Asia/Manila',
  'Asia/Hong_Kong',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Europe/London',
  'Europe/Dublin',
  'Europe/Lisbon',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Madrid',
  'Europe/Rome',
  'Europe/Moscow',
  'Africa/Cairo',
  'Africa/Lagos',
  'Africa/Johannesburg',
  'Africa/Nairobi',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Toronto',
  'America/Mexico_City',
  'America/Sao_Paulo',
  'America/Bogota',
  'Australia/Sydney',
  'Australia/Perth',
  'Pacific/Auckland',
  'UTC',
];
