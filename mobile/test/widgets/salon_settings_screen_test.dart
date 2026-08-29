import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/salon/presentation/providers/owner_salon_providers.dart';
import 'package:salon_customer/features/owner/salon/presentation/screens/salon_settings_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockOwnerSalonRepository salonRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ownerSalonRepositoryProvider.overrideWithValue(salonRepository),
      ],
      child: const MaterialApp(home: SalonSettingsScreen()),
    );
  }

  setUp(() {
    salonRepository = MockOwnerSalonRepository();
  });

  testWidgets('loads and displays the current booking-engine settings', (tester) async {
    when(() => salonRepository.settings()).thenAnswer(
      (_) async => {
        'booking_enabled': true,
        'customer_booking_enabled': false,
        'slot_interval_minutes': 15,
        'min_advance_booking_minutes': 30,
        'max_advance_booking_days': 14,
        'booking_buffer_minutes': 5,
        'cancellation_window_minutes': 60,
      },
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    final bookingEnabledSwitch = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Booking enabled'));
    expect(bookingEnabledSwitch.value, isTrue);
    final customerBookingSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Customer self-booking enabled'),
    );
    expect(customerBookingSwitch.value, isFalse);

    final slotIntervalField = tester.widget<TextField>(find.widgetWithText(TextField, 'Slot interval (minutes)'));
    expect(slotIntervalField.controller!.text, '15');
  });

  testWidgets('saving submits every setting field, including toggled switches, to updateSettings', (tester) async {
    when(() => salonRepository.settings()).thenAnswer(
      (_) async => {
        'booking_enabled': false,
        'customer_booking_enabled': false,
        'slot_interval_minutes': 15,
        'min_advance_booking_minutes': 0,
        'max_advance_booking_days': 30,
        'booking_buffer_minutes': 0,
        'cancellation_window_minutes': 0,
      },
    );
    when(() => salonRepository.updateSettings(any())).thenAnswer((_) async => {});

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Booking enabled'));
    await tester.pump();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    final captured = verify(() => salonRepository.updateSettings(captureAny())).captured.single as Map<String, dynamic>;
    expect(captured['booking_enabled'], isTrue);
    expect(captured['slot_interval_minutes'], 15);
    expect(captured['max_advance_booking_days'], 30);
  });

  group('real-device bug fix: no Salon yet', () {
    // Root cause of the raw "No query results for model [App\Models\Salon]"
    // error real-device testing found: this screen is the only place in the
    // app that rendered a raw ApiException.message. It's now unreachable
    // during onboarding (see salon_profile_screen_test.dart), but this is
    // the last line of defense in case it's ever reached with no Salon yet.
    testWidgets('shows a friendly message instead of the raw backend 404 when no salon exists yet', (tester) async {
      when(() => salonRepository.settings()).thenThrow(
        const ApiException(message: 'No query results for model [App\\Models\\Salon].', type: ApiErrorType.notFound, statusCode: 404),
      );

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      expect(find.text('Please set up your salon profile first.'), findsOneWidget);
      expect(find.textContaining('No query results for model'), findsNothing);
      expect(find.textContaining('App\\Models\\Salon'), findsNothing);
    });

    testWidgets('still shows the raw message with a retry button for non-404 errors', (tester) async {
      when(() => salonRepository.settings()).thenThrow(
        const ApiException(message: 'The server ran into a problem. Please try again shortly.', type: ApiErrorType.server, statusCode: 500),
      );

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      expect(find.text('The server ran into a problem. Please try again shortly.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    // The actual root cause found on a real device: a brand-new salon has
    // zero `salon_settings` rows, and the backend used to return an empty
    // JSON array (`[]`) instead of an object (`{}`) for that case — Dart's
    // `body['data'] as Map<String, dynamic>` cast then threw a raw
    // `TypeError`, never an `ApiException`, landing exactly here. Fixed
    // server-side (SalonSettingsResource now always returns full default
    // values), but this fallback is the last line of defense for any other
    // non-ApiException failure.
    testWidgets('shows a friendly message, never a raw exception, for a non-ApiException failure', (tester) async {
      when(() => salonRepository.settings()).thenThrow(TypeError());

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      expect(find.text('Booking settings could not be loaded. Please try again.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
