import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/core/utils/date_format.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_status.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/owner/staff/presentation/providers/staff_providers.dart';
import 'package:salon_customer/features/staff/presentation/screens/staff_today_tab.dart';

import '../support/fakes.dart';

const _staffId = 'stf-1';

void main() {
  late MockBookingRepository bookingRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
        staffWorkingHoursProvider(_staffId).overrideWith((ref) async => []),
        staffBreaksProvider(_staffId).overrideWith((ref) async => []),
        staffLeavesProvider(_staffId).overrideWith((ref) async => []),
      ],
      child: const MaterialApp(home: StaffTodayTab(staffId: _staffId)),
    );
  }

  setUp(() {
    bookingRepository = MockBookingRepository();
  });

  testWidgets('shows real counts derived from today\'s bookings — total, completed, remaining', (tester) async {
    final today = toApiDate(DateTime.now());
    when(
      () => bookingRepository.ownerBookings(
        staffId: _staffId,
        date: today,
        perPage: 100,
        page: any(named: 'page'),
        status: any(named: 'status'),
        branchId: any(named: 'branchId'),
        customerId: any(named: 'customerId'),
      ),
    ).thenAnswer(
      (_) async => const [
        Booking(
          id: 'bk-1',
          branchId: 'br-1',
          bookingDate: '2026-08-24',
          startTime: '09:00',
          endTime: '09:30',
          status: BookingStatus.completed,
          subtotal: 300,
          discount: 0,
          tax: 0,
          total: 300,
        ),
        Booking(
          id: 'bk-2',
          branchId: 'br-1',
          bookingDate: '2026-08-24',
          startTime: '11:00',
          endTime: '11:30',
          status: BookingStatus.confirmed,
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

    expect(find.text('2'), findsOneWidget); // total today
    expect(find.text('1'), findsNWidgets(2)); // completed and remaining both 1
  });

  testWidgets('shows "No appointments today" instead of fabricating one when there are none', (tester) async {
    when(
      () => bookingRepository.ownerBookings(
        staffId: _staffId,
        date: any(named: 'date'),
        perPage: any(named: 'perPage'),
        page: any(named: 'page'),
        status: any(named: 'status'),
        branchId: any(named: 'branchId'),
        customerId: any(named: 'customerId'),
      ),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No appointments today.'), findsOneWidget);
    expect(find.text('No more appointments today.'), findsOneWidget);
  });
}
