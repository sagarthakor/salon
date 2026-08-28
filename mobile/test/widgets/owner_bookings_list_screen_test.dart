import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/data/models/booking.dart';
import 'package:salon_customer/features/booking/data/models/booking_status.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/owner/bookings/presentation/screens/owner_bookings_list_screen.dart';
import 'package:salon_customer/features/owner/branches/presentation/providers/owner_branch_providers.dart';
import 'package:salon_customer/features/owner/staff/presentation/providers/staff_providers.dart';

import '../support/fakes.dart';

Booking _booking({required String id, required BookingStatus status}) => Booking(
  id: id,
  branchId: 'br-1',
  bookingDate: '2026-08-23',
  startTime: '10:00',
  endTime: '10:30',
  status: status,
  subtotal: 500,
  discount: 0,
  tax: 0,
  total: 500,
);

void main() {
  late MockBookingRepository bookingRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
        ownerBranchesProvider.overrideWith((ref) async => []),
        staffListProvider.overrideWith((ref) async => []),
      ],
      child: const MaterialApp(home: OwnerBookingsListScreen()),
    );
  }

  setUp(() {
    bookingRepository = MockBookingRepository();
  });

  testWidgets('lists bookings fetched from the owner endpoint with status chips', (tester) async {
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
    ).thenAnswer((_) async => [_booking(id: 'bk-1', status: BookingStatus.confirmed), _booking(id: 'bk-2', status: BookingStatus.pending)]);

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('2026-08-23 · 10:00'), findsNWidgets(2));
  });

  testWidgets('shows an empty state when no bookings match the current filters', (tester) async {
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

    expect(find.text('No bookings match these filters.'), findsOneWidget);
  });

  testWidgets('opens the filter sheet with status options mirroring BookingStatus', (tester) async {
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

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump();

    expect(find.text('Filter bookings'), findsOneWidget);
    expect(find.text('Any status'), findsOneWidget);
  });
}
