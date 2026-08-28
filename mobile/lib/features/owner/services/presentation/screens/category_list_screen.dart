import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../providers/owner_service_providers.dart';

class CategoryListScreen extends ConsumerWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(ownerCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/owner/categories/new'),
        child: const Icon(Icons.add),
      ),
      body: categoriesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load categories.',
          onRetry: () => ref.invalidate(ownerCategoriesProvider),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return const EmptyView(icon: Icons.category_outlined, message: 'No categories yet. Tap + to add one.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ownerCategoriesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final category = categories[index];
                return Card(
                  child: ListTile(
                    title: Text(category.name),
                    subtitle: category.description != null ? Text(category.description!) : null,
                    trailing: Chip(label: Text(category.status)),
                    onTap: () => context.push('/owner/categories/${category.id}/edit'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
