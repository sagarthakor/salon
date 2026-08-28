import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../services/data/models/service_category.dart';
import '../../../branches/presentation/providers/owner_branch_providers.dart';
import '../providers/owner_service_providers.dart';

class CategoryFormScreen extends ConsumerWidget {
  const CategoryFormScreen({super.key, this.categoryId});

  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categoryId == null) {
      return Scaffold(appBar: AppBar(title: const Text('Add category')), body: const _CategoryForm());
    }
    final categoriesAsync = ref.watch(ownerCategoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit category')),
      body: categoriesAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load this category.'),
        data: (categories) {
          final existing = categories.where((c) => c.id == categoryId).toList();
          if (existing.isEmpty) return const ErrorView(message: 'Category not found.');
          return _CategoryForm(categoryId: categoryId, existing: existing.first);
        },
      ),
    );
  }
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.categoryId, this.existing});

  final String? categoryId;
  final ServiceCategory? existing;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  String? _branchId;
  String _status = 'active';
  String? _imagePath;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _branchId = widget.existing?.branchId;
    _status = widget.existing?.status ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (picked != null) setState(() => _imagePath = picked.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _branchId == null) {
      setState(() => _errorMessage = _branchId == null ? 'Select a branch.' : null);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final repository = ref.read(ownerServiceRepositoryProvider);
      if (widget.categoryId == null) {
        await repository.createCategory(
          branchId: _branchId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          status: _status,
          imagePath: _imagePath,
        );
      } else {
        await repository.updateCategory(
          widget.categoryId!,
          branchId: _branchId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          status: _status,
          imagePath: _imagePath,
        );
      }
      ref.invalidate(ownerCategoriesProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
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
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: _imagePath != null
                      ? FileImage(File(_imagePath!))
                      : (widget.existing?.image != null ? NetworkImage(widget.existing!.image!) : null) as ImageProvider?,
                  child: (_imagePath == null && widget.existing?.image == null) ? const Icon(Icons.add_a_photo) : null,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            branchesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Could not load branches.'),
              data: (branches) => DropdownButtonFormField<String>(
                initialValue: _branchId,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                onChanged: (v) => setState(() => _branchId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _descriptionController, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
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
