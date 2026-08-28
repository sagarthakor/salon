import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/auth/data/models/owner_registration_result.dart';
import 'package:salon_customer/features/auth/data/models/user.dart';
import 'package:salon_customer/features/auth/presentation/providers/auth_provider.dart';
import 'package:salon_customer/features/auth/presentation/screens/register_owner_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockAuthRepository authRepository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(authRepository),
      ],
      child: const MaterialApp(home: RegisterOwnerScreen()),
    );
  }

  setUp(() {
    authRepository = MockAuthRepository();
  });

  Future<void> fillCommonFields(WidgetTester tester, {String salonName = 'Asha Hair Studio'}) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Owner name'), 'Asha Owner');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'asha-owner@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'SecurePassword1!');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'SecurePassword1!');
    await tester.enterText(find.widgetWithText(TextFormField, 'Salon name'), salonName);
  }

  testWidgets('rejects a missing salon name before hitting the API', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.enterText(find.widgetWithText(TextFormField, 'Owner name'), 'Asha Owner');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'asha-owner@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'SecurePassword1!');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'SecurePassword1!');
    await tester.ensureVisible(find.text('Create salon'));
    await tester.tap(find.text('Create salon'));
    await tester.pump();

    expect(find.text('Enter your salon name'), findsOneWidget);
    verifyNever(
      () => authRepository.registerOwner(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        passwordConfirmation: any(named: 'passwordConfirmation'),
        salonName: any(named: 'salonName'),
        slug: any(named: 'slug'),
      ),
    );
  });

  testWidgets('rejects a password shorter than 12 characters', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.enterText(find.widgetWithText(TextFormField, 'Owner name'), 'Asha Owner');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'asha-owner@example.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'short');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'short');
    await tester.enterText(find.widgetWithText(TextFormField, 'Salon name'), 'Asha Hair Studio');
    await tester.ensureVisible(find.text('Create salon'));
    await tester.tap(find.text('Create salon'));
    await tester.pump();

    expect(find.text('Password must be at least 12 characters'), findsOneWidget);
  });

  testWidgets('rejects a mismatched confirmation password', (tester) async {
    await tester.pumpWidget(buildApp());

    await fillCommonFields(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'DifferentPass123!');
    await tester.ensureVisible(find.text('Create salon'));
    await tester.tap(find.text('Create salon'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('registers successfully with valid input, never sending a role or tenant field', (tester) async {
    when(
      () => authRepository.registerOwner(
        name: 'Asha Owner',
        email: 'asha-owner@example.test',
        password: 'SecurePassword1!',
        passwordConfirmation: 'SecurePassword1!',
        salonName: 'Asha Hair Studio',
        slug: null,
      ),
    ).thenAnswer(
      (_) async => const OwnerRegistrationResult(
        user: AppUser(id: 9, name: 'Asha Owner', email: 'asha-owner@example.test', role: 'salon_owner'),
        token: 'owner-token',
        tenantSlug: 'asha-hair-studio',
      ),
    );

    await tester.pumpWidget(buildApp());
    await fillCommonFields(tester);
    await tester.ensureVisible(find.text('Create salon'));
    await tester.tap(find.text('Create salon'));
    await tester.pump();
    await tester.pump();

    verify(
      () => authRepository.registerOwner(
        name: 'Asha Owner',
        email: 'asha-owner@example.test',
        password: 'SecurePassword1!',
        passwordConfirmation: 'SecurePassword1!',
        salonName: 'Asha Hair Studio',
        slug: null,
      ),
    ).called(1);
  });

  testWidgets('sends the optional slug once the advanced section is expanded and filled in', (tester) async {
    when(
      () => authRepository.registerOwner(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        passwordConfirmation: any(named: 'passwordConfirmation'),
        salonName: any(named: 'salonName'),
        slug: any(named: 'slug'),
      ),
    ).thenAnswer(
      (_) async => const OwnerRegistrationResult(
        user: AppUser(id: 9, name: 'Asha Owner', email: 'asha-owner@example.test', role: 'salon_owner'),
        token: 'owner-token',
        tenantSlug: 'my-custom-slug',
      ),
    );

    await tester.pumpWidget(buildApp());
    await fillCommonFields(tester);
    await tester.ensureVisible(find.text('Advanced (salon URL)'));
    await tester.tap(find.text('Advanced (salon URL)'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Salon slug (optional)'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Salon slug (optional)'), 'my-custom-slug');
    await tester.ensureVisible(find.text('Create salon'));
    await tester.tap(find.text('Create salon'));
    await tester.pump();
    await tester.pump();

    verify(
      () => authRepository.registerOwner(
        name: 'Asha Owner',
        email: 'asha-owner@example.test',
        password: 'SecurePassword1!',
        passwordConfirmation: 'SecurePassword1!',
        salonName: 'Asha Hair Studio',
        slug: 'my-custom-slug',
      ),
    ).called(1);
  });

  testWidgets('shows a field-level error when the email is already taken', (tester) async {
    when(
      () => authRepository.registerOwner(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        passwordConfirmation: any(named: 'passwordConfirmation'),
        salonName: any(named: 'salonName'),
        slug: any(named: 'slug'),
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
    await fillCommonFields(tester);
    await tester.ensureVisible(find.text('Create salon'));
    await tester.tap(find.text('Create salon'));
    await tester.pump();
    await tester.pump();

    expect(find.text('The email has already been taken.'), findsOneWidget);
  });

  testWidgets('shows a field-level error when the salon slug is already taken', (tester) async {
    when(
      () => authRepository.registerOwner(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        passwordConfirmation: any(named: 'passwordConfirmation'),
        salonName: any(named: 'salonName'),
        slug: any(named: 'slug'),
      ),
    ).thenThrow(
      const ApiException(
        message: 'The submitted data is invalid.',
        type: ApiErrorType.validation,
        fieldErrors: {
          'slug': ['This salon slug is already taken.'],
        },
      ),
    );

    await tester.pumpWidget(buildApp());
    await fillCommonFields(tester);
    await tester.ensureVisible(find.text('Advanced (salon URL)'));
    await tester.tap(find.text('Advanced (salon URL)'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Salon slug (optional)'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Salon slug (optional)'), 'taken-slug');
    await tester.ensureVisible(find.text('Create salon'));
    await tester.tap(find.text('Create salon'));
    await tester.pump();
    await tester.pump();

    expect(find.text('This salon slug is already taken.'), findsOneWidget);
  });

  testWidgets('shows a generic error banner on a network failure', (tester) async {
    when(
      () => authRepository.registerOwner(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        passwordConfirmation: any(named: 'passwordConfirmation'),
        salonName: any(named: 'salonName'),
        slug: any(named: 'slug'),
      ),
    ).thenThrow(const ApiException(message: 'No internet connection.', type: ApiErrorType.network));

    await tester.pumpWidget(buildApp());
    await fillCommonFields(tester);
    await tester.ensureVisible(find.text('Create salon'));
    await tester.tap(find.text('Create salon'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No internet connection.'), findsOneWidget);
  });
}
