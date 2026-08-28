import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';

/// A single summary-card metric, used across every report's "summary" grid.
class ReportStatCard extends StatelessWidget {
  const ReportStatCard({super.key, required this.label, required this.value, this.icon, this.subtitle});

  final String label;
  final String value;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }
}

/// A responsive wrap of [ReportStatCard]s — every report's summary section
/// uses this so cards lay out consistently regardless of how many there are.
class ReportStatGrid extends StatelessWidget {
  const ReportStatGrid({super.key, required this.cards});

  final List<ReportStatCard> cards;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: cards.map((c) => SizedBox(width: 160, child: c)).toList(),
    );
  }
}
