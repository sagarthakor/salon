import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/brand/brand_config.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../booking/data/models/booking.dart';
import '../../../booking/presentation/providers/booking_providers.dart';
import '../../../salon/data/models/salon.dart';
import '../../../salon/presentation/providers/salon_providers.dart';
import '../../../services/presentation/service_instagram_launcher.dart';

/// Home screen for a branded single-salon app (see [BrandConfig]) — the
/// direct replacement for [HomeTab]'s salon search/discovery list. There is
/// nothing to discover: the salon is fixed, so this screen shows it
/// (logo/name/address/contact) plus the upcoming appointment and a single
/// "Book Now" action that goes straight into the existing, unmodified
/// branch → audience → service-catalog booking flow.
class BrandedHomeTab extends ConsumerWidget {
  const BrandedHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final salonAsync = ref.watch(brandedSalonProvider);
    final upcomingAsync = ref.watch(upcomingBookingProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Hi, ${user?.name.split(' ').first ?? 'there'}')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(brandedSalonProvider);
          ref.invalidate(upcomingBookingProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            salonAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: LoadingView(),
              ),
              error: (error, _) => ErrorView(
                message: 'Could not load salon details.',
                onRetry: () => ref.invalidate(brandedSalonProvider),
              ),
              data: (salon) => _SalonHeaderCard(salon: salon),
            ),
            const SizedBox(height: AppSpacing.sm),
            salonAsync.maybeWhen(
              data: (salon) => Card(
                child: ListTile(
                  key: const Key('our-work-tile'),
                  leading: const Icon(Icons.video_library_outlined),
                  title: const Text('Our Work'),
                  subtitle: const Text('Haircuts, colour & styling inspiration'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    Uri(path: '/salons/${salon.id}/gallery', queryParameters: {'name': salon.name}).toString(),
                  ),
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Upcoming appointment', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            upcomingAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (booking) => booking == null
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'No upcoming appointments yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : _UpcomingBookingCard(booking: booking),
            ),
          ],
        ),
      ),
      floatingActionButton: salonAsync.maybeWhen(
        data: (salon) => FloatingActionButton.extended(
          onPressed: () => context.push(
            Uri(path: '/salons/${salon.id}/branches', queryParameters: {'name': salon.name}).toString(),
          ),
          icon: const Icon(Icons.calendar_month),
          label: const Text('Book Now'),
        ),
        orElse: () => null,
      ),
    );
  }
}

class _SalonHeaderCard extends StatelessWidget {
  const _SalonHeaderCard({required this.salon});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The bundled brand logo (see BrandConfig.logoAssetPath) always
                // takes priority over the salon's own uploaded `logo` — this is
                // the fixed, official Nil Hair Port identity, not whichever
                // photo happens to be set on the Salon record. Falls back to
                // the existing network-logo-then-icon behavior when no bundled
                // asset is configured (i.e. every other brand/the standard app).
                if (BrandConfig.current.logoAssetPath != null)
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.asset(BrandConfig.current.logoAssetPath!, fit: BoxFit.contain),
                      ),
                    ),
                  )
                else
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: salon.logo != null ? NetworkImage(salon.logo!) : null,
                    child: salon.logo == null ? const Icon(Icons.content_cut, size: 28) : null,
                  ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(salon.name, style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            if (salon.description != null && salon.description!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(salon.description!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (!salon.address.isEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(child: Text(salon.address.singleLine, style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ],
            if (salon.phone != null && salon.phone!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.call_outlined, size: 16, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(salon.phone!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
            if (salon.instagramUrl != null) ...[
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: () => openInstagramUrl(Uri.parse(salon.instagramUrl!)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'View on Instagram',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UpcomingBookingCard extends StatelessWidget {
  const _UpcomingBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_available),
        title: Text('${booking.bookingDate} at ${booking.startTime}'),
        subtitle: Text(booking.status.label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => GoRouter.of(context).push('/bookings/${booking.id}'),
      ),
    );
  }
}
