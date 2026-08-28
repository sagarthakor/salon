import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/network/api_exception.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../shared/widgets/primary_button.dart';
import '../../../../../shared/widgets/state_views.dart';
import '../providers/owner_salon_providers.dart';

/// Editor for the Phase 2 configuration keys plus the Phase 6 booking-engine
/// settings (`App\Enums\SalonSettingKey`) — see BOOKING_ENGINE.md for what
/// each numeric setting controls and its server-side default when unset.
class SalonSettingsScreen extends ConsumerWidget {
  const SalonSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(ownerSalonSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Booking settings')),
      body: settingsAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) {
          // Booking settings live under a Salon that may not exist yet for
          // a brand-new owner still mid-setup (see
          // TenantManagementController::requireSalon() / SalonController::
          // settings()) — never show that raw 404 as an error; this screen
          // is only reachable once a Salon exists anyway (see
          // SalonProfileScreen's settings icon), but this is the last line
          // of defense against ever displaying it.
          if (error is ApiException && error.type == ApiErrorType.notFound) {
            return const ErrorView(message: 'Please set up your salon profile first.');
          }
          return ErrorView(
            message: error is ApiException ? error.message : 'Could not load settings.',
            onRetry: () => ref.invalidate(ownerSalonSettingsProvider),
          );
        },
        data: (settings) => _SettingsForm(existing: settings),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.existing});

  final Map<String, dynamic> existing;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late bool _bookingEnabled;
  late bool _customerBookingEnabled;
  late final _slotIntervalController = TextEditingController(text: '${widget.existing['slot_interval_minutes'] ?? 15}');
  late final _minAdvanceController = TextEditingController(text: '${widget.existing['min_advance_booking_minutes'] ?? 0}');
  late final _maxAdvanceController = TextEditingController(text: '${widget.existing['max_advance_booking_days'] ?? 30}');
  late final _bufferController = TextEditingController(text: '${widget.existing['booking_buffer_minutes'] ?? 0}');
  late final _cancellationWindowController = TextEditingController(
    text: '${widget.existing['cancellation_window_minutes'] ?? 0}',
  );
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bookingEnabled = widget.existing['booking_enabled'] == true;
    _customerBookingEnabled = widget.existing['customer_booking_enabled'] == true;
  }

  @override
  void dispose() {
    _slotIntervalController.dispose();
    _minAdvanceController.dispose();
    _maxAdvanceController.dispose();
    _bufferController.dispose();
    _cancellationWindowController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(ownerSalonRepositoryProvider).updateSettings({
        'booking_enabled': _bookingEnabled,
        'customer_booking_enabled': _customerBookingEnabled,
        'slot_interval_minutes': int.tryParse(_slotIntervalController.text) ?? 15,
        'min_advance_booking_minutes': int.tryParse(_minAdvanceController.text) ?? 0,
        'max_advance_booking_days': int.tryParse(_maxAdvanceController.text) ?? 30,
        'booking_buffer_minutes': int.tryParse(_bufferController.text) ?? 0,
        'cancellation_window_minutes': int.tryParse(_cancellationWindowController.text) ?? 0,
      });
      ref.invalidate(ownerSalonSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings updated.')));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SwitchListTile(
            value: _bookingEnabled,
            onChanged: (v) => setState(() => _bookingEnabled = v),
            title: const Text('Booking enabled'),
          ),
          SwitchListTile(
            value: _customerBookingEnabled,
            onChanged: (v) => setState(() => _customerBookingEnabled = v),
            title: const Text('Customer self-booking enabled'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _slotIntervalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Slot interval (minutes)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _minAdvanceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Minimum advance booking (minutes)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _maxAdvanceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Maximum advance booking (days)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _bufferController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Booking buffer (minutes)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _cancellationWindowController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cancellation window (minutes)'),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'Save', isLoading: _isSubmitting, onPressed: _submit),
        ],
      ),
    );
  }
}
