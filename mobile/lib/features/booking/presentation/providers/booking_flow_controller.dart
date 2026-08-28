import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/date_format.dart';
import '../../../salon/data/models/branch.dart';
import '../../../services/data/models/salon_service.dart';
import '../../data/models/availability.dart';
import '../../data/models/booking_item_request.dart';
import '../../data/repositories/booking_repository.dart';
import 'booking_flow_state.dart';

/// Drives the multi-step booking flow (branch → services → staff preference →
/// date → availability → slot → confirm), talking to [BookingRepository] for
/// every step that needs backend truth. Availability is always re-fetched
/// after anything that could invalidate it (service/date/staff change) and
/// once more implicitly by the create-booking call itself, which is the
/// authoritative, final check.
class BookingFlowController extends StateNotifier<BookingFlowState> {
  BookingFlowController(this._repository) : super(const BookingFlowState());

  final BookingRepository _repository;

  void selectBranch(Branch branch) {
    state = BookingFlowState(branch: branch);
  }

  void toggleService(SalonService service) {
    final selected = List<SalonService>.of(state.selectedServices);
    if (selected.any((s) => s.id == service.id)) {
      selected.removeWhere((s) => s.id == service.id);
    } else {
      selected.add(service);
    }
    state = state.copyWith(
      selectedServices: selected,
      clearAvailability: true,
      clearSelectedSlot: true,
      clearSubmissionError: true,
    );
  }

  void setStaffMode(StaffSelectionMode mode) {
    state = state.copyWith(staffMode: mode, clearSelectedStaffId: mode == StaffSelectionMode.any);
    if (state.date != null) loadAvailability();
  }

  void selectStaff(String staffId) {
    state = state.copyWith(staffMode: StaffSelectionMode.specific, selectedStaffId: staffId);
    loadAvailability();
  }

  void setDate(DateTime date) {
    state = state.copyWith(date: date, clearSelectedSlot: true);
    loadAvailability();
  }

  Future<void> loadAvailability() async {
    final branch = state.branch;
    final date = state.date;
    if (branch == null || date == null || state.selectedServices.isEmpty) return;

    state = state.copyWith(isLoadingAvailability: true, clearAvailabilityError: true);
    try {
      final result = await _repository.availability(
        branchId: branch.id,
        date: toApiDate(date),
        serviceIds: state.selectedServices.map((s) => s.id).toList(),
        staffId: state.staffMode == StaffSelectionMode.specific ? state.selectedStaffId : null,
      );
      state = state.copyWith(availability: result, isLoadingAvailability: false);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingAvailability: false, availabilityError: e.message, clearAvailability: true);
    }
  }

  void selectSlot(AvailabilitySlot slot) {
    state = state.copyWith(selectedSlot: slot);
  }

  void setNotes(String notes) {
    state = state.copyWith(notes: notes);
  }

  void setCouponCode(String code) {
    state = state.copyWith(couponCode: code, clearPricing: true, clearPricingError: true);
  }

  void setLoyaltyPointsToRedeem(int? points) {
    state = state.copyWith(loyaltyPointsToRedeem: points, clearLoyaltyPointsToRedeem: points == null, clearPricing: true, clearPricingError: true);
  }

  /// Read-only preview so the customer can see the effect of a coupon code
  /// or a loyalty-point redemption before confirming — the actual booking
  /// recalculates everything server-side regardless (see BookingRepository).
  Future<void> previewPricing() async {
    final branch = state.branch;
    if (branch == null || state.selectedServices.isEmpty) return;

    state = state.copyWith(isPricingLoading: true, clearPricingError: true);
    try {
      final pricing = await _repository.pricePreview(
        branchId: branch.id,
        serviceIds: state.selectedServices.map((s) => s.id).toList(),
        couponCode: state.couponCode.trim().isEmpty ? null : state.couponCode.trim(),
        loyaltyPointsToRedeem: state.loyaltyPointsToRedeem,
      );
      state = state.copyWith(pricing: pricing, isPricingLoading: false);
    } on ApiException catch (e) {
      state = state.copyWith(isPricingLoading: false, pricingError: e.message, clearPricing: true);
    }
  }

  /// Returns true on success. On a 409 (the slot was taken between browsing
  /// and confirming), refreshes availability so the customer sees current
  /// slots rather than a stale list, and leaves [BookingFlowState.selectedSlot]
  /// cleared so they must pick again.
  Future<bool> confirmBooking() async {
    final branch = state.branch;
    final slot = state.selectedSlot;
    if (branch == null || slot == null || state.selectedServices.isEmpty) return false;

    state = state.copyWith(isSubmitting: true, clearSubmissionError: true);
    try {
      final staffId = state.staffMode == StaffSelectionMode.specific ? state.selectedStaffId : null;
      final booking = await _repository.createBooking(
        branchId: branch.id,
        date: toApiDate(state.date!),
        startTime: slot.startTime,
        items: state.selectedServices.map((s) => BookingItemRequest(serviceId: s.id, staffId: staffId)).toList(),
        notes: state.notes,
        couponCode: state.couponCode.trim().isEmpty ? null : state.couponCode.trim(),
        loyaltyPointsToRedeem: state.loyaltyPointsToRedeem,
      );
      state = state.copyWith(isSubmitting: false, createdBooking: booking);
      return true;
    } on ApiException catch (e) {
      final message = e.type == ApiErrorType.conflict
          ? 'That slot is no longer available. Please select another time.'
          : e.message;
      state = state.copyWith(isSubmitting: false, submissionError: message, clearSelectedSlot: true);
      if (e.type == ApiErrorType.conflict) {
        await loadAvailability();
      }
      return false;
    }
  }

  void reset() {
    state = const BookingFlowState();
  }
}
