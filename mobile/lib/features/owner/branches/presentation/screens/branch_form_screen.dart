import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/constants/timezones.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../salon/data/models/branch.dart';
import '../providers/owner_branch_providers.dart';

class BranchFormScreen extends ConsumerWidget {
  const BranchFormScreen({super.key, this.branchId});

  final String? branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (branchId == null) {
      return Scaffold(appBar: AppBar(title: const Text('Add branch')), body: const _BranchForm());
    }
    final branchAsync = ref.watch(ownerBranchDetailsProvider(branchId!));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit branch')),
      body: branchAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load this branch.'),
        data: (branch) => _BranchForm(branchId: branchId, existing: branch),
      ),
    );
  }
}

class _BranchForm extends ConsumerStatefulWidget {
  const _BranchForm({this.branchId, this.existing});

  final String? branchId;
  final Branch? existing;

  @override
  ConsumerState<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends ConsumerState<_BranchForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _phoneController = TextEditingController(text: widget.existing?.phone);
  late final _emailController = TextEditingController(text: widget.existing?.email);
  late final _addressController = TextEditingController(text: widget.existing?.address.line1);
  late final _cityController = TextEditingController(text: widget.existing?.address.city);
  String _status = 'active';
  late String _timezone;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>>? _fieldErrors;

  @override
  void initState() {
    super.initState();
    _status = widget.existing?.status ?? 'active';
    // See the identical note in salon_profile_screen.dart — this drives
    // AvailabilityService/BookingService's same-day "already past" cutoff,
    // not just a display preference.
    _timezone = widget.existing?.timezone ?? 'Asia/Kolkata';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = null;
    });
    try {
      final repository = ref.read(ownerBranchRepositoryProvider);
      if (widget.branchId == null) {
        await repository.create(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          addressLine1: _addressController.text.trim(),
          city: _cityController.text.trim(),
          timezone: _timezone,
          status: _status,
        );
      } else {
        await repository.update(
          widget.branchId!,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          addressLine1: _addressController.text.trim(),
          city: _cityController.text.trim(),
          timezone: _timezone,
          status: _status,
        );
        ref.invalidate(ownerBranchDetailsProvider(widget.branchId!));
      }
      ref.invalidate(ownerBranchesProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _fieldErrors = e.fieldErrors;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name', errorText: _fieldErrors?['name']?.first),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _cityController, decoration: const InputDecoration(labelText: 'City')),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: kCommonTimezones.contains(_timezone) ? _timezone : kCommonTimezones.first,
              decoration: const InputDecoration(
                labelText: 'Timezone',
                helperText: "Used to work out what's already past for today's bookings — pick where this branch actually operates.",
                helperMaxLines: 2,
              ),
              items: kCommonTimezones.map((tz) => DropdownMenuItem(value: tz, child: Text(tz))).toList(),
              onChanged: (v) => setState(() => _timezone = v ?? _timezone),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', isLoading: _isSubmitting, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
