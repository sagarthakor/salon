import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../booking/data/models/booking_style.dart';
import '../../../booking/presentation/providers/booking_providers.dart';
import '../../../salon/data/models/branch.dart';
import '../../../salon/presentation/providers/salon_providers.dart';
import '../../../services/presentation/providers/service_providers.dart';
import '../../../services/presentation/service_instagram_launcher.dart';
import '../../data/models/gallery_item.dart';
import '../widgets/gallery_thumbnail.dart';
import '../widgets/gallery_video_player.dart';

/// Arguments for the `/gallery/viewer` route (passed as `extra`).
class GalleryViewerArgs {
  const GalleryViewerArgs({required this.item, required this.branch});

  final GalleryItem item;
  final Branch branch;
}

/// Full-screen viewer for one gallery item. A hosted video plays natively;
/// an Instagram-only item shows its thumbnail with an explicit "View on
/// Instagram" action and never a play button.
class GalleryViewerScreen extends ConsumerStatefulWidget {
  const GalleryViewerScreen({super.key, required this.item, required this.branch});

  final GalleryItem item;
  final Branch branch;

  @override
  ConsumerState<GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends ConsumerState<GalleryViewerScreen> {
  bool _fullscreen = false;
  bool _booking = false;

  @override
  void dispose() {
    if (_fullscreen) _applyFullscreen(false);
    super.dispose();
  }

  void _applyFullscreen(bool value) {
    if (value) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    _applyFullscreen(_fullscreen);
  }

  /// "Book This Style": preloads the linked service into the existing
  /// booking flow and continues at the cart. Re-checks the service against
  /// the branch's live catalog so a service that was since deactivated or
  /// deleted never reaches booking.
  Future<void> _bookThisStyle() async {
    final item = widget.item;
    final service = item.service;
    if (_booking) return;
    final style = BookingStyle(mediaId: item.id, label: item.caption, categoryLabel: item.categoryLabel, thumbnailUrl: item.thumbnailUrl);
    // No linked service: start the normal flow at service selection with the
    // style attached, so the customer picks the service themselves.
    if (service == null) {
      ref.read(selectedBranchProvider.notifier).state = widget.branch;
      final flow = ref.read(bookingFlowControllerProvider.notifier);
      flow.selectBranch(widget.branch);
      flow.setStyle(style);
      context.push('/booking/audience');
      return;
    }
    setState(() => _booking = true);
    try {
      final catalog = await ref.read(branchServicesProvider((branchId: widget.branch.id, audience: null)).future);
      final match = catalog.services.where((s) => s.id == service.id).firstOrNull;
      if (!mounted) return;
      if (match == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This service is not available for booking right now.')));
        return;
      }
      ref.read(selectedBranchProvider.notifier).state = widget.branch;
      final flow = ref.read(bookingFlowControllerProvider.notifier);
      flow.selectBranch(widget.branch);
      flow.toggleService(match);
      flow.setStyle(style);
      context.push('/booking/cart');
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _fullscreen
          ? null
          : AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _media(item)),
            if (!_fullscreen) _details(context, item),
          ],
        ),
      ),
    );
  }

  Widget _media(GalleryItem item) {
    if (item.isPlayable) {
      return GalleryVideoPlayer(url: item.videoUrl!, isFullscreen: _fullscreen, onToggleFullscreen: _toggleFullscreen);
    }
    // Instagram-only (or nothing playable): thumbnail only — deliberately no
    // play affordance, since tapping it could not play anything in-app.
    if (item.isPhoto) {
      return InteractiveViewer(
        key: const Key('gallery-photo-viewer'),
        maxScale: 4,
        child: Center(child: GalleryThumbnail(url: item.imageUrl ?? item.thumbnailUrl, fit: BoxFit.contain, iconColor: Colors.white54)),
      );
    }
    return Center(child: GalleryThumbnail(url: item.thumbnailUrl, fit: BoxFit.contain, iconColor: Colors.white54));
  }

  Widget _details(BuildContext context, GalleryItem item) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.categoryLabel != null) Text(item.categoryLabel!, style: theme.textTheme.labelMedium?.copyWith(color: Colors.white70)),
          if (item.caption != null && item.caption!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(item.caption!, maxLines: 4, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white)),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (item.service != null || item.id.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('gallery-book-button'),
                    onPressed: _booking ? null : _bookThisStyle,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_booking ? 'Please wait…' : 'Book This Style'),
                  ),
                ),
              if (item.instagramUrl != null) const SizedBox(width: AppSpacing.sm),
              if (item.instagramUrl != null)
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('gallery-instagram-button'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                    onPressed: () => openInstagramUrl(Uri.parse(item.instagramUrl!)),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View on Instagram'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
