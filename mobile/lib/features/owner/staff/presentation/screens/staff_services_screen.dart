import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../services/presentation/providers/owner_service_providers.dart';
import '../providers/staff_providers.dart';

class StaffServicesScreen extends ConsumerStatefulWidget {
  const StaffServicesScreen({super.key, required this.staffId});

  final String staffId;

  @override
  ConsumerState<StaffServicesScreen> createState() => _StaffServicesScreenState();
}

class _StaffServicesScreenState extends ConsumerState<StaffServicesScreen> {
  Set<String>? _selected;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _save() async {
    if (_selected == null) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(staffRepositoryProvider).updateServices(widget.staffId, _selected!.toList());
      ref.invalidate(staffServicesProvider(widget.staffId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Services updated.')));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allServicesAsync = ref.watch(allServicesProvider);
    final assignedAsync = ref.watch(staffServicesProvider(widget.staffId));

    return Scaffold(
      appBar: AppBar(title: const Text('Assigned services')),
      body: allServicesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load services.'),
        data: (allServices) => assignedAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load assigned services.'),
          data: (assigned) {
            _selected ??= assigned.map((s) => s.id).toSet();
            if (allServices.isEmpty) {
              return const EmptyView(icon: Icons.content_cut, message: 'No services exist yet.');
            }
            return Column(
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.all(AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: allServices.map((service) {
                      final isSelected = _selected!.contains(service.id);
                      return CheckboxListTile(
                        value: isSelected,
                        title: Text(service.name),
                        subtitle: Text(service.category?.name ?? ''),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selected!.add(service.id);
                          } else {
                            _selected!.remove(service.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: PrimaryButton(label: 'Save', isLoading: _isSubmitting, onPressed: _save),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
