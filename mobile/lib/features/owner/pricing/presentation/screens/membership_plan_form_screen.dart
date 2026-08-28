import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../../../membership/data/models/membership_plan.dart';
import '../providers/owner_pricing_providers.dart';

class MembershipPlanFormScreen extends ConsumerWidget {
  const MembershipPlanFormScreen({super.key, this.planId});

  final String? planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (planId == null) {
      return Scaffold(appBar: AppBar(title: const Text('Add membership plan')), body: const _PlanForm());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit membership plan')),
      body: FutureBuilder<MembershipPlan>(
        future: ref.read(ownerMembershipPlanRepositoryProvider).details(planId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (!snapshot.hasData) {
            return ErrorView(message: snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Could not load this plan.');
          }
          return _PlanForm(planId: planId, existing: snapshot.data);
        },
      ),
    );
  }
}

class _PlanForm extends ConsumerStatefulWidget {
  const _PlanForm({this.planId, this.existing});

  final String? planId;
  final MembershipPlan? existing;

  @override
  ConsumerState<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends ConsumerState<_PlanForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _codeController = TextEditingController(text: widget.existing?.code);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late final _priceController = TextEditingController(text: widget.existing?.price.toString());
  late final _durationController = TextEditingController(text: widget.existing?.durationDays.toString());
  late final _valueController = TextEditingController(text: widget.existing?.discountValue.toString());
  late final _maxDiscountController = TextEditingController(text: widget.existing?.maximumDiscountAmount?.toString());
  late String _discountType = widget.existing?.discountType ?? 'percentage';
  late bool _isActive = widget.existing?.isActive ?? true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    _valueController.dispose();
    _maxDiscountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final payload = {
      'name': _nameController.text.trim(),
      'code': _codeController.text.trim(),
      'description': _descriptionController.text.trim(),
      'price': num.tryParse(_priceController.text) ?? 0,
      'duration_days': int.tryParse(_durationController.text) ?? 30,
      'discount_type': _discountType,
      'discount_value': num.tryParse(_valueController.text) ?? 0,
      'maximum_discount_amount': num.tryParse(_maxDiscountController.text),
      'is_active': _isActive,
    };
    try {
      final repository = ref.read(ownerMembershipPlanRepositoryProvider);
      if (widget.planId == null) {
        await repository.create(payload);
      } else {
        await repository.update(widget.planId!, payload);
      }
      ref.invalidate(ownerMembershipPlansProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
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
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Code'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a code' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _descriptionController, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price'),
              validator: (v) => (num.tryParse(v ?? '') == null) ? 'Enter a valid price' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duration (days)'),
              validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a valid number of days' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _discountType,
              decoration: const InputDecoration(labelText: 'Benefit type'),
              items: const [
                DropdownMenuItem(value: 'percentage', child: Text('Percentage off')),
                DropdownMenuItem(value: 'fixed_amount', child: Text('Fixed amount off')),
              ],
              onChanged: (v) => setState(() => _discountType = v ?? 'percentage'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _valueController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Benefit value'),
              validator: (v) => (num.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _maxDiscountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Maximum discount per booking (optional)'),
            ),
            SwitchListTile(
              title: const Text('Active'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', isLoading: _isSubmitting, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
