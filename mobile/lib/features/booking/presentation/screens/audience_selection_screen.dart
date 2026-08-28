import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../salon/presentation/providers/salon_providers.dart';
import '../../../services/data/models/service_audience.dart';

/// "What service are you looking for?" — the customer dashboard's
/// segmentation entry point, shown right after picking a branch and before
/// the (existing, unchanged) service catalog screen. Four large, clearly
/// labeled buttons — never a dropdown or a screen full of category IDs, per
/// MASTER_CATALOG_ARCHITECTURE.md's accessibility guidance for less
/// tech-savvy owners/customers.
class AudienceSelectionScreen extends ConsumerWidget {
  const AudienceSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(selectedBranchProvider);
    if (branch == null) {
      return const Scaffold(
        body: Center(child: Text('No branch selected. Please go back and choose a branch.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(branch.name)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What service are you looking for?',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                children: ServiceAudience.values.map((audience) => _AudienceCard(audience: audience)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceCard extends ConsumerWidget {
  const _AudienceCard({required this.audience});

  final ServiceAudience audience;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(selectedAudienceProvider.notifier).state = audience.apiValue;
          context.push('/booking/services');
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(audience.emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: AppSpacing.sm),
            Text(audience.label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
