import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_spacing.dart';

/// Native in-app player for a salon-hosted video. Owns exactly one
/// [VideoPlayerController]: created when this widget is, disposed with it
/// (including if disposal races a still-pending initialize), and paused when
/// the app goes to the background. The gallery grid never builds this widget
/// — only the viewer for the one item the customer opened — so at most one
/// player exists at a time.
class GalleryVideoPlayer extends StatefulWidget {
  const GalleryVideoPlayer({
    super.key,
    required this.url,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    @visibleForTesting this.controllerFactory,
  });

  final String url;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VideoPlayerController Function(Uri uri)? controllerFactory;

  @override
  State<GalleryVideoPlayer> createState() => _GalleryVideoPlayerState();
}

class _GalleryVideoPlayerState extends State<GalleryVideoPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  /// Creates a fresh controller. Never awaits the previous controller's
  /// disposal: after a failed initialize that future may never settle, and a
  /// retry must not hang behind it.
  void _start() {
    final previous = _controller;
    _controller = null;
    if (previous != null) unawaited(previous.dispose());
    _initializing = true;
    _failed = false;

    final uri = Uri.parse(widget.url);
    final controller = widget.controllerFactory?.call(uri) ?? VideoPlayerController.networkUrl(uri);
    _controller = controller;
    _load(controller);
  }

  Future<void> _load(VideoPlayerController controller) async {
    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return; // disposed / replaced; its owner disposes it
      await controller.setLooping(true);
      await controller.play();
      if (!mounted || _controller != controller) return;
      setState(() => _initializing = false);
    } catch (_) {
      if (!mounted || _controller != controller) return;
      setState(() {
        _initializing = false;
        _failed = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _togglePlay(VideoPlayerController controller) {
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: AppSpacing.sm),
            const Text('This video could not be played.', style: TextStyle(color: Colors.white)),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(onPressed: () => setState(_start), child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_initializing || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.hasError) {
          // A mid-playback failure surfaces the same retry state.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_failed) setState(() => _failed = true);
          });
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _togglePlay(controller),
              child: Center(
                child: AspectRatio(aspectRatio: value.aspectRatio == 0 ? 9 / 16 : value.aspectRatio, child: VideoPlayer(controller)),
              ),
            ),
            if (value.isBuffering) const CircularProgressIndicator(),
            if (!value.isPlaying && !value.isBuffering)
              IconButton.filled(
                key: const Key('gallery-play-button'),
                iconSize: 40,
                onPressed: () => _togglePlay(controller),
                icon: const Icon(Icons.play_arrow),
              ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.sm,
              child: Row(
                children: [
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white38),
                    ),
                  ),
                  if (widget.onToggleFullscreen != null)
                    IconButton(
                      key: const Key('gallery-fullscreen-button'),
                      color: Colors.white,
                      onPressed: widget.onToggleFullscreen,
                      icon: Icon(widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
