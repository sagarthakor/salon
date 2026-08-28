import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
}
