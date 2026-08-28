import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/home/presentation/screens/home_tab.dart';
import 'package:salon_customer/features/salon/data/models/salon.dart';
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

/// Real-device QA bug fix: a brand-new customer with zero salon
/// relationships previously saw an empty "You're not registered as a
/// customer at any salon yet" list. The Home tab now shows every
/// customer-discoverable (active) salon, independent of any prior
/// relationship — see CUSTOMER_ARCHITECTURE.md, "Customer discovery and
/// first-time booking".
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

  Widget buildRoutedApp() {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const HomeTab()),
        GoRoute(
          path: '/salons/:salonId/branches',
          builder: (context, state) => Scaffold(
            body: Text('Branches for ${state.uri.queryParameters['name'] ?? state.pathParameters['salonId']}'),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
        salonRepositoryProvider.overrideWithValue(salonRepository),
        bookingRepositoryProvider.overrideWithValue(bookingRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Salon salonFixture({String id = 'sal_1', String name = 'Prime Hair Studio', String? instagramUrl}) {
    return Salon.fromJson({
      'id': id,
      'name': name,
      'slug': name.toLowerCase().replaceAll(' ', '-'),
      'gender_type': 'unisex',
      'instagram_url': instagramUrl,
      'address': null,
      'status': 'active',
    });
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
    when(() => salonRepository.discoverSalons()).thenAnswer(
      (_) async => [salonFixture(instagramUrl: 'https://www.instagram.com/primehairstudio/')],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('View on Instagram'), findsOneWidget);
  });

  testWidgets('hides the Instagram button when the salon has no Instagram URL', (tester) async {
    when(() => salonRepository.discoverSalons()).thenAnswer((_) async => [salonFixture()]);

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

    when(() => salonRepository.discoverSalons()).thenAnswer(
      (_) async => [salonFixture(instagramUrl: 'https://www.instagram.com/primehairstudio/')],
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('View on Instagram'));
    await tester.pump();

    expect(fakeLauncher.lastLaunchedUrl, 'https://www.instagram.com/primehairstudio/');
  });

  group('real-device bug fix: customer salon discovery', () {
    testWidgets('a brand-new customer with zero salon memberships still sees active salons', (tester) async {
      when(() => salonRepository.discoverSalons()).thenAnswer((_) async => [salonFixture()]);

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      expect(find.text('Prime Hair Studio'), findsOneWidget);
      expect(find.textContaining('not registered as a customer'), findsNothing);
    });

    testWidgets('multiple discovered salons all render', (tester) async {
      when(() => salonRepository.discoverSalons()).thenAnswer(
        (_) async => [salonFixture(id: 'sal_1', name: 'Prime Hair Studio'), salonFixture(id: 'sal_2', name: 'Sunny Unisex Salon')],
      );

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      expect(find.text('Prime Hair Studio'), findsOneWidget);
      expect(find.text('Sunny Unisex Salon'), findsOneWidget);
    });

    testWidgets('an empty salon list shows a friendly empty state, never the old "not registered" message', (tester) async {
      when(() => salonRepository.discoverSalons()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildApp());
      await tester.pump();
      await tester.pump();

      expect(find.text('No salons available near you yet.'), findsOneWidget);
      expect(find.textContaining('not registered as a customer'), findsNothing);
      expect(find.textContaining('Ask your salon to add you'), findsNothing);
    });

    testWidgets('tapping a salon opens branch selection for that salon', (tester) async {
      when(() => salonRepository.discoverSalons()).thenAnswer((_) async => [salonFixture()]);

      await tester.pumpWidget(buildRoutedApp());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Prime Hair Studio'));
      await tester.pumpAndSettle();

      expect(find.text('Branches for Prime Hair Studio'), findsOneWidget);
    });
  });
}
