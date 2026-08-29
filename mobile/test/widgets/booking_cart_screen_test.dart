import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_flow_controller.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/booking_cart_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/services/data/models/salon_service.dart';

import '../support/fakes.dart';

/// The ecommerce-style cart step — a pure view over
/// [BookingFlowController]'s existing `selectedServices` state. No new
/// pricing logic: totals shown here are the same client-side estimate the
/// booking summary screen already computed before this screen existed, and
/// the server still recalculates authoritatively when the booking is
/// actually confirmed.
void main() {
  const branch = Branch(id: 'br_1', name: 'Main Branch', slug: 'main', address: Address(), timezone: 'UTC', status: 'active');
  const haircut = SalonService(
    id: 'sv_1',
    branchId: 'br_1',
    name: 'Haircut',
    slug: 'haircut',
    gender: 'unisex',
    price: 300,
    durationMinutes: 30,
    imageUrl: 'https://cdn.example.test/haircut.jpg',
    status: 'active',
    sortOrder: 0,
  );
  const beardTrim = SalonService(
    id: 'sv_2',
    branchId: 'br_1',
    name: 'Beard Trim',
    slug: 'beard-trim',
    gender: 'male',
    price: 150,
    durationMinutes: 20,
    status: 'active',
    sortOrder: 1,
  );

  Widget buildApp(BookingFlowController controller) {
    final router = GoRouter(
      initialLocation: '/booking/cart',
      routes: [
        GoRoute(path: '/booking/cart', builder: (context, state) => const BookingCartScreen()),
        GoRoute(path: '/booking/schedule', builder: (context, state) => const Scaffold(body: Text('Choose Date'))),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        bookingFlowControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('lists each selected service with its image, name, price, and duration', (tester) async {
    final controller = BookingFlowController(MockBookingRepository());
    controller.selectBranch(branch);
    controller.toggleService(haircut);
    controller.toggleService(beardTrim);

    await tester.pumpWidget(buildApp(controller));
    await tester.pump();

    expect(find.text('Haircut'), findsOneWidget);
    expect(find.text('Beard Trim'), findsOneWidget);
    expect(find.textContaining('₹300'), findsOneWidget);
    expect(find.textContaining('₹150'), findsOneWidget);
    expect(find.textContaining('30 min'), findsOneWidget);
    expect(find.textContaining('20 min'), findsOneWidget);
  });

  testWidgets('shows the total number of services and the total amount', (tester) async {
    final controller = BookingFlowController(MockBookingRepository());
    controller.selectBranch(branch);
    controller.toggleService(haircut);
    controller.toggleService(beardTrim);

    await tester.pumpWidget(buildApp(controller));
    await tester.pump();

    expect(find.textContaining('2 services'), findsOneWidget);
    expect(find.textContaining('Total ₹450'), findsOneWidget);
  });

  testWidgets('removing a service updates the cart and the total', (tester) async {
    final controller = BookingFlowController(MockBookingRepository());
    controller.selectBranch(branch);
    controller.toggleService(haircut);
    controller.toggleService(beardTrim);

    await tester.pumpWidget(buildApp(controller));
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.remove_circle_outline).first);
    await tester.pump();

    expect(find.text('Haircut'), findsNothing);
    expect(find.text('Beard Trim'), findsOneWidget);
    expect(find.textContaining('1 service'), findsOneWidget);
    expect(find.textContaining('Total ₹150'), findsOneWidget);
  });

  testWidgets('an empty cart shows a friendly message and disables Continue', (tester) async {
    final controller = BookingFlowController(MockBookingRepository());
    controller.selectBranch(branch);

    await tester.pumpWidget(buildApp(controller));
    await tester.pump();

    expect(find.text('Your cart is empty. Go back and add a service.'), findsOneWidget);
    final continueButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Continue to Appointment'));
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('tapping Continue to Appointment proceeds to the existing schedule step', (tester) async {
    final controller = BookingFlowController(MockBookingRepository());
    controller.selectBranch(branch);
    controller.toggleService(haircut);

    await tester.pumpWidget(buildApp(controller));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue to Appointment'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Date'), findsOneWidget);
  });
}
