<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\AvailabilityController;
use App\Http\Controllers\Api\V1\BookingController;
use App\Http\Controllers\Api\V1\BranchController;
use App\Http\Controllers\Api\V1\BranchHolidayController;
use App\Http\Controllers\Api\V1\BranchWorkingHourController;
use App\Http\Controllers\Api\V1\CouponController;
use App\Http\Controllers\Api\V1\CustomerBookingController;
use App\Http\Controllers\Api\V1\CustomerController;
use App\Http\Controllers\Api\V1\CustomerLoyaltyController;
use App\Http\Controllers\Api\V1\CustomerMembershipController;
use App\Http\Controllers\Api\V1\CustomerNoteController;
use App\Http\Controllers\Api\V1\CustomerProfileController;
use App\Http\Controllers\Api\V1\CustomerSalonController;
use App\Http\Controllers\Api\V1\CustomerServiceController;
use App\Http\Controllers\Api\V1\DashboardController;
use App\Http\Controllers\Api\V1\DeviceTokenController;
use App\Http\Controllers\Api\V1\LoyaltyManagementController;
use App\Http\Controllers\Api\V1\MembershipManagementController;
use App\Http\Controllers\Api\V1\MembershipPlanController;
use App\Http\Controllers\Api\V1\NotificationController;
use App\Http\Controllers\Api\V1\NotificationPreferenceController;
use App\Http\Controllers\Api\V1\PaymentWebhookController;
use App\Http\Controllers\Api\V1\PlanController;
use App\Http\Controllers\Api\V1\ReportController;
use App\Http\Controllers\Api\V1\SalonController;
use App\Http\Controllers\Api\V1\ServiceCategoryController;
use App\Http\Controllers\Api\V1\ServiceController;
use App\Http\Controllers\Api\V1\StaffBreakController;
use App\Http\Controllers\Api\V1\StaffController;
use App\Http\Controllers\Api\V1\StaffLeaveController;
use App\Http\Controllers\Api\V1\StaffServiceController;
use App\Http\Controllers\Api\V1\StaffWorkingHourController;
use App\Http\Controllers\Api\V1\SubscriptionController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function (): void {
    Route::prefix('auth')->middleware('throttle:auth')->group(function (): void {
        Route::post('register', [AuthController::class, 'register']);
        // Self-service salon-owner registration — creates a new tenant and
        // its owner membership; see OwnerRegistrationService. Deliberately
        // its own endpoint, never a mode/flag on `register` above, so the
        // customer path's contract and tests never need to change.
        Route::post('register-owner', [AuthController::class, 'registerOwner']);
        Route::post('login', [AuthController::class, 'login']);
    });
    Route::middleware(['auth:sanctum', 'throttle:api'])->prefix('auth')->group(function (): void {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
    });
    Route::middleware(['auth:sanctum', 'throttle:api'])->prefix('customer')->group(function (): void {
        Route::get('salons', [CustomerSalonController::class, 'index']);

        Route::get('profile', [CustomerProfileController::class, 'show']);
        Route::match(['put', 'patch'], 'profile', [CustomerProfileController::class, 'update']);

        Route::get('bookings', [CustomerBookingController::class, 'index']);
        Route::post('bookings', [CustomerBookingController::class, 'store']);
        Route::post('bookings/price-preview', [CustomerBookingController::class, 'pricePreview']);
        Route::get('bookings/{booking}', [CustomerBookingController::class, 'show']);
        Route::post('bookings/{booking}/cancel', [CustomerBookingController::class, 'cancel']);
        Route::post('bookings/{booking}/reschedule', [CustomerBookingController::class, 'reschedule']);

        // Phase 12 — coupons/membership/loyalty. Same X-Tenant-Slug
        // resolution as `profile`/`bookings` above (no `tenant.context`
        // middleware: a customer may hold profiles across several tenants).
        // See LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
        Route::get('membership', [CustomerMembershipController::class, 'current']);
        Route::middleware('throttle:checkout')->group(function (): void {
            Route::post('membership/checkout', [CustomerMembershipController::class, 'checkout']);
            Route::post('membership/checkout/verify', [CustomerMembershipController::class, 'verifyCheckout']);
        });

        Route::get('loyalty', [CustomerLoyaltyController::class, 'account']);
        Route::get('loyalty/transactions', [CustomerLoyaltyController::class, 'transactions']);
    });

    Route::middleware(['auth:sanctum', 'throttle:api'])->group(function (): void {
        Route::get('branches/{branch}/availability', [AvailabilityController::class, 'index']);
        Route::get('branches/{branch}/services', [CustomerServiceController::class, 'index']);
        // Public browse, scoped by branch — mirrors the two routes above
        // (see MOBILE_API_INTEGRATION.md for why branch-scoped catalog
        // endpoints need no tenant.context/X-Tenant-Slug).
        Route::get('branches/{branch}/membership-plans', [CustomerMembershipController::class, 'plans']);
    });

    // Platform administration (super_admin only, not tenant-scoped) — backend
    // management APIs only, no Flutter Platform Admin app in this phase.
    Route::middleware(['auth:sanctum', 'throttle:api'])->prefix('platform')->group(function (): void {
        Route::get('plans', [PlanController::class, 'indexAll']);
        Route::post('plans', [PlanController::class, 'store']);
        Route::match(['put', 'patch'], 'plans/{plan}', [PlanController::class, 'update']);
        Route::post('plans/{plan}/activate', [PlanController::class, 'activate']);
        Route::post('plans/{plan}/deactivate', [PlanController::class, 'deactivate']);
    });

    // Billing/subscription — deliberately its own group WITHOUT
    // `subscription.active`: an owner must always be able to view/renew/
    // cancel billing regardless of subscription status (see
    // SAAS_BILLING_ARCHITECTURE.md, "Subscription access control").
    // In-app notifications, device-token registration, and personal channel
    // preferences — deliberately NOT tenant-scoped (no `tenant.context`
    // middleware): every query is scoped to the authenticated user instead,
    // since a customer's notification inbox spans every tenant they hold a
    // customer profile with. See NOTIFICATION_ARCHITECTURE.md,
    // "Tenant isolation".
    Route::middleware(['auth:sanctum', 'throttle:api'])->prefix('notifications')->group(function (): void {
        Route::get('/', [NotificationController::class, 'index']);
        Route::get('unread-count', [NotificationController::class, 'unreadCount']);
        Route::post('read-all', [NotificationController::class, 'markAllRead']);
        Route::post('{notification}/read', [NotificationController::class, 'markRead']);

        Route::post('device-tokens', [DeviceTokenController::class, 'store']);
        Route::post('device-tokens/deactivate', [DeviceTokenController::class, 'deactivate']);

        Route::get('preferences', [NotificationPreferenceController::class, 'personal']);
        Route::put('preferences', [NotificationPreferenceController::class, 'updatePersonal']);
    });

    Route::middleware(['auth:sanctum', 'tenant.context', 'throttle:api'])->prefix('subscription')->group(function (): void {
        Route::get('/', [SubscriptionController::class, 'show']);
        Route::get('plans', [PlanController::class, 'index']);
        Route::middleware('throttle:checkout')->group(function (): void {
            Route::post('checkout', [SubscriptionController::class, 'checkout']);
            Route::post('checkout/verify', [SubscriptionController::class, 'verify']);
            Route::post('renew', [SubscriptionController::class, 'renew']);
        });
        Route::post('cancel', [SubscriptionController::class, 'cancel']);
        Route::get('payments', [SubscriptionController::class, 'payments']);
        Route::get('invoices', [SubscriptionController::class, 'invoices']);
    });

    // No auth — the gateway calls this directly. Authenticity comes from the
    // signature check inside the controller, never from Sanctum.
    Route::post('webhooks/razorpay', [PaymentWebhookController::class, 'handle']);

    Route::middleware(['auth:sanctum', 'tenant.context', 'subscription.active', 'throttle:api'])->group(function (): void {
        Route::get('dashboard/summary', [DashboardController::class, 'summary']);

        Route::get('salon', [SalonController::class, 'show']);
        Route::post('salon', [SalonController::class, 'store']);
        Route::match(['put', 'patch'], 'salon', [SalonController::class, 'update']);
        Route::get('salon/settings', [SalonController::class, 'settings']);
        Route::match(['put', 'patch'], 'salon/settings', [SalonController::class, 'updateSettings']);
        Route::get('salon/notification-settings', [NotificationPreferenceController::class, 'tenant']);
        Route::match(['put', 'patch'], 'salon/notification-settings', [NotificationPreferenceController::class, 'updateTenant']);

        Route::apiResource('branches', BranchController::class);
        Route::get('branches/{branch}/working-hours', [BranchWorkingHourController::class, 'index']);
        Route::put('branches/{branch}/working-hours', [BranchWorkingHourController::class, 'update']);
        Route::get('branches/{branch}/holidays', [BranchHolidayController::class, 'index']);
        Route::post('branches/{branch}/holidays', [BranchHolidayController::class, 'store']);
        Route::match(['put', 'patch'], 'branches/{branch}/holidays/{holiday}', [BranchHolidayController::class, 'update']);
        Route::delete('branches/{branch}/holidays/{holiday}', [BranchHolidayController::class, 'destroy']);
        Route::apiResource('service-categories', ServiceCategoryController::class);
        Route::apiResource('services', ServiceController::class);

        Route::get('staff/me', [StaffController::class, 'me']);
        Route::apiResource('staff', StaffController::class);
        Route::get('staff/{staff}/services', [StaffServiceController::class, 'index']);
        Route::put('staff/{staff}/services', [StaffServiceController::class, 'update']);
        Route::get('staff/{staff}/working-hours', [StaffWorkingHourController::class, 'index']);
        Route::put('staff/{staff}/working-hours', [StaffWorkingHourController::class, 'update']);
        Route::get('staff/{staff}/breaks', [StaffBreakController::class, 'index']);
        Route::post('staff/{staff}/breaks', [StaffBreakController::class, 'store']);
        Route::match(['put', 'patch'], 'staff/{staff}/breaks/{break}', [StaffBreakController::class, 'update']);
        Route::delete('staff/{staff}/breaks/{break}', [StaffBreakController::class, 'destroy']);
        Route::get('staff/{staff}/leaves', [StaffLeaveController::class, 'index']);
        Route::post('staff/{staff}/leaves', [StaffLeaveController::class, 'store']);
        Route::match(['put', 'patch'], 'staff/{staff}/leaves/{leave}', [StaffLeaveController::class, 'update']);
        Route::delete('staff/{staff}/leaves/{leave}', [StaffLeaveController::class, 'destroy']);

        Route::apiResource('customers', CustomerController::class);
        Route::get('customers/{customer}/summary', [CustomerController::class, 'summary']);
        Route::get('customers/{customer}/notes', [CustomerNoteController::class, 'index']);
        Route::post('customers/{customer}/notes', [CustomerNoteController::class, 'store']);
        Route::match(['put', 'patch'], 'customers/{customer}/notes/{note}', [CustomerNoteController::class, 'update']);
        Route::delete('customers/{customer}/notes/{note}', [CustomerNoteController::class, 'destroy']);

        Route::apiResource('bookings', BookingController::class)->except(['destroy']);
        Route::post('bookings/price-preview', [BookingController::class, 'pricePreview']);
        Route::post('bookings/{booking}/confirm', [BookingController::class, 'confirm']);
        Route::post('bookings/{booking}/cancel', [BookingController::class, 'cancel']);
        Route::post('bookings/{booking}/reschedule', [BookingController::class, 'reschedule']);

        // Phase 12 — coupons/membership/loyalty (owner/super-admin only for
        // every write; see "Authorization" in
        // LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md). Loyalty *settings*
        // reuse the existing `salon/settings` endpoint above — no separate
        // endpoint for those.
        Route::apiResource('coupons', CouponController::class);
        Route::post('coupons/{coupon}/activate', [CouponController::class, 'activate']);
        Route::post('coupons/{coupon}/deactivate', [CouponController::class, 'deactivate']);

        Route::apiResource('membership-plans', MembershipPlanController::class);
        Route::post('membership-plans/{membership_plan}/activate', [MembershipPlanController::class, 'activate']);
        Route::post('membership-plans/{membership_plan}/deactivate', [MembershipPlanController::class, 'deactivate']);

        Route::get('memberships', [MembershipManagementController::class, 'index']);
        Route::get('memberships/{customer_membership}', [MembershipManagementController::class, 'show']);
        Route::post('memberships/grant', [MembershipManagementController::class, 'grant']);
        Route::post('memberships/{customer_membership}/cancel', [MembershipManagementController::class, 'cancel']);

        Route::get('loyalty/customers', [LoyaltyManagementController::class, 'index']);
        Route::get('loyalty/customers/{customer}', [LoyaltyManagementController::class, 'show']);
        Route::get('loyalty/customers/{customer}/transactions', [LoyaltyManagementController::class, 'transactions']);
        Route::post('loyalty/customers/{customer}/adjust', [LoyaltyManagementController::class, 'adjust']);

        // Phase 13 — reports/analytics. Owner-only (see ReportController):
        // unlike `dashboard/summary` above, none of these are reachable by a
        // Staff session. See REPORTING_ANALYTICS_ARCHITECTURE.md.
        Route::prefix('reports')->group(function (): void {
            Route::get('dashboard', [ReportController::class, 'dashboard']);
            Route::get('revenue', [ReportController::class, 'revenue']);
            Route::get('bookings', [ReportController::class, 'bookings']);
            Route::get('customers', [ReportController::class, 'customers']);
            Route::get('services', [ReportController::class, 'services']);
            Route::get('staff', [ReportController::class, 'staff']);
            Route::get('branches', [ReportController::class, 'branches']);
            Route::get('coupons', [ReportController::class, 'coupons']);
            Route::get('memberships', [ReportController::class, 'memberships']);
            Route::get('loyalty', [ReportController::class, 'loyalty']);
        });
    });
});
