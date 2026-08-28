import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/models/app_role.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_choice_screen.dart';
import '../../features/auth/presentation/screens/register_owner_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/booking/presentation/screens/audience_selection_screen.dart';
import '../../features/booking/presentation/screens/booking_confirmation_screen.dart';
import '../../features/booking/presentation/screens/booking_details_screen.dart';
import '../../features/booking/presentation/screens/booking_schedule_screen.dart';
import '../../features/booking/presentation/screens/booking_service_selection_screen.dart';
import '../../features/booking/presentation/screens/booking_summary_screen.dart';
import '../../features/booking/presentation/screens/reschedule_screen.dart';
import '../../features/booking/presentation/screens/salon_branch_selection_screen.dart';
import '../../features/home/presentation/screens/home_shell.dart';
import '../../features/loyalty/presentation/screens/loyalty_screen.dart';
import '../../features/membership/presentation/screens/membership_checkout_screen.dart';
import '../../features/membership/presentation/screens/membership_screen.dart';
import '../../features/notifications/presentation/screens/notification_list_screen.dart';
import '../../features/notifications/presentation/screens/notification_preferences_screen.dart';
import '../../features/owner/notifications/presentation/screens/tenant_notification_settings_screen.dart';
import '../../features/owner/reports/presentation/screens/branch_report_screen.dart';
import '../../features/owner/reports/presentation/screens/booking_report_screen.dart';
import '../../features/owner/reports/presentation/screens/coupon_report_screen.dart';
import '../../features/owner/reports/presentation/screens/customer_report_screen.dart';
import '../../features/owner/reports/presentation/screens/loyalty_report_screen.dart';
import '../../features/owner/reports/presentation/screens/membership_report_screen.dart';
import '../../features/owner/reports/presentation/screens/reports_hub_screen.dart';
import '../../features/owner/reports/presentation/screens/reports_overview_screen.dart';
import '../../features/owner/reports/presentation/screens/revenue_report_screen.dart';
import '../../features/owner/reports/presentation/screens/service_report_screen.dart';
import '../../features/owner/reports/presentation/screens/staff_report_screen.dart';
import '../../features/owner/pricing/presentation/screens/coupon_form_screen.dart';
import '../../features/owner/pricing/presentation/screens/coupon_list_screen.dart';
import '../../features/owner/pricing/presentation/screens/loyalty_customer_detail_screen.dart';
import '../../features/owner/pricing/presentation/screens/loyalty_search_screen.dart';
import '../../features/owner/pricing/presentation/screens/membership_plan_form_screen.dart';
import '../../features/owner/pricing/presentation/screens/membership_plan_list_screen.dart';
import '../../features/owner/pricing/presentation/screens/owner_memberships_screen.dart';
import '../../features/owner/bookings/presentation/screens/owner_booking_details_screen.dart';
import '../../features/owner/bookings/presentation/screens/owner_reschedule_screen.dart';
import '../../features/owner/branches/presentation/screens/branch_details_screen.dart';
import '../../features/owner/branches/presentation/screens/branch_form_screen.dart';
import '../../features/owner/branches/presentation/screens/branch_holidays_screen.dart';
import '../../features/owner/branches/presentation/screens/branch_list_screen.dart';
import '../../features/owner/branches/presentation/screens/branch_working_hours_screen.dart';
import '../../features/owner/billing/presentation/screens/invoice_history_screen.dart';
import '../../features/owner/billing/presentation/screens/payment_checkout_screen.dart';
import '../../features/owner/billing/presentation/screens/payment_history_screen.dart';
import '../../features/owner/billing/presentation/screens/plan_selection_screen.dart';
import '../../features/owner/billing/presentation/screens/subscription_screen.dart';
import '../../features/owner/customers/presentation/screens/customer_details_screen.dart';
import '../../features/owner/customers/presentation/screens/customer_form_screen.dart';
import '../../features/owner/customers/presentation/screens/customer_notes_screen.dart';
import '../../features/owner/salon/presentation/screens/salon_profile_screen.dart';
import '../../features/owner/salon/presentation/screens/salon_settings_screen.dart';
import '../../features/owner/services/presentation/screens/category_form_screen.dart';
import '../../features/owner/services/presentation/screens/category_list_screen.dart';
import '../../features/owner/services/presentation/screens/service_form_screen.dart';
import '../../features/owner/services/presentation/screens/service_list_screen.dart';
import '../../features/owner/shell/presentation/screens/owner_shell.dart';
import '../../features/owner/staff/presentation/screens/staff_breaks_screen.dart';
import '../../features/owner/staff/presentation/screens/staff_details_screen.dart';
import '../../features/owner/staff/presentation/screens/staff_form_screen.dart';
import '../../features/owner/staff/presentation/screens/staff_leaves_screen.dart';
import '../../features/owner/staff/presentation/screens/staff_services_screen.dart';
import '../../features/owner/staff/presentation/screens/staff_working_hours_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/staff/presentation/screens/staff_shell.dart';

/// Bridges Riverpod's [authControllerProvider] to go_router's
/// `refreshListenable`, so navigation re-evaluates redirects the instant
/// auth state changes (login, logout, a 401 anywhere in the app) without
/// tearing down and rebuilding the whole [GoRouter].
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authControllerProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}

bool _isOwnerRoute(String location) => location.startsWith('/owner');

bool _isStaffRoute(String location) => location.startsWith('/staff');

/// Customer-only areas that an owner/admin or staff session should not land
/// in — role checks here are navigation-only (see OWNER_APP_ARCHITECTURE.md
/// / STAFF_APP_ARCHITECTURE.md); the backend independently authorizes every
/// request regardless of what screen the app happens to show.
bool _isCustomerOnlyRoute(String location) =>
    location == '/home' ||
    location.startsWith('/salons/') ||
    location.startsWith('/booking/') ||
    location.startsWith('/bookings/') ||
    location == '/profile/edit' ||
    location.startsWith('/membership') ||
    location == '/loyalty';

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final isAuthScreen =
          location == '/login' ||
          location == '/register' ||
          location == '/register-choice' ||
          location == '/register-owner';
      final isSplash = location == '/splash';

      if (auth.status == AuthStatus.unknown) {
        return isSplash ? null : '/splash';
      }
      if (auth.status == AuthStatus.unauthenticated) {
        return isAuthScreen ? null : '/login';
      }

      // authenticated
      final role = AppRole.fromBackendRole(auth.user!.role);
      // A brand-new self-registered owner (hasSalonProfile == false, set by
      // AuthController.registerOwner()) lands on Salon Profile first instead
      // of the dashboard — see "Owner onboarding: salon setup" in
      // OWNER_APP_ARCHITECTURE.md. An existing owner's hasSalonProfile is
      // null (never checked eagerly), so this never affects them.
      final homeFor = switch (role) {
        AppRole.ownerAdmin => auth.hasSalonProfile == false ? '/owner/salon' : '/owner',
        AppRole.customer => '/home',
        AppRole.staff => '/staff',
        AppRole.unknown => '/login',
      };

      if (isAuthScreen || isSplash) return homeFor;

      // Role-aware route guarding — UI/navigation only, never the real
      // authorization boundary (that's the Laravel backend on every request).
      if (role != AppRole.ownerAdmin && _isOwnerRoute(location)) return homeFor;
      if (role != AppRole.staff && _isStaffRoute(location)) return homeFor;
      if (role == AppRole.ownerAdmin && _isCustomerOnlyRoute(location)) return homeFor;
      if (role == AppRole.staff && _isCustomerOnlyRoute(location)) return homeFor;

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/register-choice', builder: (context, state) => const RegisterChoiceScreen()),
      GoRoute(path: '/register-owner', builder: (context, state) => const RegisterOwnerScreen()),

      // --- Customer app (unchanged from Phase 7) ---
      GoRoute(path: '/home', builder: (context, state) => const HomeShell()),
      GoRoute(
        path: '/salons/:salonId/branches',
        builder: (context, state) => SalonBranchSelectionScreen(
          salonId: state.pathParameters['salonId']!,
          salonName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: '/booking/audience', builder: (context, state) => const AudienceSelectionScreen()),
      GoRoute(path: '/booking/services', builder: (context, state) => const BookingServiceSelectionScreen()),
      GoRoute(path: '/booking/schedule', builder: (context, state) => const BookingScheduleScreen()),
      GoRoute(path: '/booking/summary', builder: (context, state) => const BookingSummaryScreen()),
      GoRoute(path: '/booking/confirmation', builder: (context, state) => const BookingConfirmationScreen()),
      GoRoute(
        path: '/bookings/:id',
        builder: (context, state) => BookingDetailsScreen(bookingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/bookings/:id/reschedule',
        builder: (context, state) => RescheduleScreen(bookingId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/profile/edit', builder: (context, state) => const EditProfileScreen()),

      // --- Notifications (Phase 11) — shared across all three roles; every
      // backing endpoint is already scoped to the authenticated user server-side.
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationListScreen()),
      GoRoute(path: '/notifications/preferences', builder: (context, state) => const NotificationPreferencesScreen()),

      // --- Membership / loyalty (Phase 12) — customer-facing ---
      GoRoute(path: '/membership', builder: (context, state) => const MembershipScreen()),
      GoRoute(
        path: '/membership/checkout/:planId',
        builder: (context, state) => MembershipCheckoutScreen(planId: state.pathParameters['planId']!),
      ),
      GoRoute(path: '/loyalty', builder: (context, state) => const LoyaltyScreen()),

      // --- Owner/admin app (Phase 8) ---
      GoRoute(path: '/owner', builder: (context, state) => const OwnerShell()),

      GoRoute(
        path: '/owner/bookings/:id',
        builder: (context, state) => OwnerBookingDetailsScreen(bookingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/bookings/:id/reschedule',
        builder: (context, state) => OwnerRescheduleScreen(bookingId: state.pathParameters['id']!),
      ),

      GoRoute(path: '/owner/staff/new', builder: (context, state) => const StaffFormScreen()),
      GoRoute(
        path: '/owner/staff/:id',
        builder: (context, state) => StaffDetailsScreen(staffId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/staff/:id/edit',
        builder: (context, state) => StaffFormScreen(staffId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/staff/:id/services',
        builder: (context, state) => StaffServicesScreen(staffId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/staff/:id/working-hours',
        builder: (context, state) => StaffWorkingHoursScreen(staffId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/staff/:id/breaks',
        builder: (context, state) => StaffBreaksScreen(staffId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/staff/:id/leaves',
        builder: (context, state) => StaffLeavesScreen(staffId: state.pathParameters['id']!),
      ),

      GoRoute(path: '/owner/customers/new', builder: (context, state) => const CustomerFormScreen()),
      GoRoute(
        path: '/owner/customers/:id',
        builder: (context, state) => CustomerDetailsScreen(customerId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/customers/:id/edit',
        builder: (context, state) => CustomerFormScreen(customerId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/customers/:id/notes',
        builder: (context, state) => CustomerNotesScreen(customerId: state.pathParameters['id']!),
      ),

      GoRoute(path: '/owner/services', builder: (context, state) => const ServiceListScreen()),
      GoRoute(path: '/owner/services/new', builder: (context, state) => const ServiceFormScreen()),
      GoRoute(
        path: '/owner/services/:id/edit',
        builder: (context, state) => ServiceFormScreen(serviceId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/owner/categories', builder: (context, state) => const CategoryListScreen()),
      GoRoute(path: '/owner/categories/new', builder: (context, state) => const CategoryFormScreen()),
      GoRoute(
        path: '/owner/categories/:id/edit',
        builder: (context, state) => CategoryFormScreen(categoryId: state.pathParameters['id']!),
      ),

      GoRoute(path: '/owner/branches', builder: (context, state) => const BranchListScreen()),
      GoRoute(path: '/owner/branches/new', builder: (context, state) => const BranchFormScreen()),
      GoRoute(
        path: '/owner/branches/:id',
        builder: (context, state) => BranchDetailsScreen(branchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/branches/:id/edit',
        builder: (context, state) => BranchFormScreen(branchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/branches/:id/working-hours',
        builder: (context, state) => BranchWorkingHoursScreen(branchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/owner/branches/:id/holidays',
        builder: (context, state) => BranchHolidaysScreen(branchId: state.pathParameters['id']!),
      ),

      GoRoute(path: '/owner/salon', builder: (context, state) => const SalonProfileScreen()),
      GoRoute(path: '/owner/salon/settings', builder: (context, state) => const SalonSettingsScreen()),
      GoRoute(path: '/owner/notification-settings', builder: (context, state) => const TenantNotificationSettingsScreen()),

      // --- Coupons / memberships / loyalty (Phase 12) — owner-only ---
      GoRoute(path: '/owner/coupons', builder: (context, state) => const CouponListScreen()),
      GoRoute(path: '/owner/coupons/new', builder: (context, state) => const CouponFormScreen()),
      GoRoute(
        path: '/owner/coupons/:id/edit',
        builder: (context, state) => CouponFormScreen(couponId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/owner/membership-plans', builder: (context, state) => const MembershipPlanListScreen()),
      GoRoute(path: '/owner/membership-plans/new', builder: (context, state) => const MembershipPlanFormScreen()),
      GoRoute(
        path: '/owner/membership-plans/:id/edit',
        builder: (context, state) => MembershipPlanFormScreen(planId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/owner/memberships', builder: (context, state) => const OwnerMembershipsScreen()),
      GoRoute(path: '/owner/loyalty', builder: (context, state) => const LoyaltySearchScreen()),
      GoRoute(
        path: '/owner/loyalty/:customerId',
        builder: (context, state) => LoyaltyCustomerDetailScreen(customerId: state.pathParameters['customerId']!),
      ),

      // --- Billing / subscription (Phase 10) — always reachable for an
      // owner/admin session regardless of subscription status; see
      // SAAS_BILLING_ARCHITECTURE.md, "Subscription access control".
      GoRoute(path: '/owner/subscription', builder: (context, state) => const SubscriptionScreen()),
      GoRoute(path: '/owner/subscription/plans', builder: (context, state) => const PlanSelectionScreen()),
      GoRoute(
        path: '/owner/subscription/checkout/:planId',
        builder: (context, state) => PaymentCheckoutScreen(planId: state.pathParameters['planId']!),
      ),
      GoRoute(path: '/owner/subscription/payments', builder: (context, state) => const PaymentHistoryScreen()),

      // --- Reports / analytics (Phase 13) — owner-only, reached from the
      // More tab; see REPORTING_ANALYTICS_ARCHITECTURE.md.
      GoRoute(path: '/owner/reports', builder: (context, state) => const ReportsHubScreen()),
      GoRoute(path: '/owner/reports/overview', builder: (context, state) => const ReportsOverviewScreen()),
      GoRoute(path: '/owner/reports/revenue', builder: (context, state) => const RevenueReportScreen()),
      GoRoute(path: '/owner/reports/bookings', builder: (context, state) => const BookingReportScreen()),
      GoRoute(path: '/owner/reports/customers', builder: (context, state) => const CustomerReportScreen()),
      GoRoute(path: '/owner/reports/services', builder: (context, state) => const ServiceReportScreen()),
      GoRoute(path: '/owner/reports/staff', builder: (context, state) => const StaffReportScreen()),
      GoRoute(path: '/owner/reports/branches', builder: (context, state) => const BranchReportScreen()),
      GoRoute(path: '/owner/reports/coupons', builder: (context, state) => const CouponReportScreen()),
      GoRoute(path: '/owner/reports/memberships', builder: (context, state) => const MembershipReportScreen()),
      GoRoute(path: '/owner/reports/loyalty', builder: (context, state) => const LoyaltyReportScreen()),
      GoRoute(path: '/owner/subscription/invoices', builder: (context, state) => const InvoiceHistoryScreen()),

      // --- Staff app (Phase 9) ---
      GoRoute(path: '/staff', builder: (context, state) => const StaffShell()),
      // Booking details/reschedule reuse the owner screens outright — staff and
      // owner share identical booking authorization and UI needs here (see
      // STAFF_APP_ARCHITECTURE.md), so a separate staff-only copy would just be
      // duplication with no behavioral difference.
      GoRoute(
        path: '/staff/appointments/:id',
        builder: (context, state) => OwnerBookingDetailsScreen(bookingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/staff/appointments/:id/reschedule',
        builder: (context, state) => OwnerRescheduleScreen(bookingId: state.pathParameters['id']!),
      ),
    ],
  );
});
