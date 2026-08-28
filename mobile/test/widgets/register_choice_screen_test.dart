import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:salon_customer/features/auth/presentation/screens/register_choice_screen.dart';

void main() {
  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/register-choice',
      routes: [
        GoRoute(path: '/register-choice', builder: (context, state) => const RegisterChoiceScreen()),
        GoRoute(path: '/register', builder: (context, state) => const Scaffold(body: Text('Customer register screen'))),
        GoRoute(path: '/register-owner', builder: (context, state) => const Scaffold(body: Text('Owner register screen'))),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('offers two clearly distinct registration paths', (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.text('Register as Customer'), findsOneWidget);
    expect(find.text('Register your Salon'), findsOneWidget);
  });

  testWidgets('tapping "Register as Customer" navigates to the customer register screen', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.text('Register as Customer'));
    await tester.pumpAndSettle();

    expect(find.text('Customer register screen'), findsOneWidget);
  });

  testWidgets('tapping "Register your Salon" navigates to the owner register screen', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.text('Register your Salon'));
    await tester.pumpAndSettle();

    expect(find.text('Owner register screen'), findsOneWidget);
  });
}
