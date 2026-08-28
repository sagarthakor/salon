import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../branches/presentation/providers/owner_branch_providers.dart';
import '../../data/models/report_filter.dart';
import '../providers/reports_providers.dart';

/// The one filter control every report screen shares — date range preset (or
/// a custom from/to pair) plus, where [showBranchFilter] is true, a branch
/// picker. Selecting a value updates the shared [reportFilterProvider], so
/// every report screen re-fetches with the same filter server-side; nothing
/// is filtered on-device.
class ReportFilterBar extends ConsumerWidget {
  const ReportFilterBar({super.key, this.showBranchFilter = false});

  final bool showBranchFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ReportFilter.presets.map((preset) {
                final selected = filter.range == preset;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: ChoiceChip(
                    label: Text(ReportFilter.presetLabel(preset)),
                    selected: selected,
                    onSelected: (_) => _selectPreset(context, ref, preset),
                  ),
                );
              }).toList(),
            ),
          ),
          if (filter.range == 'custom') ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              filter.from != null && filter.to != null ? '${filter.from} to ${filter.to}' : 'Choose a date range',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (showBranchFilter) ...[
            const SizedBox(height: AppSpacing.sm),
            _BranchFilterDropdown(filter: filter),
          ],
        ],
      ),
    );
  }

  Future<void> _selectPreset(BuildContext context, WidgetRef ref, String preset) async {
    if (preset != 'custom') {
      ref.read(reportFilterProvider.notifier).state = ref.read(reportFilterProvider).copyWith(range: preset);

      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (range == null) return;
    ref.read(reportFilterProvider.notifier).state = ref.read(reportFilterProvider).copyWith(
      range: 'custom',
      from: _formatDate(range.start),
      to: _formatDate(range.end),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _BranchFilterDropdown extends ConsumerWidget {
  const _BranchFilterDropdown({required this.filter});

  final ReportFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(ownerBranchesProvider);

    return branchesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (branches) {
        if (branches.length <= 1) return const SizedBox.shrink();

        return DropdownButtonFormField<String?>(
          initialValue: filter.branchId,
          decoration: const InputDecoration(labelText: 'Branch', isDense: true),
          items: [
            const DropdownMenuItem(value: null, child: Text('All branches')),
            ...branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
          ],
          onChanged: (value) {
            ref.read(reportFilterProvider.notifier).state = filter.copyWith(branchId: value, clearBranchId: value == null);
          },
        );
      },
    );
  }
}
