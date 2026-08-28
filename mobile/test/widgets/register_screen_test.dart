import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/auth/data/models/auth_result.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/auth/presentation/screens/register_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockAuthRepository authRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
      ],
      child: const MaterialApp(home: RegisterScreen()),
    );
  }

  setUp(() {
    authRepository = MockAuthRepository();
  });

  testWidgets('rejects a password shorter than 12 characters before hitting the API', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Rahul Sharma');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'rahul@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'short');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'short');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Password must be at least 12 characters'), findsOneWidget);
    verifyNever(
      () => authRepository.register(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        passwordConfirmation: any(named: 'passwordConfirmation'),
      ),
    );
  });

  testWidgets('rejects a mismatched confirmation password', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Rahul Sharma');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'rahul@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'CustomerPass123!');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'DifferentPass123!');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('registers successfully with valid input', (tester) async {
    when(
      () => authRepository.register(
        name: 'Rahul Sharma',
        email: 'rahul@example.test',
        password: 'CustomerPass123!',
        passwordConfirmation: 'CustomerPass123!',
      ),
    ).thenAnswer(
      (_) async => const AuthResult(
        user: AppUser(id: 3, name: 'Rahul Sharma', email: 'rahul@example.test', role: 'customer'),
        token: 'test-token',
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Rahul Sharma');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'rahul@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'CustomerPass123!');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'CustomerPass123!');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump();

    verify(
      () => authRepository.register(
        name: 'Rahul Sharma',
        email: 'rahul@example.test',
        password: 'CustomerPass123!',
        passwordConfirmation: 'CustomerPass123!',
      ),
    ).called(1);
  });

  testWidgets('shows a field-level error when the email is already taken', (tester) async {
    when(
      () => authRepository.register(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        passwordConfirmation: any(named: 'passwordConfirmation'),
      ),
    ).thenThrow(
      const ApiException(
        message: 'The submitted data is invalid.',
        type: ApiErrorType.validation,
        fieldErrors: {
          'email': ['The email has already been taken.'],
        },
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Rahul Sharma');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'taken@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'CustomerPass123!');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'CustomerPass123!');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump();

    expect(find.text('The email has already been taken.'), findsOneWidget);
  });
}
