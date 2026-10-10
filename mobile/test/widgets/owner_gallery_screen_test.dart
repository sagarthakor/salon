import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/gallery/data/models/gallery_item.dart';
import 'package:salon_customer/features/owner/gallery/presentation/providers/owner_gallery_providers.dart';
import 'package:salon_customer/features/owner/gallery/presentation/screens/owner_gallery_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockOwnerGalleryRepository repository;

  GalleryItem item(String id, {bool native = false, bool active = true, String? caption}) => GalleryItem.fromJson({
    'id': id,
    'media_type': 'video',
    'caption': caption ?? 'Item $id',
    'has_native_video': native,
    'video_url': native ? 'https://x.test/$id.mp4' : null,
    'instagram_url': native ? null : 'https://www.instagram.com/reel/$id/',
    'thumbnail_url': null,
    'playback': native ? 'native' : 'instagram',
    'source': native ? 'upload' : 'instagram',
    'is_active': active,
  });

  const disconnected = InstagramConnectionStatus(configured: true, connected: false, needsReconnect: false);

  Widget buildApp() {
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => const OwnerGalleryScreen())]);
    return ProviderScope(
      overrides: [secureStorageProvider.overrideWithValue(FakeSecureStorage()), ownerGalleryRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    repository = MockOwnerGalleryRepository();
    when(() => repository.instagramStatus()).thenAnswer((_) async => disconnected);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('lists items and labels hosted video vs Instagram-only and hidden items', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => [item('a', native: true), item('b', active: false)]);

    await tester.pumpWidget(buildApp());
    await settle(tester);

    expect(find.text('Hosted video'), findsOneWidget);
    expect(find.text('Instagram only'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
  });

  testWidgets('shows an empty state', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await settle(tester);

    expect(find.textContaining('No gallery items yet'), findsOneWidget);
  });

  testWidgets('shows an error with retry', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenThrow(const ApiException(message: 'Nope', type: ApiErrorType.server));

    await tester.pumpWidget(buildApp());
    await settle(tester);

    expect(find.text('Nope'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('toggling visibility updates the item via the API', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => [item('a')]);
    when(() => repository.update('a', isActive: false)).thenAnswer((_) async => item('a', active: false));

    await tester.pumpWidget(buildApp());
    await settle(tester);
    await tester.tap(find.byType(Switch));
    await settle(tester);

    verify(() => repository.update('a', isActive: false)).called(1);
    expect(find.text('Hidden'), findsOneWidget);
  });

  testWidgets('not-connected state offers Connect; unconfigured server explains and hides it', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);

    await tester.pumpWidget(buildApp());
    await settle(tester);
    expect(find.text('Connect Instagram'), findsOneWidget);

    when(() => repository.instagramStatus()).thenAnswer((_) async => const InstagramConnectionStatus(configured: false, connected: false, needsReconnect: false));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(buildApp());
    await settle(tester);
    expect(find.text('Connect Instagram'), findsNothing);
    expect(find.textContaining('not set up on this server'), findsOneWidget);
  });

  testWidgets('connected state offers Sync and Disconnect; sync reports the result', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);
    when(() => repository.instagramStatus()).thenAnswer((_) async => const InstagramConnectionStatus(configured: true, connected: true, needsReconnect: false, username: 'nil_hairport_unisex'));
    when(() => repository.instagramSync()).thenAnswer((_) async => const InstagramSyncResult(created: 3, updated: 1, skipped: 0));

    await tester.pumpWidget(buildApp());
    await settle(tester);
    expect(find.textContaining('@nil_hairport_unisex'), findsOneWidget);

    await tester.tap(find.text('Sync now'));
    await settle(tester);

    verify(() => repository.instagramSync()).called(1);
    expect(find.textContaining('3 new, 1 updated'), findsOneWidget);
  });

  testWidgets('an expired connection asks to reconnect instead of syncing', (tester) async {
    when(() => repository.list(page: any(named: 'page'), perPage: any(named: 'perPage'))).thenAnswer((_) async => []);
    when(() => repository.instagramStatus()).thenAnswer(
      (_) async => const InstagramConnectionStatus(configured: true, connected: true, needsReconnect: true, username: 'nil', lastError: 'Authorization expired'),
    );

    await tester.pumpWidget(buildApp());
    await settle(tester);

    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Authorization expired'), findsOneWidget);
  });
}
