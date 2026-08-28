import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/features/booking/data/models/availability.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_item_request.dart';
import 'package:salon_customer/features/booking/data/repositories/booking_repository.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_flow_controller.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_flow_state.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/services/data/models/salon_service.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

void main() {
  late _MockBookingRepository repository;
  late BookingFlowController controller;

  final branch = const Branch(
    id: 'br_1',
    name: 'Main',
    slug: 'main',
    address: Address(),
    timezone: 'UTC',
    status: 'active',
  );
  const haircut = SalonService(
    id: 'sv_1',
    branchId: 'br_1',
    name: 'Haircut',
    slug: 'haircut',
    gender: 'unisex',
    price: 300,
    durationMinutes: 30,
    status: 'active',
    sortOrder: 0,
  );

  setUpAll(() {
    registerFallbackValue(<BookingItemRequest>[]);
  });

  setUp(() {
    repository = _MockBookingRepository();
    controller = BookingFlowController(repository);
  });

  test('toggling a service adds and then removes it, resetting availability', () {
    controller.selectBranch(branch);
    controller.toggleService(haircut);
    expect(controller.state.selectedServices, [haircut]);

    controller.toggleService(haircut);
    expect(controller.state.selectedServices, isEmpty);
  });

  test('setDate triggers an availability fetch and stores the result', () async {
    controller.selectBranch(branch);
    controller.toggleService(haircut);
    final availability = AvailabilityResult.fromJson({
      'date': '2026-09-01',
      'duration_minutes': 30,
      'buffer_minutes': 0,
      'slots': [
        {'start_time': '09:00', 'end_time': '09:30', 'staff_ids': ['st_1']},
      ],
      'staff': [
        {'id': 'st_1', 'name': 'Amit'},
      ],
    });
    when(
      () => repository.availability(
        branchId: 'br_1',
        date: any(named: 'date'),
        serviceIds: ['sv_1'],
        staffId: null,
      ),
    ).thenAnswer((_) async => availability);

    controller.setDate(DateTime(2026, 9, 1));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.isLoadingAvailability, isFalse);
    expect(controller.state.availability?.slots, hasLength(1));
    expect(controller.state.availabilityError, isNull);
  });

  test('an availability failure surfaces the error and clears availability', () async {
    controller.selectBranch(branch);
    controller.toggleService(haircut);
    when(
      () => repository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).thenThrow(const ApiException(message: 'The branch is closed on the selected date.', type: ApiErrorType.conflict));

    controller.setDate(DateTime(2026, 9, 1));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.availability, isNull);
    expect(controller.state.availabilityError, 'The branch is closed on the selected date.');
  });

  test('confirmBooking succeeds and stores the created booking', () async {
    controller.selectBranch(branch);
    controller.toggleService(haircut);

    when(
      () => repository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).thenAnswer(
      (_) async => AvailabilityResult.fromJson({
        'date': '2026-09-01',
        'duration_minutes': 30,
        'buffer_minutes': 0,
        'slots': [
          {'start_time': '09:00', 'end_time': '09:30', 'staff_ids': ['st_1']},
        ],
        'staff': [
          {'id': 'st_1', 'name': 'Amit'},
        ],
      }),
    );
    controller.setDate(DateTime(2026, 9, 1));
    await Future<void>.delayed(Duration.zero);
    controller.selectSlot(controller.state.availability!.slots.first);

    final createdBooking = Booking.fromJson({
      'id': 'bk_1',
      'branch_id': 'br_1',
      'booking_date': '2026-09-01',
      'start_time': '09:00',
      'end_time': '09:30',
      'status': 'pending',
      'subtotal': '300.00',
      'discount': '0.00',
      'tax': '0.00',
      'total': '300.00',
    });
    when(
      () => repository.createBooking(
        branchId: 'br_1',
        date: '2026-09-01',
        startTime: '09:00',
        items: any(named: 'items'),
        notes: any(named: 'notes'),
      ),
    ).thenAnswer((_) async => createdBooking);

    final success = await controller.confirmBooking();

    expect(success, isTrue);
    expect(controller.state.createdBooking?.id, 'bk_1');
    expect(controller.state.isSubmitting, isFalse);
  });

  test('confirmBooking on a 409 conflict shows a friendly message and refreshes availability', () async {
    controller.selectBranch(branch);
    controller.toggleService(haircut);

    when(
      () => repository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).thenAnswer(
      (_) async => AvailabilityResult.fromJson({
        'date': '2026-09-01',
        'duration_minutes': 30,
        'buffer_minutes': 0,
        'slots': [
          {'start_time': '09:00', 'end_time': '09:30', 'staff_ids': ['st_1']},
        ],
        'staff': [
          {'id': 'st_1', 'name': 'Amit'},
        ],
      }),
    );
    controller.setDate(DateTime(2026, 9, 1));
    await Future<void>.delayed(Duration.zero);
    controller.selectSlot(controller.state.availability!.slots.first);

    when(
      () => repository.createBooking(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        startTime: any(named: 'startTime'),
        items: any(named: 'items'),
        notes: any(named: 'notes'),
      ),
    ).thenThrow(const ApiException(message: 'Conflict.', type: ApiErrorType.conflict));

    final success = await controller.confirmBooking();

    expect(success, isFalse);
    expect(controller.state.submissionError, contains('no longer available'));
    expect(controller.state.selectedSlot, isNull);
    // loadAvailability was called again after the conflict (initial call + refresh).
    verify(
      () => repository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).called(2);
  });

  test('setStaffMode(any) clears a previously selected specific staff id', () {
    controller.selectBranch(branch);
    controller.toggleService(haircut);

    when(
      () => repository.availability(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        serviceIds: any(named: 'serviceIds'),
        staffId: any(named: 'staffId'),
      ),
    ).thenAnswer(
      (_) async => AvailabilityResult.fromJson({
        'date': '2026-09-01',
        'duration_minutes': 30,
        'buffer_minutes': 0,
        'slots': <dynamic>[],
        'staff': <dynamic>[],
      }),
    );

    controller.selectStaff('st_1');
    expect(controller.state.staffMode, StaffSelectionMode.specific);
    expect(controller.state.selectedStaffId, 'st_1');

    controller.setStaffMode(StaffSelectionMode.any);
    expect(controller.state.staffMode, StaffSelectionMode.any);
    expect(controller.state.selectedStaffId, isNull);
  });

  group('real-device bug fix: first-time-customer phone requirement', () {
    // The backend auto-creates a first-time customer's profile on booking —
    // see CustomerBookingController::resolveOrCreateCustomer() — but needs a
    // phone number to do it, reported as a `phone` field error.
    test('confirmBooking sets requiresPhone on a phone field error, and canConfirm becomes false', () async {
      controller.selectBranch(branch);
      controller.toggleService(haircut);
      when(
        () => repository.availability(
          branchId: any(named: 'branchId'),
          date: any(named: 'date'),
          serviceIds: any(named: 'serviceIds'),
          staffId: any(named: 'staffId'),
        ),
      ).thenAnswer(
        (_) async => AvailabilityResult.fromJson({
          'date': '2026-09-01',
          'duration_minutes': 30,
          'buffer_minutes': 0,
          'slots': [
            {'start_time': '09:00', 'end_time': '09:30', 'staff_ids': ['st_1']},
          ],
          'staff': [
            {'id': 'st_1', 'name': 'Amit'},
          ],
        }),
      );
      controller.setDate(DateTime(2026, 9, 1));
      await Future<void>.delayed(Duration.zero);
      controller.selectSlot(controller.state.availability!.slots.first);

      when(
        () => repository.createBooking(
          branchId: any(named: 'branchId'),
          date: any(named: 'date'),
          startTime: any(named: 'startTime'),
          items: any(named: 'items'),
          notes: any(named: 'notes'),
        ),
      ).thenThrow(
        const ApiException(
          message: 'A valid phone number is required to complete your first booking with this salon.',
          type: ApiErrorType.validation,
          fieldErrors: {'phone': ['The phone field is required.']},
        ),
      );

      expect(controller.state.canConfirm, isTrue, reason: 'nothing requires a phone yet');
      final success = await controller.confirmBooking();

      expect(success, isFalse);
      expect(controller.state.requiresPhone, isTrue);
      // The slot the customer already picked must survive — only a 409
      // conflict clears it.
      expect(controller.state.selectedSlot, isNotNull);
      expect(controller.state.canConfirm, isFalse, reason: 'requiresPhone but no phone entered yet');

      controller.setPhone('9123456780');
      expect(controller.state.canConfirm, isTrue, reason: 'phone now entered');
    });

    test('confirmBooking sends the entered phone and succeeds once provided', () async {
      controller.selectBranch(branch);
      controller.toggleService(haircut);
      when(
        () => repository.availability(
          branchId: any(named: 'branchId'),
          date: any(named: 'date'),
          serviceIds: any(named: 'serviceIds'),
          staffId: any(named: 'staffId'),
        ),
      ).thenAnswer(
        (_) async => AvailabilityResult.fromJson({
          'date': '2026-09-01',
          'duration_minutes': 30,
          'buffer_minutes': 0,
          'slots': [
            {'start_time': '09:00', 'end_time': '09:30', 'staff_ids': ['st_1']},
          ],
          'staff': [
            {'id': 'st_1', 'name': 'Amit'},
          ],
        }),
      );
      controller.setDate(DateTime(2026, 9, 1));
      await Future<void>.delayed(Duration.zero);
      controller.selectSlot(controller.state.availability!.slots.first);
      controller.setPhone('9123456780');

      final createdBooking = Booking.fromJson({
        'id': 'bk_1',
        'branch_id': 'br_1',
        'booking_date': '2026-09-01',
        'start_time': '09:00',
        'end_time': '09:30',
        'status': 'pending',
        'subtotal': '300.00',
        'discount': '0.00',
        'tax': '0.00',
        'total': '300.00',
      });
      when(
        () => repository.createBooking(
          branchId: 'br_1',
          date: '2026-09-01',
          startTime: '09:00',
          items: any(named: 'items'),
          notes: any(named: 'notes'),
          phone: '9123456780',
        ),
      ).thenAnswer((_) async => createdBooking);

      final success = await controller.confirmBooking();

      expect(success, isTrue);
      expect(controller.state.createdBooking?.id, 'bk_1');
      expect(controller.state.requiresPhone, isFalse);
    });
  });
}
