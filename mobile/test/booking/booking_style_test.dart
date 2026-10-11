import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/availability.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_item_request.dart';
import 'package:salon_customer/features/booking/data/models/booking_style.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_flow_controller.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/booking_cart_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/services/data/models/salon_service.dart';

import '../support/fakes.dart';

/// "Book This Style": the chosen gallery item travels with the booking flow,
/// stays visible, is sent on create, and is dropped if the salon removed it.
void main() {
  const branch = Branch(
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
  const style = BookingStyle(
    mediaId: 'm1',
    label: 'Layered bob',
    categoryLabel: 'Haircut',
  );
  final created = Booking.fromJson({
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
    'style': {
      'id': 'm1',
      'label': 'Layered bob',
      'category_label': 'Haircut',
      'thumbnail_url': null,
    },
  });

  late MockBookingRepository repository;
  late BookingFlowController controller;

  Future<void> readyToConfirm() async {
    controller.selectBranch(branch);
    controller.toggleService(haircut);
    controller.setStyle(style);
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
          {
            'start_time': '09:00',
            'end_time': '09:30',
            'staff_ids': ['st_1'],
          },
        ],
        'staff': [
          {'id': 'st_1', 'name': 'Amit'},
        ],
      }),
    );
    controller.setDate(DateTime(2026, 9, 1));
    await Future<void>.delayed(Duration.zero);
    controller.selectSlot(controller.state.availability!.slots.first);
  }

  setUpAll(() => registerFallbackValue(<BookingItemRequest>[]));

  setUp(() {
    repository = MockBookingRepository();
    controller = BookingFlowController(repository);
  });

  test(
    'the selected style is sent as salon_media_id when the booking is created',
    () async {
      await readyToConfirm();
      when(
        () => repository.createBooking(
          branchId: any(named: 'branchId'),
          date: any(named: 'date'),
          startTime: any(named: 'startTime'),
          items: any(named: 'items'),
          notes: any(named: 'notes'),
          couponCode: any(named: 'couponCode'),
          loyaltyPointsToRedeem: any(named: 'loyaltyPointsToRedeem'),
          phone: any(named: 'phone'),
          salonMediaId: 'm1',
        ),
      ).thenAnswer((_) async => created);

      expect(await controller.confirmBooking(), isTrue);

      expect(controller.state.createdBooking?.style?.mediaId, 'm1');
      expect(controller.state.createdBooking?.style?.title, 'Layered bob');
    },
  );

  test('a booking without a style sends no salon_media_id', () async {
    await readyToConfirm();
    controller.clearStyle();
    when(
      () => repository.createBooking(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        startTime: any(named: 'startTime'),
        items: any(named: 'items'),
        notes: any(named: 'notes'),
        couponCode: any(named: 'couponCode'),
        loyaltyPointsToRedeem: any(named: 'loyaltyPointsToRedeem'),
        phone: any(named: 'phone'),
        salonMediaId: null,
      ),
    ).thenAnswer((_) async => created);

    expect(await controller.confirmBooking(), isTrue);
  });

  test('a style the salon removed is dropped and the customer can retry without it, keeping the slot', () async {
    await readyToConfirm();
    when(
      () => repository.createBooking(
        branchId: any(named: 'branchId'),
        date: any(named: 'date'),
        startTime: any(named: 'startTime'),
        items: any(named: 'items'),
        notes: any(named: 'notes'),
        couponCode: any(named: 'couponCode'),
        loyaltyPointsToRedeem: any(named: 'loyaltyPointsToRedeem'),
        phone: any(named: 'phone'),
        salonMediaId: any(named: 'salonMediaId'),
      ),
    ).thenThrow(
      const ApiException(
        message: 'The selected style is no longer available.',
        type: ApiErrorType.validation,
        fieldErrors: {
          'salon_media_id': ['gone'],
        },
      ),
    );

    expect(await controller.confirmBooking(), isFalse);

    expect(controller.state.style, isNull);
    expect(controller.state.selectedSlot, isNotNull);
    expect(controller.state.selectedServices, [haircut]);
    expect(controller.state.submissionError, contains('no longer available'));
  });

  test('selecting the branch again starts clean (no stale style) and reset clears it', () {
    controller.selectBranch(branch);
    controller.setStyle(style);
    controller.selectBranch(branch);
    expect(controller.state.style, isNull);
    controller.setStyle(style);
    controller.reset();
    expect(controller.state.style, isNull);
  });

  test(
    'Booking.fromJson reads the persisted style, and tolerates its absence',
    () {
      expect(created.style?.mediaId, 'm1');
      expect(created.style?.categoryLabel, 'Haircut');
      final plain = Booking.fromJson({
        'id': 'b',
        'branch_id': 'br_1',
        'booking_date': '2026-09-01',
        'start_time': '09:00',
        'end_time': '09:30',
        'status': 'pending',
        'subtotal': '1',
        'discount': '0',
        'tax': '0',
        'total': '1',
        'style': null,
      });
      expect(plain.style, isNull);
      // A deleted gallery item leaves only the label snapshot.
      expect(const BookingStyle(label: 'Layered bob').title, 'Layered bob');
      expect(const BookingStyle().title, 'Selected style');
    },
  );

  testWidgets(
    'the cart keeps the chosen style visible and lets the customer remove it',
    (tester) async {
      controller.selectBranch(branch);
      controller.toggleService(haircut);
      controller.setStyle(style);
      final router = GoRouter(
        initialLocation: '/booking/cart',
        routes: [
          GoRoute(
            path: '/booking/cart',
            builder: (c, s) => const BookingCartScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(FakeSecureStorage()),
            bookingFlowControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('selected-style-banner')), findsOneWidget);
      expect(find.text('Layered bob'), findsOneWidget);
      expect(find.textContaining('30 min'), findsOneWidget); // the service row

      await tester.tap(find.byKey(const Key('selected-style-remove')));
      await tester.pump();

      expect(find.byKey(const Key('selected-style-banner')), findsNothing);
      expect(controller.state.style, isNull);
      expect(controller.state.selectedServices, [haircut]);
    },
  );
}
