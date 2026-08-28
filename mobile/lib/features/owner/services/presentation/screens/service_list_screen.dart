import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../services/data/models/salon_service.dart';
import '../../../../services/data/models/service_audience.dart';
import '../providers/owner_service_list_controller.dart';
import '../providers/owner_service_providers.dart';

class ServiceListScreen extends ConsumerWidget {
  const ServiceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ownerServiceListControllerProvider);
    final controller = ref.read(ownerServiceListControllerProvider.notifier);
    final categoriesAsync = ref.watch(ownerCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Services'),
        actions: [
          categoriesAsync.maybeWhen(
            data: (categories) => PopupMenuButton<String?>(
              icon: const Icon(Icons.filter_list),
              onSelected: controller.setCategory,
              itemBuilder: (context) => [
                const PopupMenuItem(value: null, child: Text('All categories')),
                ...categories.map((c) => PopupMenuItem(value: c.id, child: Text(c.name))),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/owner/services/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _AudienceFilterBar(selected: state.audience, onSelected: controller.setAudience),
          Expanded(
            child: Builder(
              builder: (context) {
                if (state.isLoadingFirstPage) return const LoadingView();
                if (state.error != null && state.services.isEmpty) {
                  return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
                }
                if (state.services.isEmpty) {
                  return const EmptyView(icon: Icons.content_cut, message: 'No services yet. Tap + to add one.');
                }
                return RefreshIndicator(
                  onRefresh: controller.loadFirstPage,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (state.hasMore &&
                          !state.isLoadingMore &&
                          notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                        controller.loadMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: state.services.length + (state.hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        if (index >= state.services.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _ServiceTile(service: state.services[index]);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Men / Women / Unisex / Kids" grouping, plus "All" — the same
/// segmentation the customer app uses, so an owner reviewing "what am I
/// offering Men?" sees exactly what a Men customer would. See
/// MASTER_CATALOG_ARCHITECTURE.md.
class _AudienceFilterBar extends StatelessWidget {
  const _AudienceFilterBar({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(label: const Text('All'), selected: selected == null, onSelected: (_) => onSelected(null)),
          ),
          for (final audience in ServiceAudience.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(audience.label),
                selected: selected == audience.apiValue,
                onSelected: (_) => onSelected(audience.apiValue),
              ),
            ),
        ],
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  const _ServiceTile({required this.service});

  final SalonService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: Switch(
          value: service.isActive,
          onChanged: (_) => ref.read(ownerServiceListControllerProvider.notifier).toggleStatus(service),
        ),
        title: Text(service.name),
        subtitle: Text('${service.category?.name ?? ''} · ₹${service.price} · ${service.durationMinutes} min'),
        trailing: TextButton(
          onPressed: () => context.push('/owner/services/${service.id}/edit'),
          child: const Text('Edit'),
        ),
      ),
    );
  }
}
