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

/// Ecommerce-style catalog: services render as cards (image, name,
/// description, price, duration, Add/Added button) instead of a checkbox
/// list; a cart badge in the AppBar and a "View Cart" bottom bar replace the
/// old "N service(s) · Next" summary. See MOBILE_API_INTEGRATION.md,
/// "Customer service catalog redesign".
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

  Finder addButtonFor(String serviceName) => find.descendant(
    of: find.ancestor(of: find.text(serviceName), matching: find.byType(Card)),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );

  testWidgets('renders a card per service with name, description, price, and duration', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer((_) async => branchServices);

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    expect(find.text('Hair'), findsOneWidget);
    expect(find.text('Haircut'), findsOneWidget);
    expect(find.text('Beard Trim'), findsOneWidget);
    expect(find.textContaining('₹300'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.textContaining('₹150'), findsOneWidget);
    expect(find.text('20 min'), findsOneWidget);
    expect(find.text('Add services to get started'), findsOneWidget);
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

  testWidgets('shows a placeholder icon (never a broken image) when a service has no image_url', (tester) async {
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

  testWidgets('tapping Add adds the service to the cart, shown in the bottom bar and the cart badge', (tester) async {
    // The service grid's cards are tall enough that the default 800x600
    // test surface clips their Add button below the fold — use a taller
    // surface instead of relying on GridView scroll mechanics, matching
    // audience_selection_screen_test.dart's established fix for the same
    // limitation.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer((_) async => branchServices);

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    await tester.tap(addButtonFor('Haircut'));
    await tester.pump();

    expect(find.textContaining('1 service · ₹300'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // cart badge

    await tester.tap(addButtonFor('Beard Trim'));
    await tester.pump();

    expect(find.textContaining('2 services · ₹450'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // cart badge

    final viewCartButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'View Cart'));
    expect(viewCartButton.onPressed, isNotNull);
  });

  testWidgets('tapping Added removes the service from the cart', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer((_) async => branchServices);

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    await tester.tap(addButtonFor('Haircut'));
    await tester.pump();
    expect(find.text('Added'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Added'));
    await tester.pump();

    expect(find.text('Added'), findsNothing);
    expect(find.text('Add services to get started'), findsOneWidget);
  });

  testWidgets('the cart button is disabled until at least one service is added', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer((_) async => branchServices);

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    final viewCartButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'View Cart'));
    expect(viewCartButton.onPressed, isNull);
  });

  testWidgets(
    'tapping a service card opens a detail sheet with the "Watch Service Video" button only when instagram_url exists',
    (tester) async {
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

      await tester.tap(find.text('Haircut'));
      await tester.pumpAndSettle();

      expect(find.text('Watch Service Video'), findsOneWidget);
      await tester.ensureVisible(find.text('Watch Service Video'));
      await tester.tap(find.text('Watch Service Video'));
      await tester.pump();
      expect(fakeLauncher.lastLaunchedUrl, 'https://www.instagram.com/reel/Cabc123/');

      Navigator.of(tester.element(find.text('Add to Cart'))).pop();
      await tester.pumpAndSettle();

      // Beard Trim has no instagram_url — its detail sheet must not show the button.
      await tester.tap(find.text('Beard Trim'));
      await tester.pumpAndSettle();
      expect(find.text('Watch Service Video'), findsNothing);
    },
  );

  testWidgets('"Add to Cart" inside the detail sheet adds the service and closes the sheet', (tester) async {
    final serviceRepository = MockServiceRepository();
    when(() => serviceRepository.forBranch('br_1')).thenAnswer((_) async => branchServices);

    await tester.pumpWidget(buildApp(serviceRepository));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Haircut'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add to Cart'));
    await tester.tap(find.text('Add to Cart'));
    await tester.pumpAndSettle();

    expect(find.text('Add to Cart'), findsNothing, reason: 'sheet should have closed');
    expect(find.textContaining('1 service · ₹300'), findsOneWidget);
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
