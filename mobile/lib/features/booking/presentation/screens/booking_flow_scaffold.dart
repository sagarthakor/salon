import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/primary_button.dart';

/// The persistent "running summary + next action" bar shown at the bottom of
/// every booking-flow step, so the customer always sees what they've picked
/// so far and the estimated (client-side, informational only) total.
class BookingFlowBottomBar extends StatelessWidget {
  const BookingFlowBottomBar({
    super.key,
    required this.summaryLabel,
    required this.buttonLabel,
    required this.onPressed,
    this.isLoading = false,
  });

  final String summaryLabel;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(summaryLabel, style: Theme.of(context).textTheme.bodyMedium),
            ),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 120,
              child: PrimaryButton(label: buttonLabel, isLoading: isLoading, onPressed: onPressed),
            ),
          ],
        ),
      ),
    );
  }
}
