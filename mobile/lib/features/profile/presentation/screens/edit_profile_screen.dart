import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/state_views.dart';
import '../providers/profile_providers.dart';

class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(customerProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: profileAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : 'Could not load your profile.',
        ),
        data: (profile) => _EditProfileForm(
          initialName: profile.name,
          initialPhone: profile.phone,
          initialCountryCode: profile.countryCode,
          initialEmail: profile.email,
          initialGender: profile.gender,
          initialDateOfBirth: profile.dateOfBirth,
          initialAddress: profile.address,
        ),
      ),
    );
  }
}

class _EditProfileForm extends ConsumerStatefulWidget {
  const _EditProfileForm({
    required this.initialName,
    required this.initialPhone,
    this.initialCountryCode,
    this.initialEmail,
    this.initialGender,
    this.initialDateOfBirth,
    this.initialAddress,
  });

  final String initialName;
  final String initialPhone;
  final String? initialCountryCode;
  final String? initialEmail;
  final String? initialGender;
  final String? initialDateOfBirth;
  final String? initialAddress;

  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.initialName);
  late final _phoneController = TextEditingController(text: widget.initialPhone);
  late final _countryCodeController = TextEditingController(text: widget.initialCountryCode);
  late final _emailController = TextEditingController(text: widget.initialEmail);
  late final _addressController = TextEditingController(text: widget.initialAddress);
  String? _gender;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>>? _fieldErrors;

  @override
  void initState() {
    super.initState();
    _gender = widget.initialGender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _countryCodeController.dispose();
    _emailController.dispose();
    _addressController.dispose();
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
      await ref
          .read(profileRepositoryProvider)
          .update(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            countryCode: _countryCodeController.text.trim(),
            email: _emailController.text.trim(),
            gender: _gender,
            address: _addressController.text.trim(),
          );
      ref.invalidate(customerProfileProvider);
      if (mounted) Navigator.of(context).pop();
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
              _ErrorBanner(message: _errorMessage!),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Full name', errorText: _fieldErrors?['name']?.first),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Phone', errorText: _fieldErrors?['phone']?.first),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your phone number' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _countryCodeController,
              decoration: const InputDecoration(labelText: 'Country code (e.g. +91)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: 'Email', errorText: _fieldErrors?['email']?.first),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _gender = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _addressController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save changes', isLoading: _isSubmitting, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
