import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../services/data/models/salon_service.dart';
import '../../../branches/presentation/providers/owner_branch_providers.dart';
import '../providers/owner_service_list_controller.dart';
import '../providers/owner_service_providers.dart';

class ServiceFormScreen extends ConsumerWidget {
  const ServiceFormScreen({super.key, this.serviceId});

  final String? serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (serviceId == null) {
      return Scaffold(appBar: AppBar(title: const Text('Add service')), body: const _ServiceForm());
    }
    final serviceAsync = ref.watch(serviceDetailsProvider(serviceId!));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit service')),
      body: serviceAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error is ApiException ? error.message : 'Could not load this service.'),
        data: (service) => _ServiceForm(serviceId: serviceId, existing: service),
      ),
    );
  }
}

class _ServiceForm extends ConsumerStatefulWidget {
  const _ServiceForm({this.serviceId, this.existing});

  final String? serviceId;
  final SalonService? existing;

  @override
  ConsumerState<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends ConsumerState<_ServiceForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late final _priceController = TextEditingController(text: widget.existing?.price.toStringAsFixed(2));
  late final _durationController = TextEditingController(text: widget.existing?.durationMinutes.toString());
  late final _instagramUrlController = TextEditingController(text: widget.existing?.instagramUrl);
  String? _branchId;
  String? _categoryId;
  String _gender = 'unisex';
  String _status = 'active';
  String? _imagePath;
  bool _removeImage = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, List<String>>? _fieldErrors;

  @override
  void initState() {
    super.initState();
    _branchId = widget.existing?.branchId;
    _categoryId = widget.existing?.category?.id;
    _gender = widget.existing?.gender ?? 'unisex';
    _status = widget.existing?.status ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    _instagramUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (picked != null) {
      setState(() {
        _imagePath = picked.path;
        _removeImage = false;
      });
    }
  }

  void _removeExistingImage() {
    setState(() {
      _imagePath = null;
      _removeImage = true;
    });
  }

  ImageProvider? get _imageProvider {
    if (_imagePath != null) return FileImage(File(_imagePath!));
    if (_removeImage) return null;
    final existingUrl = widget.existing?.imageUrl;
    return existingUrl != null ? NetworkImage(existingUrl) : null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _branchId == null || _categoryId == null) {
      setState(() => _errorMessage = (_branchId == null || _categoryId == null) ? 'Select a branch and category.' : null);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = null;
    });
    try {
      final repository = ref.read(ownerServiceRepositoryProvider);
      final duration = int.tryParse(_durationController.text.trim()) ?? 0;
      if (widget.serviceId == null) {
        await repository.createService(
          branchId: _branchId!,
          categoryId: _categoryId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          gender: _gender,
          price: _priceController.text.trim(),
          durationMinutes: duration,
          status: _status,
          imagePath: _imagePath,
          instagramUrl: _instagramUrlController.text.trim(),
        );
      } else {
        await repository.updateService(
          widget.serviceId!,
          branchId: _branchId!,
          categoryId: _categoryId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          gender: _gender,
          price: _priceController.text.trim(),
          durationMinutes: duration,
          status: _status,
          imagePath: _imagePath,
          instagramUrl: _instagramUrlController.text.trim(),
          removeImage: _removeImage,
        );
        ref.invalidate(serviceDetailsProvider(widget.serviceId!));
      }
      ref.invalidate(ownerServiceListControllerProvider);
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
    final categoriesAsync = ref.watch(ownerCategoriesProvider);

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
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 36,
                      onBackgroundImageError: _imageProvider == null ? null : (_, _) {},
                      backgroundImage: _imageProvider,
                      child: _imageProvider == null ? const Icon(Icons.add_a_photo) : null,
                    ),
                  ),
                  if (_imageProvider != null)
                    TextButton(onPressed: _removeExistingImage, child: const Text('Remove photo')),
                ],
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
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Could not load categories.'),
              data: (categories) => DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: InputDecoration(labelText: 'Category', errorText: _fieldErrors?['category_id']?.first),
                items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
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
            TextFormField(
              controller: _instagramUrlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Instagram post/reel URL (optional)',
                hintText: 'https://www.instagram.com/reel/...',
                errorText: _fieldErrors?['instagram_url']?.first,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'unisex', child: Text('Unisex')),
              ],
              onChanged: (v) => setState(() => _gender = v ?? 'unisex'),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Price', errorText: _fieldErrors?['price']?.first),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a price' : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Duration (min)', errorText: _fieldErrors?['duration_minutes']?.first),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a duration' : null,
                  ),
                ),
              ],
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
