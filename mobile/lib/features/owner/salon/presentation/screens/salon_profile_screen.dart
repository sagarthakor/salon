import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../../../salon/data/models/salon.dart';
import '../providers/owner_salon_providers.dart';

class SalonProfileScreen extends ConsumerWidget {
  const SalonProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salonAsync = ref.watch(ownerSalonProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salon'),
        actions: [
          // Booking Settings requires a Salon to already exist
          // (`SalonController::settings()`) — only ever shown once
          // `ownerSalonProvider` has actually resolved one, so a
          // brand-new owner still filling in Salon Details can never tap
          // into a screen that would 404 on them. See
          // MASTER_CATALOG_ARCHITECTURE.md, "Onboarding UI safety".
          if (salonAsync.hasValue)
            IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/owner/salon/settings')),
        ],
      ),
      body: salonAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) {
          // A brand-new self-registered owner has no Salon yet — the backend
          // reports this as a plain 404 on GET /salon (see
          // TenantManagementController::requireSalon() for why this is a
          // deliberately different, business-level 422 on the branch/service
          // creation paths instead). Never show that raw 404 as an error:
          // this is an expected onboarding state, so offer the create form.
          if (error is ApiException && error.type == ApiErrorType.notFound) {
            return const _SalonForm(existing: null);
          }
          return ErrorView(
            message: error is ApiException ? error.message : 'Could not load salon profile.',
            onRetry: () => ref.invalidate(ownerSalonProvider),
          );
        },
        data: (salon) => _SalonForm(existing: salon),
      ),
    );
  }
}

class _SalonForm extends ConsumerStatefulWidget {
  const _SalonForm({required this.existing});

  final Salon? existing;

  @override
  ConsumerState<_SalonForm> createState() => _SalonFormState();
}

class _SalonFormState extends ConsumerState<_SalonForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late final _phoneController = TextEditingController(text: widget.existing?.phone);
  late final _emailController = TextEditingController(text: widget.existing?.email);
  late final _websiteController = TextEditingController(text: widget.existing?.website);
  late final _instagramUrlController = TextEditingController(text: widget.existing?.instagramUrl);
  late final _addressController = TextEditingController(text: widget.existing?.address.line1);
  late final _cityController = TextEditingController(text: widget.existing?.address.city);
  late String _genderType;
  late String _status;
  bool _isSubmitting = false;
  String? _error;
  Map<String, List<String>>? _fieldErrors;

  bool get _isCreating => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _genderType = widget.existing?.genderType ?? 'unisex';
    _status = widget.existing?.status ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _instagramUrlController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
      _fieldErrors = null;
    });
    try {
      final repository = ref.read(ownerSalonRepositoryProvider);
      if (_isCreating) {
        await repository.create(
          name: _nameController.text.trim(),
          genderType: _genderType,
          description: _descriptionController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          website: _websiteController.text.trim(),
          instagramUrl: _instagramUrlController.text.trim(),
          addressLine1: _addressController.text.trim(),
          city: _cityController.text.trim(),
        );
      } else {
        await repository.update(
          name: _nameController.text.trim(),
          genderType: _genderType,
          description: _descriptionController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          website: _websiteController.text.trim(),
          instagramUrl: _instagramUrlController.text.trim(),
          addressLine1: _addressController.text.trim(),
          city: _cityController.text.trim(),
          status: _status,
        );
      }
      ref.invalidate(ownerSalonProvider);
      if (_isCreating) {
        ref.read(authControllerProvider.notifier).markSalonProfileComplete();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isCreating ? 'Your salon is ready — common services have been added for you! 🎉' : 'Salon updated.'),
          ),
        );
        if (_isCreating) context.go('/owner');
      }
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
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
            if (_isCreating) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  "Let's set up your salon. We'll add a starter branch and common services for you automatically — you can customize everything afterward.",
                  style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Salon name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _descriptionController, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _genderType,
              decoration: const InputDecoration(labelText: 'Serves'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'unisex', child: Text('Unisex')),
              ],
              onChanged: (v) => setState(() => _genderType = v ?? 'unisex'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _websiteController, decoration: const InputDecoration(labelText: 'Website')),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _instagramUrlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Instagram profile (optional)',
                hintText: 'https://www.instagram.com/yoursalon/',
                errorText: _fieldErrors?['instagram_url']?.first,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _cityController, decoration: const InputDecoration(labelText: 'City')),
            const SizedBox(height: AppSpacing.md),
            if (!_isCreating) ...[
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
            ],
            PrimaryButton(
              label: _isCreating ? 'Create salon profile' : 'Save',
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
