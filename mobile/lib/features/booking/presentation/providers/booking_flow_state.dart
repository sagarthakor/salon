import '../../../salon/data/models/branch.dart';
import '../../../services/data/models/salon_service.dart';
import '../../data/models/availability.dart';
import '../../data/models/booking.dart';
import '../../data/models/booking_pricing.dart';

/// Whether the customer wants a specific staff member or lets the backend
/// assign automatically. Never resolved client-side — see BookingRepository.
enum StaffSelectionMode { any, specific }

/// All state for one in-progress booking attempt: branch → services → staff
/// preference → date → availability → slot → submission. A single
/// [BookingFlowController] owns this so it isn't threaded manually through
/// five screens' constructors.
class BookingFlowState {
  const BookingFlowState({
    this.branch,
    this.selectedServices = const [],
    this.staffMode = StaffSelectionMode.any,
    this.selectedStaffId,
    this.date,
    this.availability,
    this.isLoadingAvailability = false,
    this.availabilityError,
    this.selectedSlot,
    this.notes = '',
    this.couponCode = '',
    this.loyaltyPointsToRedeem,
    this.pricing,
    this.isPricingLoading = false,
    this.pricingError,
    this.isSubmitting = false,
    this.submissionError,
    this.createdBooking,
  });

  final Branch? branch;
  final List<SalonService> selectedServices;
  final StaffSelectionMode staffMode;
  final String? selectedStaffId;
  final DateTime? date;
  final AvailabilityResult? availability;
  final bool isLoadingAvailability;
  final String? availabilityError;
  final AvailabilitySlot? selectedSlot;
  final String notes;
  final String couponCode;
  final int? loyaltyPointsToRedeem;
  final BookingPricing? pricing;
  final bool isPricingLoading;
  final String? pricingError;
  final bool isSubmitting;
  final String? submissionError;
  final Booking? createdBooking;

  num get estimatedTotal => selectedServices.fold<num>(0, (sum, s) => sum + s.price);

  int get estimatedDurationMinutes => selectedServices.fold<int>(0, (sum, s) => sum + s.durationMinutes);

  bool get canProceedPastServices => selectedServices.isNotEmpty;

  bool get canConfirm => branch != null && selectedServices.isNotEmpty && selectedSlot != null && !isSubmitting;

  BookingFlowState copyWith({
    Branch? branch,
    List<SalonService>? selectedServices,
    StaffSelectionMode? staffMode,
    String? selectedStaffId,
    bool clearSelectedStaffId = false,
    DateTime? date,
    AvailabilityResult? availability,
    bool clearAvailability = false,
    bool? isLoadingAvailability,
    String? availabilityError,
    bool clearAvailabilityError = false,
    AvailabilitySlot? selectedSlot,
    bool clearSelectedSlot = false,
    String? notes,
    String? couponCode,
    int? loyaltyPointsToRedeem,
    bool clearLoyaltyPointsToRedeem = false,
    BookingPricing? pricing,
    bool clearPricing = false,
    bool? isPricingLoading,
    String? pricingError,
    bool clearPricingError = false,
    bool? isSubmitting,
    String? submissionError,
    bool clearSubmissionError = false,
    Booking? createdBooking,
  }) {
    return BookingFlowState(
      branch: branch ?? this.branch,
      selectedServices: selectedServices ?? this.selectedServices,
      staffMode: staffMode ?? this.staffMode,
      selectedStaffId: clearSelectedStaffId ? null : (selectedStaffId ?? this.selectedStaffId),
      date: date ?? this.date,
      availability: clearAvailability ? null : (availability ?? this.availability),
      isLoadingAvailability: isLoadingAvailability ?? this.isLoadingAvailability,
      availabilityError: clearAvailabilityError ? null : (availabilityError ?? this.availabilityError),
      selectedSlot: clearSelectedSlot ? null : (selectedSlot ?? this.selectedSlot),
      notes: notes ?? this.notes,
      couponCode: couponCode ?? this.couponCode,
      loyaltyPointsToRedeem: clearLoyaltyPointsToRedeem ? null : (loyaltyPointsToRedeem ?? this.loyaltyPointsToRedeem),
      pricing: clearPricing ? null : (pricing ?? this.pricing),
      isPricingLoading: isPricingLoading ?? this.isPricingLoading,
      pricingError: clearPricingError ? null : (pricingError ?? this.pricingError),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submissionError: clearSubmissionError ? null : (submissionError ?? this.submissionError),
      createdBooking: createdBooking ?? this.createdBooking,
    );
  }
}
