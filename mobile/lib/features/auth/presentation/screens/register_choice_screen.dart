import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';

/// The one place a new user picks which of the two, deliberately separate,
/// registration paths they want — reached from [LoginScreen]'s "Register"
/// link instead of going straight to the customer [RegisterScreen]. Neither
/// destination screen changes behavior based on how it was reached; this
/// screen only decides which one to push.
class RegisterChoiceScreen extends StatelessWidget {
  const RegisterChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('How would you like to register?', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xl),
              _ChoiceCard(
                icon: Icons.person_outline,
                title: 'Register as Customer',
                subtitle: 'Book appointments at a salon you already have a relationship with',
                onTap: () => context.push('/register'),
              ),
              const SizedBox(height: AppSpacing.md),
              _ChoiceCard(
                icon: Icons.storefront_outlined,
                title: 'Register your Salon',
                subtitle: 'Create your salon, start your free trial, and manage bookings, staff, and more',
                onTap: () => context.push('/register-owner'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        leading: Icon(icon, size: 32),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
