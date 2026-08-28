import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../booking/data/models/booking.dart';
import '../../../booking/presentation/providers/booking_providers.dart';
import '../../../salon/data/models/salon.dart';
import '../../../salon/presentation/providers/salon_providers.dart';
import '../../../services/presentation/service_instagram_launcher.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final salonsAsync = ref.watch(discoverSalonsProvider);
    final upcomingAsync = ref.watch(upcomingBookingProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Hi, ${user?.name.split(' ').first ?? 'there'}')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(discoverSalonsProvider);
          ref.invalidate(upcomingBookingProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
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
            const SizedBox(height: AppSpacing.lg),
            Text('Find a Salon', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(labelText: 'Search salons', prefixIcon: Icon(Icons.search)),
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: AppSpacing.sm),
            salonsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: LoadingView(),
              ),
              error: (error, _) => ErrorView(
                message: 'Could not load salons.',
                onRetry: () => ref.invalidate(discoverSalonsProvider),
              ),
              data: (salons) {
                final filtered = _query.isEmpty
                    ? salons
                    : salons.where((s) => s.name.toLowerCase().contains(_query)).toList();
                if (filtered.isEmpty) {
                  return EmptyView(
                    icon: Icons.storefront_outlined,
                    message: salons.isEmpty
                        ? 'No salons available near you yet.'
                        : 'No salons match "$_query".',
                  );
                }

                return Column(
                  children: filtered.map((salon) => _SalonCard(salon: salon)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SalonCard extends StatelessWidget {
  const _SalonCard({required this.salon});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          Uri(path: '/salons/${salon.id}/branches', queryParameters: {'name': salon.name}).toString(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (salon.logo != null) ...[
                    CircleAvatar(backgroundImage: NetworkImage(salon.logo!), radius: 20),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(child: Text(salon.name, style: Theme.of(context).textTheme.titleMedium)),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (salon.description != null && salon.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(salon.description!, style: Theme.of(context).textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              if (!salon.address.isEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(child: Text(salon.address.singleLine, style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ],
              if (salon.instagramUrl != null) ...[
                const SizedBox(height: 4),
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
