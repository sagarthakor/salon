import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/presentation/screens/audience_selection_screen.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/salon/presentation/providers/salon_providers.dart';

import '../support/fakes.dart';

/// "What service are you looking for?" — the customer dashboard's
/// Men/Women/Unisex/Kids segmentation entry point, shown right after
/// picking a branch and before the (unchanged) service catalog screen. See
/// MASTER_CATALOG_ARCHITECTURE.md.
void main() {
  const branch = Branch(id: 'br_1', name: 'Main Branch', slug: 'main', address: Address(), timezone: 'UTC', status: 'active');

  Widget buildApp({Branch? selectedBranch = branch}) {
    final router = GoRouter(
      initialLocation: '/audience',
      routes: [
        GoRoute(path: '/audience', builder: (context, state) => const AudienceSelectionScreen()),
        GoRoute(path: '/booking/services', builder: (context, state) => const Scaffold(body: Text('Service catalog'))),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        selectedBranchProvider.overrideWith((ref) => selectedBranch),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('shows Men, Women, Unisex, and Kids as clear, separate choices', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text('Men'), findsOneWidget);
    expect(find.text('Women'), findsOneWidget);
    expect(find.text('Unisex'), findsOneWidget);
    expect(find.text('Kids'), findsOneWidget);
    expect(find.text('What service are you looking for?'), findsOneWidget);
  });

  testWidgets('selecting Men sets the audience and navigates to the service catalog', (tester) async {
    late ProviderContainer container;
    final router = GoRouter(
      initialLocation: '/audience',
      routes: [
        GoRoute(path: '/audience', builder: (context, state) => const AudienceSelectionScreen()),
        GoRoute(path: '/booking/services', builder: (context, state) => const Scaffold(body: Text('Service catalog'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          selectedBranchProvider.overrideWith((ref) => branch),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Men'));
    await tester.pumpAndSettle();

    expect(container.read(selectedAudienceProvider), 'male');
    expect(find.text('Service catalog'), findsOneWidget);
  });

  testWidgets('selecting Kids sets the kids audience', (tester) async {
    // The 2x2 audience grid can push the "Kids" card outside the default
    // 800x600 test surface — use a taller surface instead of relying on
    // GridView scroll mechanics, which don't interact well with `tap()`.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late ProviderContainer container;
    final router = GoRouter(
      initialLocation: '/audience',
      routes: [
        GoRoute(path: '/audience', builder: (context, state) => const AudienceSelectionScreen()),
        GoRoute(path: '/booking/services', builder: (context, state) => const Scaffold(body: Text('Service catalog'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          selectedBranchProvider.overrideWith((ref) => branch),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Kids'));
    await tester.pumpAndSettle();

    expect(container.read(selectedAudienceProvider), 'kids');
  });

  testWidgets('shows a friendly message instead of crashing when no branch was selected', (tester) async {
    await tester.pumpWidget(buildApp(selectedBranch: null));
    await tester.pump();

    expect(find.textContaining('No branch selected'), findsOneWidget);
    expect(find.text('Men'), findsNothing);
  });
}
