import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_status.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/staff/presentation/screens/staff_appointments_screen.dart';

import '../support/fakes.dart';

const _staffId = 'stf-1';

void main() {
  late MockBookingRepository bookingRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
      ],
      child: const MaterialApp(home: StaffAppointmentsScreen(staffId: _staffId)),
    );
  }

  setUp(() {
    bookingRepository = MockBookingRepository();
  });

  testWidgets('splits a single fetched list into Upcoming / Today / Past tabs by real date and status', (tester) async {
    when(
      () => bookingRepository.ownerBookings(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        date: any(named: 'date'),
        status: any(named: 'status'),
        branchId: any(named: 'branchId'),
        staffId: _staffId,
        customerId: any(named: 'customerId'),
      ),
    ).thenAnswer(
      (_) async => const [
        Booking(
          id: 'bk-future',
          branchId: 'br-1',
          bookingDate: '2099-01-01',
          startTime: '10:00',
          endTime: '10:30',
          status: BookingStatus.confirmed,
          subtotal: 300,
          discount: 0,
          tax: 0,
          total: 300,
        ),
        Booking(
          id: 'bk-past',
          branchId: 'br-1',
          bookingDate: '2020-01-01',
          startTime: '10:00',
          endTime: '10:30',
          status: BookingStatus.completed,
          subtotal: 300,
          discount: 0,
          tax: 0,
          total: 300,
        ),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('2099-01-01 · 10:00'), findsOneWidget); // visible on the default (Upcoming) tab
    expect(find.text('2020-01-01 · 10:00'), findsNothing); // Past tab not visible yet

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(find.text('2020-01-01 · 10:00'), findsOneWidget);
    expect(find.text('2099-01-01 · 10:00'), findsNothing);
  });

  testWidgets('the repository call is scoped to this staff member\'s own id', (tester) async {
    when(
      () => bookingRepository.ownerBookings(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        date: any(named: 'date'),
        status: any(named: 'status'),
        branchId: any(named: 'branchId'),
        staffId: any(named: 'staffId'),
        customerId: any(named: 'customerId'),
      ),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    verify(
      () => bookingRepository.ownerBookings(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        date: any(named: 'date'),
        status: any(named: 'status'),
        branchId: any(named: 'branchId'),
        staffId: _staffId,
        customerId: any(named: 'customerId'),
      ),
    ).called(1);
  });
}
