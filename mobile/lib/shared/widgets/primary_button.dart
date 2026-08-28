import 'package:flutter/material.dart';

/// An [ElevatedButton] that disables itself and shows a spinner while
/// [isLoading] is true — used on every submit action (login, register,
/// confirm booking, cancel, reschedule) so a slow network can't produce a
/// duplicate submission from a second tap.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.isLoading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Text(label),
    );
  }
}
