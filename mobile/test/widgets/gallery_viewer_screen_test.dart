import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/booking/presentation/providers/booking_providers.dart';
import 'package:salon_customer/features/gallery/data/models/gallery_item.dart';
import 'package:salon_customer/features/gallery/presentation/screens/gallery_viewer_screen.dart';
import 'package:salon_customer/features/gallery/presentation/widgets/gallery_video_player.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/services/data/models/branch_services.dart';
import 'package:salon_customer/features/services/presentation/providers/service_providers.dart';

import '../support/fakes.dart';

void main() {
  late MockServiceRepository services;
  final branch = Branch.fromJson({'id': 'b1', 'name': 'Main', 'slug': 'main', 'address': null, 'timezone': 'UTC', 'status': 'active'});

  GalleryItem item({required bool native, Map<String, dynamic>? service, String? instagramUrl}) => GalleryItem.fromJson({
    'id': 'm1',
    'media_type': 'video',
    'caption': 'Layered cut',
    'category_label': 'Haircut',
    'has_native_video': native,
    'video_url': native ? 'https://x.test/v.mp4' : null,
    'instagram_url': instagramUrl,
    'thumbnail_url': null,
    'playback': native ? 'native' : (instagramUrl != null ? 'instagram' : 'none'),
    'service': service,
  });

  Widget buildApp(GalleryItem gi) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (c, s) => GalleryViewerScreen(item: gi, branch: branch)),
        GoRoute(path: '/booking/cart', builder: (c, s) => const Scaffold(body: Text('Cart'))),
      ],
    );
    return ProviderScope(
      overrides: [secureStorageProvider.overrideWithValue(FakeSecureStorage()), serviceRepositoryProvider.overrideWithValue(services)],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() => services = MockServiceRepository());

  testWidgets('an Instagram-only item shows the thumbnail and View on Instagram, with no player or play button', (tester) async {
    await tester.pumpWidget(buildApp(item(native: false, instagramUrl: 'https://www.instagram.com/reel/AAA/')));
    await tester.pump();

    expect(find.byType(GalleryVideoPlayer), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byKey(const Key('gallery-play-button')), findsNothing);
    expect(find.byKey(const Key('gallery-instagram-button')), findsOneWidget);
    expect(find.byKey(const Key('gallery-book-button')), findsNothing);
    expect(find.text('Layered cut'), findsOneWidget);
  });

  testWidgets('a hosted video item builds the native player', (tester) async {
    await tester.pumpWidget(buildApp(item(native: true)));
    await tester.pump();

    expect(find.byType(GalleryVideoPlayer), findsOneWidget);
    expect(find.byKey(const Key('gallery-instagram-button')), findsNothing);
  });

  testWidgets('Book This Style preloads the linked service into the booking flow and opens the cart', (tester) async {
    final catalog = BranchServices.fromJson({
      'categories': [],
      'services': [
        {'id': 's1', 'branch_id': 'b1', 'name': 'Haircut', 'slug': 'haircut', 'gender': 'unisex', 'price': '300.00', 'duration_minutes': 30, 'status': 'active'},
      ],
    });
    when(() => services.forBranch('b1', audience: any(named: 'audience'))).thenAnswer((_) async => catalog);

    await tester.pumpWidget(buildApp(item(native: false, instagramUrl: 'https://www.instagram.com/reel/AAA/', service: {'id': 's1', 'name': 'Haircut'})));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(GalleryViewerScreen)));

    await tester.tap(find.byKey(const Key('gallery-book-button')));
    await tester.pumpAndSettle();

    expect(find.text('Cart'), findsOneWidget);
    final flow = container.read(bookingFlowControllerProvider);
    expect(flow.branch?.id, 'b1');
    expect(flow.selectedServices.map((s) => s.id), ['s1']);
  });

  testWidgets('Book This Style refuses a service that is no longer in the branch catalog', (tester) async {
    when(() => services.forBranch('b1', audience: any(named: 'audience'))).thenAnswer((_) async => BranchServices.fromJson({'categories': [], 'services': []}));

    await tester.pumpWidget(buildApp(item(native: true, service: {'id': 'gone', 'name': 'Old'})));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gallery-book-button')));
    await tester.pumpAndSettle();

    expect(find.text('Cart'), findsNothing);
    expect(find.textContaining('not available for booking'), findsOneWidget);
  });
}
