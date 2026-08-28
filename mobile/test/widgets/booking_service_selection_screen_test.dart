import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/booking_service_selection_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/salon/presentation/providers/salon_providers.dart';
import 'package:salon_customer/features/services/data/models/branch_services.dart';
import 'package:salon_customer/features/services/presentation/providers/service_providers.dart';
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

void main() {
  const branch = Branch(id: 'br_1', name: 'Main Branch', slug: 'main', address: Address(), timezone: 'UTC', status: 'active');

  final branchServices = BranchServices.fromJson({
    'categories': [
      {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
    ],
    'services': [
      {
        'id': 'sv_1',
        'branch_id': 'br_1',
        'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
        'name': 'Haircut',
        'slug': 'haircut',
        'gender': 'unisex',
        'price': '300.00',
        'duration_minutes': 30,
        'status': 'active',
        'sort_order': 0,
      },
      {
        'id': 'sv_2',
        'branch_id': 'br_1',
        'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
        'name': 'Beard Trim',
        'slug': 'beard-trim',
        'gender': 'male',
        'price': '150.00',
        'duration_minutes': 20,
        'status': 'active',
        'sort_order': 1,
      },
    ],
  });

  Widget buildApp(MockServiceRepository serviceRepository, {String? audience}) {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        serviceRepositoryProvider.overrideWithValue(serviceRepository),
        selectedBranchProvider.overrideWith((ref) => branch),
        selectedAudienceProvider.overrideWith((ref) => audience),
      ],
      child: const MaterialApp(home: BookingServiceSelectionScreen()),
    );
  }

  testWidgets('lists services grouped by category and lets the customer select more than one', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer((_) async => branchServices);

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    expect(find.text('Hair'), findsOneWidget);
    expect(find.text('Haircut'), findsOneWidget);
    expect(find.text('Beard Trim'), findsOneWidget);
    expect(find.text('Select at least one service'), findsOneWidget);

    await tester.tap(find.text('Haircut'));
    await tester.pump();

    expect(find.textContaining('1 service(s)'), findsOneWidget);
    expect(find.textContaining('₹300'), findsWidgets);

    await tester.tap(find.text('Beard Trim'));
    await tester.pump();

    expect(find.textContaining('2 service(s)'), findsOneWidget);
    expect(find.textContaining('₹450'), findsWidgets);

    final nextButtonFinder = find.widgetWithText(ElevatedButton, 'Next');
    final nextButton = tester.widget<ElevatedButton>(nextButtonFinder);
    expect(nextButton.onPressed, isNotNull);
  });

  testWidgets('shows an empty state when the branch has no bookable services', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer(
      (_) async => BranchServices.fromJson({'categories': <dynamic>[], 'services': <dynamic>[]}),
    );

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    expect(find.text('This branch has no bookable services yet.'), findsOneWidget);
  });

  testWidgets('renders an Image.network pointed at the service image_url', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer(
      (_) async => BranchServices.fromJson({
        'categories': [
          {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
        ],
        'services': [
          {
            'id': 'sv_1',
            'branch_id': 'br_1',
            'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
            'name': 'Haircut',
            'slug': 'haircut',
            'gender': 'unisex',
            'price': '300.00',
            'duration_minutes': 30,
            'image_url': 'https://cdn.example.test/services/haircut.jpg',
            'status': 'active',
            'sort_order': 0,
          },
        ],
      }),
    );

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    // Deliberately not pumping again here: a real HttpClient can't complete
    // in the widget-test sandbox, so a further pump would let the image
    // fail and fall through to the placeholder — this assertion only needs
    // to prove the widget tree was built pointed at the right URL.
    final networkImages = tester
        .widgetList<Image>(find.byType(Image))
        .where((w) => w.image is NetworkImage)
        .map((w) => (w.image as NetworkImage).url);
    expect(networkImages, contains('https://cdn.example.test/services/haircut.jpg'));
  });

  testWidgets('shows a placeholder icon when a service has no image_url', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer(
      (_) async => BranchServices.fromJson({
        'categories': [
          {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
        ],
        'services': [
          {
            'id': 'sv_2',
            'branch_id': 'br_1',
            'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
            'name': 'Beard Trim',
            'slug': 'beard-trim',
            'gender': 'male',
            'price': '150.00',
            'duration_minutes': 20,
            'status': 'active',
            'sort_order': 1,
          },
        ],
      }),
    );

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.content_cut), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows a "Watch Service Video" button only for services with an instagram_url, and tapping it opens the URL', (tester) async {
    final originalLauncher = UrlLauncherPlatform.instance;
    final fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);

    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer(
      (_) async => BranchServices.fromJson({
        'categories': [
          {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
        ],
        'services': [
          {
            'id': 'sv_1',
            'branch_id': 'br_1',
            'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
            'name': 'Haircut',
            'slug': 'haircut',
            'gender': 'unisex',
            'price': '300.00',
            'duration_minutes': 30,
            'instagram_url': 'https://www.instagram.com/reel/Cabc123/',
            'status': 'active',
            'sort_order': 0,
          },
          {
            'id': 'sv_2',
            'branch_id': 'br_1',
            'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Hair', 'slug': 'hair', 'status': 'active', 'sort_order': 0},
            'name': 'Beard Trim',
            'slug': 'beard-trim',
            'gender': 'male',
            'price': '150.00',
            'duration_minutes': 20,
            'status': 'active',
            'sort_order': 1,
          },
        ],
      }),
    );

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    // Only Haircut has an instagram_url — exactly one button, never an
    // empty one for Beard Trim.
    expect(find.text('Watch Service Video'), findsOneWidget);

    await tester.tap(find.text('Watch Service Video'));
    await tester.pump();

    expect(fakeLauncher.lastLaunchedUrl, 'https://www.instagram.com/reel/Cabc123/');
  });

  testWidgets('requests the catalog filtered to the selected audience', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1', audience: 'male')).thenAnswer(
      (_) async => BranchServices.fromJson({
        'categories': [
          {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Beard', 'slug': 'beard', 'status': 'active', 'sort_order': 0},
        ],
        'services': [
          {
            'id': 'sv_2',
            'branch_id': 'br_1',
            'category': {'id': 'cat_1', 'branch_id': 'br_1', 'name': 'Beard', 'slug': 'beard', 'status': 'active', 'sort_order': 0},
            'name': 'Beard Trim',
            'slug': 'beard-trim',
            'gender': 'male',
            'audience': 'male',
            'price': '150.00',
            'duration_minutes': 20,
            'status': 'active',
            'sort_order': 0,
          },
        ],
      }),
    );

    await tester.pumpWidget(buildApp(serviceRepository, audience: 'male'));
    await tester.pump();
    await tester.pump();

    verify(() => serviceRepository.forBranch('br_1', audience: 'male')).called(1);
    expect(find.text('Beard Trim'), findsOneWidget);
    expect(find.text('Main Branch · Men'), findsOneWidget);
  });

  testWidgets('shows a friendly, audience-specific empty state when nothing matches', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1', audience: 'kids')).thenAnswer(
      (_) async => BranchServices.fromJson({'categories': <dynamic>[], 'services': <dynamic>[]}),
    );

    await tester.pumpWidget(buildApp(serviceRepository, audience: 'kids'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('No Kids services here yet'), findsOneWidget);
  });
}
