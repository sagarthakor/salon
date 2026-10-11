import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/brand/brand_config.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Shown instead of any owner/staff UI if an owner or staff account signs
/// into a branded single-salon app (see [BrandConfig]) — that account type
/// isn't supported here at all (the owner/staff routes don't even exist in
/// this build; see `app_router.dart`), so this explains why rather than
/// leaving the customer on a blank or crashing screen. The owner keeps
/// managing the salon through the existing, unmodified multi-tenant app.
class BrandedRoleBlockedScreen extends ConsumerWidget {
  const BrandedRoleBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${BrandConfig.current.appName} is for customers only',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Owner and staff accounts should use the main Salon Booking app to manage this salon.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
