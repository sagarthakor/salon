import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_exception.dart';
import 'package:salon_customer/features/owner/branches/presentation/providers/owner_branch_providers.dart';
import 'package:salon_customer/features/owner/reports/data/models/revenue_report.dart';
import 'package:salon_customer/features/owner/reports/data/models/report_filter.dart';
import 'package:salon_customer/features/owner/reports/data/repositories/reports_repository.dart';
import 'package:salon_customer/features/owner/reports/presentation/providers/reports_providers.dart';
import 'package:salon_customer/features/owner/reports/presentation/screens/revenue_report_screen.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';

class MockReportsRepository extends Mock implements ReportsRepository {}

void main() {
  late MockReportsRepository repository;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        reportsRepositoryProvider.overrideWithValue(repository),
        ownerBranchesProvider.overrideWith((ref) async => <Branch>[]),
      ],
      child: const MaterialApp(home: RevenueReportScreen()),
    );
  }

  setUpAll(() {
    registerFallbackValue(const ReportFilter());
  });

  setUp(() {
    repository = MockReportsRepository();
  });

  testWidgets('renders real backend summary figures, never a hard-coded placeholder', (tester) async {
    when(() => repository.revenue(any())).thenAnswer(
      (_) async => const RevenueReport(
        summary: RevenueSummary(
          completedBookings: 2,
          grossBookingValue: '1500.00',
          discount: '100.00',
          netRevenue: '1400.00',
          averageBookingValue: '700.00',
        ),
        series: [],
        byBranch: [],
        byStaff: [],
        byService: [],
      ),
    );

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('₹1400.00'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('No data for selected period.'), findsWidgets);
  });

  testWidgets('shows an error view with retry when the report request fails', (tester) async {
    when(() => repository.revenue(any())).thenThrow(const ApiException(message: 'Something went wrong.', type: ApiErrorType.server));

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
