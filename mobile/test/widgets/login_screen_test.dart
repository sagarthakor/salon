import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/auth/data/models/auth_result.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/auth/presentation/screens/login_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockAuthRepository authRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
      ],
      child: const MaterialApp(home: LoginScreen()),
    );
  }

  setUp(() {
    authRepository = MockAuthRepository();
  });

  testWidgets('shows validation errors when submitting an empty form', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    verifyNever(() => authRepository.login(email: any(named: 'email'), password: any(named: 'password')));
  });

  testWidgets('logs in successfully and clears the form error state', (tester) async {
    when(() => authRepository.login(email: 'rahul@example.test', password: 'CustomerPass123!')).thenAnswer(
      (_) async => const AuthResult(
        user: AppUser(id: 3, name: 'Rahul', email: 'rahul@example.test', role: 'customer'),
        token: 'test-token',
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'rahul@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'CustomerPass123!');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    await tester.pump();

    verify(() => authRepository.login(email: 'rahul@example.test', password: 'CustomerPass123!')).called(1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows the backend error message when login fails', (tester) async {
    when(() => authRepository.login(email: any(named: 'email'), password: any(named: 'password'))).thenThrow(
      const ApiException(message: 'Invalid credentials.', type: ApiErrorType.validation),
    );

    await tester.pumpWidget(buildApp());
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'wrong@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrongpassword');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Invalid credentials.'), findsOneWidget);
  });

  testWidgets('disables the submit button while the request is in flight', (tester) async {
    when(() => authRepository.login(email: any(named: 'email'), password: any(named: 'password'))).thenAnswer(
      (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const AuthResult(
          user: AppUser(id: 3, name: 'Rahul', email: 'rahul@example.test', role: 'customer'),
          token: 'test-token',
        );
      },
    );

    await tester.pumpWidget(buildApp());
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'rahul@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'CustomerPass123!');
    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
  });
}
