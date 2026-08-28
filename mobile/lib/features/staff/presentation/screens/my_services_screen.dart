import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../owner/staff/presentation/providers/staff_providers.dart';

/// My Services — the services this staff member is assigned to perform,
/// view-only (assignment is an owner-only action, `PUT /staff/{id}/services`
/// requires `managedTenant()` — see STAFF_APP_ARCHITECTURE.md).
class MyServicesScreen extends ConsumerWidget {
  const MyServicesScreen({super.key, required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(staffServicesProvider(staffId));

    return Scaffold(
      appBar: AppBar(title: const Text('My Services')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(staffServicesProvider(staffId)),
        child: servicesAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: 400,
                child: ErrorView(message: 'Could not load your services.', onRetry: () => ref.invalidate(staffServicesProvider(staffId))),
              ),
            ],
          ),
          data: (services) {
            if (services.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 200, child: EmptyView(icon: Icons.content_cut, message: 'No services assigned to you yet.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: services.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final service = services[index];
                return Card(
                  child: ListTile(
                    title: Text(service.name),
                    subtitle: Text('${service.category?.name ?? ''} · ${service.durationMinutes} min'),
                    trailing: Text('₹${service.price}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
