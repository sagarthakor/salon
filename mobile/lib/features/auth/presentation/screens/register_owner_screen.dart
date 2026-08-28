import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';

/// Self-service salon-owner registration — creates a new tenant, starts its
/// trial, and lands the caller in the existing Owner App, all through
/// [AuthController.registerOwner]. No navigation call is made on success:
/// exactly like [RegisterScreen], the router's own redirect logic reacts to
/// [AuthState] becoming authenticated and sends an `ownerAdmin`-role user to
/// `/owner` automatically (see `app_router.dart`) — this screen only needs
/// to know how to fail loudly, not how to navigate on success.
class RegisterOwnerScreen extends ConsumerStatefulWidget {
  const RegisterOwnerScreen({super.key});

  @override
  ConsumerState<RegisterOwnerScreen> createState() => _RegisterOwnerScreenState();
}

class _RegisterOwnerScreenState extends ConsumerState<RegisterOwnerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _salonNameController = TextEditingController();
  final _slugController = TextEditingController();
  bool _showAdvanced = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>>? _fieldErrors;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _salonNameController.dispose();
    _slugController.dispose();
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
          .read(authControllerProvider.notifier)
          .registerOwner(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            passwordConfirmation: _confirmController.text,
            salonName: _salonNameController.text.trim(),
            slug: _slugController.text.trim().isEmpty ? null : _slugController.text.trim(),
          );
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
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Register your salon', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Create your salon and start your free trial',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_errorMessage != null) ...[
                  _buildErrorBanner(context, _errorMessage!),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: 'Owner name', errorText: _fieldErrors?['name']?.first),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter your name' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: 'Email', errorText: _fieldErrors?['email']?.first),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter your email' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 12 characters',
                    errorText: _fieldErrors?['password']?.first,
                  ),
                  validator: (value) =>
                      (value == null || value.length < 12) ? 'Password must be at least 12 characters' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: (value) =>
                      value != _passwordController.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _salonNameController,
                  textInputAction: _showAdvanced ? TextInputAction.next : TextInputAction.done,
                  decoration: InputDecoration(labelText: 'Salon name', errorText: _fieldErrors?['salon_name']?.first),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter your salon name' : null,
                  onFieldSubmitted: _showAdvanced ? null : (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                  icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
                  label: const Text('Advanced (salon URL)'),
                ),
                if (_showAdvanced) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _slugController,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Salon slug (optional)',
                      helperText: 'Leave blank to generate one automatically from the salon name',
                      errorText: _fieldErrors?['slug']?.first,
                    ),
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(label: 'Create salon', isLoading: _isSubmitting, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
