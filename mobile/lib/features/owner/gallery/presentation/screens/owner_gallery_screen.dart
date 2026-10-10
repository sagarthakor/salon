import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../gallery/data/models/gallery_item.dart';
import '../../../../gallery/presentation/widgets/gallery_thumbnail.dart';
import '../providers/owner_gallery_providers.dart';

/// Owner management of the Hair Inspiration gallery: Instagram connection,
/// item list (visibility, reorder, delete) and the entry point for adding
/// items. Reached from the More tab.
class OwnerGalleryScreen extends ConsumerWidget {
  const OwnerGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ownerGalleryControllerProvider);
    final controller = ref.read(ownerGalleryControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Hair inspiration gallery')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'owner-gallery-add',
        onPressed: () async {
          await context.push('/owner/gallery/new');
          controller.load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(instagramConnectionProvider);
          await controller.load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
          children: [
            InstagramConnectionCard(onSynced: controller.load),
            const SizedBox(height: AppSpacing.md),
            Text('Gallery items', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Hosted videos play inside the app. Instagram-only items show a thumbnail with a "View on Instagram" link. Drag to reorder.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (state.isLoading && state.items.isEmpty)
              const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: LoadingView())
            else if (state.error != null && state.items.isEmpty)
              ErrorView(message: state.error!, onRetry: controller.load)
            else if (state.items.isEmpty)
              const EmptyView(icon: Icons.video_library_outlined, message: 'No gallery items yet. Tap Add, or connect Instagram and sync.')
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: true,
                itemCount: state.items.length,
                onReorderItem: (oldIndex, newIndex) async {
                  final error = await controller.move(oldIndex, newIndex);
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                  }
                },
                itemBuilder: (context, index) => _OwnerGalleryTile(key: ValueKey(state.items[index].id), item: state.items[index], index: index),
              ),
          ],
        ),
      ),
    );
  }
}

class _OwnerGalleryTile extends ConsumerWidget {
  const _OwnerGalleryTile({super.key, required this.item, required this.index});

  final GalleryItem item;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(ownerGalleryControllerProvider.notifier);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 56, height: 72, child: GalleryThumbnail(url: item.thumbnailUrl))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.caption?.isNotEmpty == true ? item.caption! : 'No caption',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(item.hasNativeVideo ? Icons.play_circle_outline : Icons.open_in_new, size: 16),
                        label: Text(item.hasNativeVideo ? 'Hosted video' : 'Instagram only'),
                      ),
                      if (!item.isActive) const Chip(visualDensity: VisualDensity.compact, label: Text('Hidden')),
                      if (item.categoryLabel != null) Chip(visualDensity: VisualDensity.compact, label: Text(item.categoryLabel!)),
                      if (item.service != null) Chip(visualDensity: VisualDensity.compact, label: Text(item.service!.name)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Switch(
                  value: item.isActive,
                  onChanged: (value) async {
                    final error = await controller.setActive(item, value);
                    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                  },
                ),
                PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await context.push('/owner/gallery/${item.id}/edit');
                      controller.load();
                    } else if (action == 'delete') {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Remove from gallery?'),
                          content: const Text('Any uploaded video is deleted. The Instagram post itself is not affected.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        final error = await controller.delete(item);
                        if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Connect / sync / disconnect the salon's Instagram Professional account.
/// Authorization happens on Instagram's own page in the browser; the app
/// re-checks the connection when the owner returns to it.
class InstagramConnectionCard extends ConsumerStatefulWidget {
  const InstagramConnectionCard({super.key, this.onSynced});

  final Future<void> Function()? onSynced;

  @override
  ConsumerState<InstagramConnectionCard> createState() => _InstagramConnectionCardState();
}

class _InstagramConnectionCardState extends ConsumerState<InstagramConnectionCard> with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(instagramConnectionProvider);
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
    final url = await ref.read(ownerGalleryRepositoryProvider).instagramConnectUrl();
    final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched && mounted) _snack('Could not open the browser to authorize Instagram.');
    if (launched && mounted) _snack('Approve access on Instagram, then return to this app.');
  });

  Future<void> _sync() => _run(() async {
    final result = await ref.read(ownerGalleryRepositoryProvider).instagramSync();
    ref.invalidate(instagramConnectionProvider);
    await widget.onSynced?.call();
    if (mounted) {
      _snack(
        '${result.created} new, ${result.updated} updated.'
        '${result.created > 0 ? ' New items are hidden until you switch them on.' : ''}',
      );
    }
  });

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Instagram?'),
        content: const Text('The app forgets its access. Gallery items already added stay. You can also remove the app in Instagram → Settings → Apps and websites.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref.read(ownerGalleryRepositoryProvider).instagramDisconnect();
      ref.invalidate(instagramConnectionProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(instagramConnectionProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: statusAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Row(
            children: [
              Expanded(child: Text(error is ApiException ? error.message : 'Could not load the Instagram connection.')),
              TextButton(onPressed: () => ref.invalidate(instagramConnectionProvider), child: const Text('Retry')),
            ],
          ),
          data: (status) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.camera_alt_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Instagram', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!status.connected) ...[
                Text(
                  status.configured
                      ? 'Connect your Instagram Professional (Business or Creator) account to import your reels and posts. Only metadata is imported; videos play on Instagram unless you upload the original.'
                      : 'Instagram connection is not set up on this server yet. You can still add reel links and upload videos.',
                  style: theme.textTheme.bodySmall,
                ),
                if (status.configured) ...[
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(onPressed: _busy ? null : _connect, icon: const Icon(Icons.link), label: const Text('Connect Instagram')),
                ],
              ] else ...[
                Text('Connected${status.username != null ? ' as @${status.username}' : ''}', style: theme.textTheme.bodyMedium),
                if (status.lastSyncedAt != null) Text('Last synced ${status.lastSyncedAt!.split('T').first}', style: theme.textTheme.bodySmall),
                if (status.needsReconnect) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    status.lastError ?? 'Your Instagram authorization has expired. Please reconnect.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    if (status.needsReconnect)
                      FilledButton.icon(onPressed: _busy ? null : _connect, icon: const Icon(Icons.link), label: const Text('Reconnect'))
                    else
                      FilledButton.icon(onPressed: _busy ? null : _sync, icon: const Icon(Icons.sync), label: Text(_busy ? 'Working…' : 'Sync now')),
                    OutlinedButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
