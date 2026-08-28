import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../branches/presentation/providers/owner_branch_providers.dart';
import '../../data/models/staff_member.dart';
import '../providers/staff_list_controller.dart';
import '../providers/staff_providers.dart';

/// Create when [staffId] is null, edit otherwise. One screen for both to
/// avoid duplicating the form/validation logic.
class StaffFormScreen extends ConsumerWidget {
  const StaffFormScreen({super.key, this.staffId});

  final String? staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (staffId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add staff')),
        body: const _StaffForm(),
      );
    }
    final staffAsync = ref.watch(staffDetailsProvider(staffId!));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit staff')),
      body: staffAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load this staff member.'),
        data: (staff) => _StaffForm(staffId: staffId, existing: staff),
      ),
    );
  }
}

class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm({this.staffId, this.existing});

  final String? staffId;
  final StaffMember? existing;

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _phoneController = TextEditingController(text: widget.existing?.phone);
  late final _emailController = TextEditingController(text: widget.existing?.email);
  late final _bioController = TextEditingController(text: widget.existing?.bio);
  String _gender = 'male';
  String _status = 'active';
  Set<String> _selectedBranchIds = {};
  String? _photoPath;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>>? _fieldErrors;

  @override
  void initState() {
    super.initState();
    _gender = widget.existing?.gender ?? 'male';
    _status = widget.existing?.status ?? 'active';
    _selectedBranchIds = widget.existing?.branches.map((b) => b.id).toSet() ?? {};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (picked != null) setState(() => _photoPath = picked.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = null;
    });
    try {
      final repository = ref.read(staffRepositoryProvider);
      if (widget.staffId == null) {
        await repository.create(
          name: _nameController.text.trim(),
          gender: _gender,
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          bio: _bioController.text.trim(),
          status: _status,
          branchIds: _selectedBranchIds.toList(),
          photoPath: _photoPath,
        );
      } else {
        await repository.update(
          widget.staffId!,
          name: _nameController.text.trim(),
          gender: _gender,
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          bio: _bioController.text.trim(),
          status: _status,
          branchIds: _selectedBranchIds.toList(),
          photoPath: _photoPath,
        );
        ref.invalidate(staffDetailsProvider(widget.staffId!));
      }
      ref.invalidate(staffListControllerProvider);
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
    final branchesAsync = ref.watch(ownerBranchesProvider);

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
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: _photoPath != null
                      ? FileImage(File(_photoPath!))
                      : (widget.existing?.photo != null ? NetworkImage(widget.existing!.photo!) : null) as ImageProvider?,
                  child: (_photoPath == null && widget.existing?.photo == null) ? const Icon(Icons.add_a_photo) : null,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name', errorText: _fieldErrors?['name']?.first),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
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
              onChanged: (v) => setState(() => _gender = v ?? 'male'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Phone', errorText: _fieldErrors?['phone']?.first),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: 'Email', errorText: _fieldErrors?['email']?.first),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _bioController, maxLines: 2, decoration: const InputDecoration(labelText: 'Bio')),
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
            const SizedBox(height: AppSpacing.md),
            Text('Branches', style: Theme.of(context).textTheme.titleSmall),
            branchesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Could not load branches.'),
              data: (branches) => Wrap(
                spacing: AppSpacing.sm,
                children: branches.map((b) {
                  final selected = _selectedBranchIds.contains(b.id);
                  return FilterChip(
                    label: Text(b.name),
                    selected: selected,
                    onSelected: (value) => setState(() {
                      if (value) {
                        _selectedBranchIds.add(b.id);
                      } else {
                        _selectedBranchIds.remove(b.id);
                      }
                    }),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', isLoading: _isSubmitting, onPressed: _submit),
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
