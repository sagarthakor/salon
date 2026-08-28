import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/core/providers.dart';
import 'package:salon_customer/features/owner/branches/presentation/providers/owner_branch_providers.dart';
import 'package:salon_customer/features/owner/staff/data/models/staff_member.dart';
import 'package:salon_customer/features/owner/staff/presentation/providers/staff_providers.dart';
import 'package:salon_customer/features/owner/staff/presentation/screens/staff_form_screen.dart';

import '../support/fakes.dart';

void main() {
  late MockStaffRepository staffRepository;

  late GoRouter router;

  Widget buildApp({String? staffId}) {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('behind'))),
        GoRoute(path: '/form', builder: (context, state) => StaffFormScreen(staffId: staffId)),
      ],
    );
    return ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        staffRepositoryProvider.overrideWithValue(staffRepository),
        ownerBranchesProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    staffRepository = MockStaffRepository();
  });

  testWidgets('requires a name before submitting a new staff member', (tester) async {
    await tester.pumpWidget(buildApp());
    router.push('/form');
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Enter a name'), findsOneWidget);
    verifyNever(
      () => staffRepository.create(
        name: any(named: 'name'),
        gender: any(named: 'gender'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        bio: any(named: 'bio'),
        status: any(named: 'status'),
        branchIds: any(named: 'branchIds'),
        photoPath: any(named: 'photoPath'),
      ),
    );
  });

  testWidgets('creates a staff member with the entered name and default gender/status', (tester) async {
    when(
      () => staffRepository.create(
        name: any(named: 'name'),
        gender: any(named: 'gender'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        bio: any(named: 'bio'),
        status: any(named: 'status'),
        branchIds: any(named: 'branchIds'),
        photoPath: any(named: 'photoPath'),
      ),
    ).thenAnswer((_) async => const StaffMember(id: 'stf-1', name: 'New Stylist', gender: 'male', status: 'active'));

    await tester.pumpWidget(buildApp());
    router.push('/form');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'New Stylist');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    verify(
      () => staffRepository.create(
        name: 'New Stylist',
        gender: 'male',
        phone: '',
        email: '',
        bio: '',
        status: 'active',
        branchIds: <String>[],
        photoPath: null,
      ),
    ).called(1);
  });

  testWidgets('editing an existing staff member pre-fills the form and calls update', (tester) async {
    when(() => staffRepository.details('stf-2')).thenAnswer(
      (_) async => const StaffMember(id: 'stf-2', name: 'Existing Stylist', phone: '9000000000', gender: 'female', status: 'active'),
    );
    when(
      () => staffRepository.update(
        'stf-2',
        name: any(named: 'name'),
        gender: any(named: 'gender'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        bio: any(named: 'bio'),
        status: any(named: 'status'),
        branchIds: any(named: 'branchIds'),
        photoPath: any(named: 'photoPath'),
      ),
    ).thenAnswer(
      (_) async => const StaffMember(id: 'stf-2', name: 'Existing Stylist Updated', gender: 'female', status: 'active'),
    );

    await tester.pumpWidget(buildApp(staffId: 'stf-2'));
    router.push('/form');
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    final nameField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Name'));
    expect(nameField.controller!.text, 'Existing Stylist');

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Existing Stylist Updated');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    verify(
      () => staffRepository.update(
        'stf-2',
        name: 'Existing Stylist Updated',
        gender: 'female',
        phone: '9000000000',
        email: '',
        bio: '',
        status: 'active',
        branchIds: <String>[],
        photoPath: null,
      ),
    ).called(1);
  });

  testWidgets('shows the backend field-level error under the offending field', (tester) async {
    when(
      () => staffRepository.create(
        name: any(named: 'name'),
        gender: any(named: 'gender'),
        phone: any(named: 'phone'),
        email: any(named: 'email'),
        bio: any(named: 'bio'),
        status: any(named: 'status'),
        branchIds: any(named: 'branchIds'),
        photoPath: any(named: 'photoPath'),
      ),
    ).thenThrow(
      const ApiException(
        message: 'The given data was invalid.',
        type: ApiErrorType.validation,
        fieldErrors: {
          'email': ['That email is already in use.'],
        },
      ),
    );

    await tester.pumpWidget(buildApp());
    router.push('/form');
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Dup Name');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();

    expect(find.text('That email is already in use.'), findsOneWidget);
  });
}
