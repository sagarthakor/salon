/// Mirrors `App\Enums\BookingStatus`. Kept as a Dart enum (not a raw string)
/// so the UI can exhaustively switch on it; [BookingStatus.fromApi] is the
/// only place backend string values are parsed.
enum BookingStatus {
  pending,
  confirmed,
  checkedIn,
  inService,
  completed,
  cancelled,
  noShow;

  static BookingStatus fromApi(String value) => switch (value) {
    'pending' => BookingStatus.pending,
    'confirmed' => BookingStatus.confirmed,
    'checked_in' => BookingStatus.checkedIn,
    'in_service' => BookingStatus.inService,
    'completed' => BookingStatus.completed,
    'cancelled' => BookingStatus.cancelled,
    'no_show' => BookingStatus.noShow,
    _ => throw ArgumentError('Unknown booking status: $value'),
  };

  String get label => switch (this) {
    BookingStatus.pending => 'Pending',
    BookingStatus.confirmed => 'Confirmed',
    BookingStatus.checkedIn => 'Checked in',
    BookingStatus.inService => 'In service',
    BookingStatus.completed => 'Completed',
    BookingStatus.cancelled => 'Cancelled',
    BookingStatus.noShow => 'No-show',
  };

  bool get isUpcoming => this == BookingStatus.pending || this == BookingStatus.confirmed;

  bool get isActive =>
      this == BookingStatus.pending ||
      this == BookingStatus.confirmed ||
      this == BookingStatus.checkedIn ||
      this == BookingStatus.inService;

  bool get isTerminal =>
      this == BookingStatus.completed || this == BookingStatus.cancelled || this == BookingStatus.noShow;

  /// Wire value expected by `PATCH /bookings/{id}` `status` and the
  /// `confirm`/`cancel` endpoints. The inverse of [fromApi].
  String get apiValue => switch (this) {
    BookingStatus.pending => 'pending',
    BookingStatus.confirmed => 'confirmed',
    BookingStatus.checkedIn => 'checked_in',
    BookingStatus.inService => 'in_service',
    BookingStatus.completed => 'completed',
    BookingStatus.cancelled => 'cancelled',
    BookingStatus.noShow => 'no_show',
  };

  /// UI hint only, mirroring `App\Enums\BookingStatus::canTransitionTo` —
  /// which statuses to *offer* as next actions. The backend independently
  /// re-validates every transition and is the only real enforcement; this
  /// just avoids showing a button that would always 409.
  List<BookingStatus> get nextActions => switch (this) {
    BookingStatus.pending => [BookingStatus.confirmed, BookingStatus.cancelled],
    BookingStatus.confirmed => [BookingStatus.checkedIn, BookingStatus.cancelled, BookingStatus.noShow],
    BookingStatus.checkedIn => [BookingStatus.inService, BookingStatus.cancelled],
    BookingStatus.inService => [BookingStatus.completed, BookingStatus.cancelled],
    BookingStatus.completed || BookingStatus.cancelled || BookingStatus.noShow => [],
  };
}
