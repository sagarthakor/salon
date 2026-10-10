import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/gallery/data/models/gallery_item.dart';
import 'package:salon_customer/features/gallery/presentation/screens/gallery_viewer_screen.dart';
import 'package:salon_customer/features/gallery/presentation/screens/hair_inspiration_screen.dart';
import 'package:salon_customer/features/gallery/presentation/providers/gallery_providers.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/salon/presentation/providers/salon_providers.dart';

import '../support/fakes.dart';

void main() {
  late MockGalleryRepository gallery;
  late MockSalonRepository salons;

  Branch branch(String id, String name) =>
      Branch.fromJson({'id': id, 'name': name, 'slug': id, 'address': null, 'timezone': 'UTC', 'status': 'active'});

  GalleryItem item(String id, {bool native = true, String? caption}) => GalleryItem.fromJson({
    'id': id,
    'media_type': 'video',
    'caption': caption ?? 'Caption $id',
    'has_native_video': native,
    'video_url': native ? 'https://x.test/$id.mp4' : null,
    'instagram_url': native ? null : 'https://www.instagram.com/reel/$id/',
    'thumbnail_url': null,
    'playback': native ? 'native' : 'instagram',
  });

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/salons/s1/gallery',
      routes: [
        GoRoute(path: '/salons/:salonId/gallery', builder: (c, s) => HairInspirationScreen(salonId: s.pathParameters['salonId']!, salonName: 'Nil')),
        GoRoute(
          path: '/gallery/viewer',
          builder: (c, s) => Scaffold(body: Text('viewer:${(s.extra as GalleryViewerArgs).item.id}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        galleryRepositoryProvider.overrideWithValue(gallery),
        salonRepositoryProvider.overrideWithValue(salons),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    gallery = MockGalleryRepository();
    salons = MockSalonRepository();
    when(() => salons.branchesForSalon('s1')).thenAnswer((_) async => [branch('b1', 'Main')]);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows a loading indicator, then the items with correct per-item badges', (tester) async {
    when(() => gallery.list('b1', page: any(named: 'page'), perPage: any(named: 'perPage'), category: any(named: 'category')))
        .thenAnswer((_) async => [item('a'), item('b', native: false)]);

    await tester.pumpWidget(buildApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await settle(tester);

    expect(find.text('Caption a'), findsOneWidget);
    expect(find.text('Caption b'), findsOneWidget);
    // Only the hosted video gets a play badge; the Instagram-only item gets a link-out badge.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('shows an empty state when the salon has no gallery items', (tester) async {
    when(() => gallery.list('b1', page: any(named: 'page'), perPage: any(named: 'perPage'), category: any(named: 'category'))).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await settle(tester);

    expect(find.textContaining('No work to show yet'), findsOneWidget);
  });

  testWidgets('shows an error with retry, and retry reloads', (tester) async {
    var calls = 0;
    when(() => gallery.list('b1', page: any(named: 'page'), perPage: any(named: 'perPage'), category: any(named: 'category'))).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw const ApiException(message: 'Server unavailable', type: ApiErrorType.server);
      return [item('a')];
    });

    await tester.pumpWidget(buildApp());
    await settle(tester);
    expect(find.text('Server unavailable'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await settle(tester);

    expect(find.text('Caption a'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('choosing a category reloads from page 1 with that filter', (tester) async {
    when(() => gallery.list('b1', page: any(named: 'page'), perPage: any(named: 'perPage'), category: any(named: 'category'))).thenAnswer((_) async => [item('a')]);

    await tester.pumpWidget(buildApp());
    await settle(tester);
    await tester.tap(find.text('Hair Colour'));
    await settle(tester);

    verify(() => gallery.list('b1', page: 1, perPage: galleryPageSize, category: 'hair_colour')).called(1);
  });

  testWidgets('scrolling to the end loads the next page and appends it', (tester) async {
    final firstPage = [for (var i = 0; i < galleryPageSize; i++) item('p1-$i')];
    when(() => gallery.list('b1', page: 1, perPage: any(named: 'perPage'), category: any(named: 'category'))).thenAnswer((_) async => firstPage);
    when(() => gallery.list('b1', page: 2, perPage: any(named: 'perPage'), category: any(named: 'category'))).thenAnswer((_) async => [item('p2-0')]);

    await tester.pumpWidget(buildApp());
    await settle(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await settle(tester);

    verify(() => gallery.list('b1', page: 2, perPage: galleryPageSize, category: null)).called(1);
  });

  testWidgets('tapping a tile opens the viewer for that item', (tester) async {
    when(() => gallery.list('b1', page: any(named: 'page'), perPage: any(named: 'perPage'), category: any(named: 'category'))).thenAnswer((_) async => [item('a')]);

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await settle(tester);
    await tester.tap(find.text('Caption a'));
    await tester.pumpAndSettle();

    expect(find.text('viewer:a'), findsOneWidget);
  });

  testWidgets('a multi-branch salon offers a branch picker', (tester) async {
    when(() => salons.branchesForSalon('s1')).thenAnswer((_) async => [branch('b1', 'Main'), branch('b2', 'Second')]);
    when(() => gallery.list(any(), page: any(named: 'page'), perPage: any(named: 'perPage'), category: any(named: 'category'))).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await settle(tester);

    expect(find.text('Branch'), findsOneWidget);
  });
}
