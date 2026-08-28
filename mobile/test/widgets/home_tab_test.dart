import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/home/presentation/screens/home_tab.dart';
import 'package:salon_customer/features/salon/data/models/customer_salon.dart';
import 'package:salon_customer/features/salon/presentation/providers/salon_providers.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../support/fakes.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  String? lastLaunchedUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastLaunchedUrl = url;
    return true;
  }

  @override
  Future<bool> canLaunch(String url) async => true;
}

/// The salon's official Instagram profile link, shown on the customer's
/// salon card on the Home tab — deliberately separate from a service's
/// Instagram post/reel link (see `booking_service_selection_screen_test.dart`,
/// unchanged by this feature).
void main() {
  late MockAuthRepository authRepository;
  late MockSalonRepository salonRepository;
  late MockBookingRepository bookingRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
        salonRepositoryProvider.overrideWithValue(salonRepository),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
      ],
      child: const MaterialApp(home: HomeTab()),
    );
  }

  setUp(() {
    authRepository = MockAuthRepository();
    salonRepository = MockSalonRepository();
    bookingRepository = MockBookingRepository();
    when(() => authRepository.me()).thenAnswer(
      (_) async => const AppUser(id: 1, name: 'Test Customer', email: 'customer@example.test', role: 'customer'),
    );
    when(() => bookingRepository.myBookings(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);
  });

  testWidgets('shows "View on Instagram" for a salon with an Instagram URL', (tester) async {
    when(() => salonRepository.mySalons()).thenAnswer(
      (_) async => [
        CustomerSalon.fromJson({
          'tenant_slug': 'prime-hair-studio',
          'salon': {
            'id': 'sal_1',
            'name': 'Prime Hair Studio',
            'slug': 'prime-hair-studio',
            'gender_type': 'unisex',
            'instagram_url': 'https://www.instagram.com/primehairstudio/',
            'address': null,
            'status': 'active',
          },
          'branches': <dynamic>[],
        }),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('View on Instagram'), findsOneWidget);
  });

  testWidgets('hides the Instagram button when the salon has no Instagram URL', (tester) async {
    when(() => salonRepository.mySalons()).thenAnswer(
      (_) async => [
        CustomerSalon.fromJson({
          'tenant_slug': 'prime-hair-studio',
          'salon': {
            'id': 'sal_1',
            'name': 'Prime Hair Studio',
            'slug': 'prime-hair-studio',
            'gender_type': 'unisex',
            'address': null,
            'status': 'active',
          },
          'branches': <dynamic>[],
        }),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Prime Hair Studio'), findsOneWidget);
    expect(find.text('View on Instagram'), findsNothing);
  });

  testWidgets('tapping "View on Instagram" opens the URL through the URL launcher', (tester) async {
    final originalLauncher = UrlLauncherPlatform.instance;
    final fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);

    when(() => salonRepository.mySalons()).thenAnswer(
      (_) async => [
        CustomerSalon.fromJson({
          'tenant_slug': 'prime-hair-studio',
          'salon': {
            'id': 'sal_1',
            'name': 'Prime Hair Studio',
            'slug': 'prime-hair-studio',
            'gender_type': 'unisex',
            'instagram_url': 'https://www.instagram.com/primehairstudio/',
            'address': null,
            'status': 'active',
          },
          'branches': <dynamic>[],
        }),
      ],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('View on Instagram'));
    await tester.pump();

    expect(fakeLauncher.lastLaunchedUrl, 'https://www.instagram.com/primehairstudio/');
  });
}
