import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../profile/data/models/customer_profile.dart';
import '../providers/owner_customer_list_controller.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ownerCustomerListControllerProvider);
    final controller = ref.read(ownerCustomerListControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton(
        // Explicit tag required: OwnerShell's IndexedStack keeps this screen
        // mounted alongside StaffListScreen (also a default-tag FAB), so the
        // two default tags collide within that one subtree during animated
        // transitions into /owner ("multiple heroes share the same tag").
        // See OWNER_APP_ARCHITECTURE.md.
        heroTag: 'owner-customer-list-fab',
        onPressed: () => context.push('/owner/customers/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name, phone, or email',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: controller.setSearch,
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (state.isLoadingFirstPage) return const LoadingView();
                if (state.error != null && state.customers.isEmpty) {
                  return ErrorView(message: state.error!, onRetry: controller.loadFirstPage);
                }
                if (state.customers.isEmpty) {
                  return const EmptyView(icon: Icons.people_outline, message: 'No customers found.');
                }
                return RefreshIndicator(
                  onRefresh: controller.loadFirstPage,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (state.hasMore &&
                          !state.isLoadingMore &&
                          notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                        controller.loadMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      itemCount: state.customers.length + (state.hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        if (index >= state.customers.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _CustomerTile(customer: state.customers[index]);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer});

  final CustomerProfile customer;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(customer.name),
        subtitle: Text(customer.phone),
        trailing: Chip(label: Text(customer.status)),
        onTap: () => context.push('/owner/customers/${customer.id}'),
      ),
    );
  }
}
