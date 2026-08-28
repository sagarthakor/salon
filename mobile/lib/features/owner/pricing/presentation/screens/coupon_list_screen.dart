import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../providers/owner_pricing_providers.dart';

class CouponListScreen extends ConsumerWidget {
  const CouponListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couponsAsync = ref.watch(couponsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Coupons')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/owner/coupons/new'),
        child: const Icon(Icons.add),
      ),
      body: couponsAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load coupons.',
          onRetry: () => ref.invalidate(couponsProvider),
        ),
        data: (coupons) {
          if (coupons.isEmpty) {
            return const EmptyView(icon: Icons.sell_outlined, message: 'No coupons yet. Tap + to add one.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(couponsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: coupons.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final coupon = coupons[index];
                return Card(
                  child: ListTile(
                    title: Text('${coupon.code} — ${coupon.name}'),
                    subtitle: Text('${coupon.discountLabel} off · used ${coupon.usageCount}${coupon.usageLimit != null ? '/${coupon.usageLimit}' : ''} times'),
                    trailing: Chip(label: Text(coupon.isActive ? 'Active' : 'Inactive')),
                    onTap: () => context.push('/owner/coupons/${coupon.id}/edit'),
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
