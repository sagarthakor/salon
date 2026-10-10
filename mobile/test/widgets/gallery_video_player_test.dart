import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:salon_customer/features/gallery/presentation/widgets/gallery_video_player.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Records every platform call so lifecycle (create/dispose/pause) can be
/// asserted without a real player.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform with MockPlatformInterfaceMixin {
  final calls = <String>[];
  bool failCreate = false;
  int _next = 1;
  final _streams = <int, StreamController<VideoEvent>>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    if (failCreate) throw Exception('boom');
    final id = _next++;
    calls.add('create:$id');
    final controller = StreamController<VideoEvent>();
    _streams[id] = controller;
    scheduleMicrotask(() => controller.add(VideoEvent(eventType: VideoEventType.initialized, size: const Size(720, 1280), duration: const Duration(seconds: 10))));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose:$playerId');
    await _streams.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => calls.add('play:$playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause:$playerId');

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox(key: Key('fake-video-view'));

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox(key: Key('fake-video-view'));
}

void main() {
  late FakeVideoPlayerPlatform platform;

  setUp(() {
    platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// The controller's disposal awaits a real stream cancellation, which the
  /// fake-async test clock doesn't drive on its own.
  Future<void> flushDisposal(WidgetTester tester) => tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))).then((_) => settle(tester));

  Widget host(Widget? child) => MaterialApp(home: Scaffold(body: child ?? const SizedBox()));

  testWidgets('initializes one player, autoplays, and disposes it when removed', (tester) async {
    await tester.pumpWidget(host(const GalleryVideoPlayer(url: 'https://x.test/v.mp4')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await settle(tester);

    expect(platform.calls, containsAllInOrder(['create:1', 'play:1']));
    expect(find.byKey(const Key('fake-video-view')), findsOneWidget);

    await tester.pumpWidget(host(null));
    await settle(tester);
    await flushDisposal(tester);
    expect(platform.calls, contains('dispose:1'));
  });

  testWidgets('shows an error with retry when the video cannot be loaded, and retry creates a fresh player', (tester) async {
    platform.failCreate = true;
    await tester.pumpWidget(host(const GalleryVideoPlayer(url: 'https://x.test/v.mp4')));
    await settle(tester);

    expect(find.text('This video could not be played.'), findsOneWidget);

    platform.failCreate = false;
    await tester.tap(find.text('Try again'));
    await settle(tester);

    expect(find.text('This video could not be played.'), findsNothing);
    expect(platform.calls, contains('create:1'));
  });

  testWidgets('tapping toggles pause and resume', (tester) async {
    await tester.pumpWidget(host(const GalleryVideoPlayer(url: 'https://x.test/v.mp4')));
    await settle(tester);

    await tester.tap(find.byKey(const Key('fake-video-view')));
    await tester.pump();
    expect(platform.calls, contains('pause:1'));
    expect(find.byKey(const Key('gallery-play-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gallery-play-button')));
    await tester.pump();
    expect(platform.calls.where((c) => c == 'play:1').length, 2);
  });

  testWidgets('pauses when the app is backgrounded', (tester) async {
    await tester.pumpWidget(host(const GalleryVideoPlayer(url: 'https://x.test/v.mp4')));
    await settle(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(platform.calls, contains('pause:1'));
  });

  testWidgets('disposing while still initializing does not leak the controller', (tester) async {
    await tester.pumpWidget(host(const GalleryVideoPlayer(url: 'https://x.test/v.mp4')));
    // Remove before the initialized event is processed.
    await tester.pumpWidget(host(null));
    await settle(tester);
    await flushDisposal(tester);

    expect(platform.calls.where((c) => c.startsWith('create')).length, platform.calls.where((c) => c.startsWith('dispose')).length);
  });
}
