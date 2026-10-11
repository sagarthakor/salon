import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../data/models/booking_style.dart';

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

/// The gallery style the customer picked via "Book This Style", kept visible
/// at the top of each booking step. [onRemove] lets them drop it (the booking
/// then proceeds without a style); omit it for a read-only display.
class SelectedStyleBanner extends StatelessWidget {
  const SelectedStyleBanner({super.key, required this.style, this.onRemove});

  final BookingStyle style;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('selected-style-banner'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: style.thumbnailUrl == null
                    ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: const Icon(Icons.content_cut))
                    : Image.network(
                        style.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: const Icon(Icons.content_cut)),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your chosen style', style: theme.textTheme.labelSmall),
                  Text(style.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  if (style.categoryLabel != null && style.label != null && style.label!.isNotEmpty)
                    Text(style.categoryLabel!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (onRemove != null) IconButton(key: const Key('selected-style-remove'), tooltip: 'Remove style', onPressed: onRemove, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}
