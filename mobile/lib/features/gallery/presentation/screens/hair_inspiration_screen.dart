import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../salon/data/models/branch.dart';
import '../../../salon/presentation/providers/salon_providers.dart';
import '../../data/models/gallery_item.dart';
import '../providers/gallery_providers.dart';
import '../widgets/gallery_thumbnail.dart';
import 'gallery_viewer_screen.dart';

/// "Our Work" / Hair Inspiration: the salon's gallery as a thumbnail grid
/// with category filters and incremental loading. Only thumbnails are built
/// here — no video player is created until the customer opens one item.
class HairInspirationScreen extends ConsumerStatefulWidget {
  const HairInspirationScreen({super.key, required this.salonId, this.salonName});

  final String salonId;
  final String? salonName;

  @override
  ConsumerState<HairInspirationScreen> createState() => _HairInspirationScreenState();
}

class _HairInspirationScreenState extends ConsumerState<HairInspirationScreen> {
  String? _branchId;

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(salonBranchesProvider(widget.salonId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.salonName == null ? 'Hair Inspiration' : '${widget.salonName} · Our Work')),
      body: branchesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: 'Could not load this salon.', onRetry: () => ref.invalidate(salonBranchesProvider(widget.salonId))),
        data: (branches) {
          if (branches.isEmpty) {
            return const EmptyView(icon: Icons.storefront_outlined, message: 'This salon has no active branches right now.');
          }
          final branch = branches.firstWhere((b) => b.id == _branchId, orElse: () => branches.first);
          return Column(
            children: [
              if (branches.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                  child: DropdownButtonFormField<String>(
                    initialValue: branch.id,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: [for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
                    onChanged: (value) => setState(() => _branchId = value),
                  ),
                ),
              Expanded(child: GalleryBrowser(key: ValueKey(branch.id), branch: branch)),
            ],
          );
        },
      ),
    );
  }
}

/// Category chips + paginated grid for one branch.
class GalleryBrowser extends ConsumerStatefulWidget {
  const GalleryBrowser({super.key, required this.branch});

  final Branch branch;

  @override
  ConsumerState<GalleryBrowser> createState() => _GalleryBrowserState();
}

class _GalleryBrowserState extends ConsumerState<GalleryBrowser> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      ref.read(galleryListControllerProvider(widget.branch.id).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(galleryListControllerProvider(widget.branch.id));
    final controller = ref.read(galleryListControllerProvider(widget.branch.id).notifier);

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(label: const Text('All'), selected: state.category == null, onSelected: (_) => controller.setCategory(null)),
              ),
              for (final category in galleryCategories)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(category.label),
                    selected: state.category == category.value,
                    onSelected: (_) => controller.setCategory(category.value),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _body(context, state, controller)),
      ],
    );
  }

  Widget _body(BuildContext context, GalleryListState state, GalleryListController controller) {
    if (state.isLoadingFirstPage) return const LoadingView();
    if (state.error != null) return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
    if (state.items.isEmpty) {
      return EmptyView(
        icon: Icons.video_library_outlined,
        message: state.category == null ? 'No work to show yet. Check back soon!' : 'Nothing in this category yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: controller.loadFirstPage,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.md),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 9 / 14,
              ),
              itemCount: state.items.length,
              itemBuilder: (context, index) => _GalleryTile(
                item: state.items[index],
                onTap: () => context.push('/gallery/viewer', extra: GalleryViewerArgs(item: state.items[index], branch: widget.branch)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: state.isLoadingMore
                  ? const Center(child: CircularProgressIndicator())
                  : state.loadMoreError != null
                  ? ErrorView(message: state.loadMoreError!, onRetry: controller.loadMore)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.item, required this.onTap});

  final GalleryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: item.caption ?? 'Gallery item',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GalleryThumbnail(url: item.thumbnailUrl),
              // Only a hosted video gets a play badge; an Instagram-only
              // item gets an Instagram badge instead, never a fake play.
              Positioned(
                right: 8,
                top: 8,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.black54,
                  child: Icon(item.isPlayable ? Icons.play_arrow : Icons.open_in_new, size: 16, color: Colors.white),
                ),
              ),
              if (item.caption != null && item.caption!.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                    ),
                    child: Text(item.caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
