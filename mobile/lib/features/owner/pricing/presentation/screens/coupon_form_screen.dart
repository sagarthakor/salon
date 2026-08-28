import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../../data/models/coupon.dart';
import '../providers/owner_pricing_providers.dart';

class CouponFormScreen extends ConsumerWidget {
  const CouponFormScreen({super.key, this.couponId});

  final String? couponId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (couponId == null) {
      return Scaffold(appBar: AppBar(title: const Text('Add coupon')), body: const _CouponForm());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit coupon')),
      body: FutureBuilder<Coupon>(
        future: ref.read(couponRepositoryProvider).details(couponId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (!snapshot.hasData) {
            return ErrorView(message: snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Could not load this coupon.');
          }
          return _CouponForm(couponId: couponId, existing: snapshot.data);
        },
      ),
    );
  }
}

class _CouponForm extends ConsumerStatefulWidget {
  const _CouponForm({this.couponId, this.existing});

  final String? couponId;
  final Coupon? existing;

  @override
  ConsumerState<_CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends ConsumerState<_CouponForm> {
  final _formKey = GlobalKey<FormState>();
  late final _codeController = TextEditingController(text: widget.existing?.code);
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _descriptionController = TextEditingController(text: widget.existing?.description);
  late final _valueController = TextEditingController(text: widget.existing?.discountValue.toString());
  late final _minAmountController = TextEditingController(text: widget.existing?.minimumBookingAmount?.toString());
  late final _maxDiscountController = TextEditingController(text: widget.existing?.maximumDiscountAmount?.toString());
  late final _usageLimitController = TextEditingController(text: widget.existing?.usageLimit?.toString());
  late final _perCustomerLimitController = TextEditingController(text: widget.existing?.usageLimitPerCustomer?.toString());
  late String _discountType = widget.existing?.discountType ?? 'percentage';
  late bool _isActive = widget.existing?.isActive ?? true;
  late bool _firstBookingOnly = widget.existing?.firstBookingOnly ?? false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _minAmountController.dispose();
    _maxDiscountController.dispose();
    _usageLimitController.dispose();
    _perCustomerLimitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final payload = {
      'code': _codeController.text.trim(),
      'name': _nameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'discount_type': _discountType,
      'discount_value': num.tryParse(_valueController.text) ?? 0,
      'minimum_booking_amount': num.tryParse(_minAmountController.text),
      'maximum_discount_amount': num.tryParse(_maxDiscountController.text),
      'usage_limit': int.tryParse(_usageLimitController.text),
      'usage_limit_per_customer': int.tryParse(_perCustomerLimitController.text),
      'is_active': _isActive,
      'first_booking_only': _firstBookingOnly,
    };
    try {
      final repository = ref.read(couponRepositoryProvider);
      if (widget.couponId == null) {
        await repository.create(payload);
      } else {
        await repository.update(widget.couponId!, payload);
      }
      ref.invalidate(couponsProvider);
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
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Code'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a code' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _descriptionController, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _discountType,
              decoration: const InputDecoration(labelText: 'Discount type'),
              items: const [
                DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                DropdownMenuItem(value: 'fixed_amount', child: Text('Fixed amount')),
              ],
              onChanged: (v) => setState(() => _discountType = v ?? 'percentage'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _valueController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Discount value'),
              validator: (v) => (num.tryParse(v ?? '') == null) ? 'Enter a valid number' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _minAmountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minimum booking amount (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _maxDiscountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Maximum discount amount (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _usageLimitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total usage limit (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _perCustomerLimitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Per-customer usage limit (optional)'),
            ),
            SwitchListTile(
              title: const Text('First booking only'),
              value: _firstBookingOnly,
              onChanged: (v) => setState(() => _firstBookingOnly = v),
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
