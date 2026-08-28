<?php

namespace App\Providers;

use App\Enums\UserRole;
use App\Events\BookingCompleted;
use App\Listeners\Loyalty\AwardLoyaltyPointsOnBookingCompleted;
use App\Listeners\Membership\MembershipNotificationSubscriber;
use App\Listeners\Notifications\BillingNotificationSubscriber;
use App\Listeners\Notifications\BookingNotificationSubscriber;
use App\Models\Staff;
use App\Models\Tenant;
use App\Models\User;
use App\Policies\StaffPolicy;
use App\Policies\TenantPolicy;
use App\Services\Billing\Gateways\PaymentGatewayInterface;
use App\Services\Billing\Gateways\RazorpayGateway;
use App\Services\Notifications\Providers\FcmHttpV1Provider;
use App\Services\Notifications\Providers\LogSmsProvider;
use App\Services\Notifications\Providers\MetaWhatsAppProvider;
use App\Services\Notifications\Providers\PushProviderInterface;
use App\Services\Notifications\Providers\SmsProviderInterface;
use App\Services\Notifications\Providers\WhatsAppProviderInterface;
use App\Support\TenantContext;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->scoped(TenantContext::class);

        // The only place a concrete gateway class is named — every other
        // billing class depends on PaymentGatewayInterface only. Tests
        // rebind this to FakePaymentGateway (see SAAS_BILLING_ARCHITECTURE.md).
        $this->app->bind(PaymentGatewayInterface::class, fn () => new RazorpayGateway(
            config('services.razorpay.key'),
            config('services.razorpay.secret'),
            config('services.razorpay.webhook_secret'),
        ));

        // Notification provider bindings — see NOTIFICATION_ARCHITECTURE.md.
        // Every channel depends on the *Interface only; tests rebind these
        // to the Fake* equivalents, the same pattern as PaymentGatewayInterface.
        $this->app->bind(PushProviderInterface::class, fn () => new FcmHttpV1Provider(
            config('notifications.fcm.project_id'),
            config('notifications.fcm.client_email'),
            config('notifications.fcm.private_key'),
        ));
        $this->app->bind(WhatsAppProviderInterface::class, fn () => new MetaWhatsAppProvider(
            config('notifications.whatsapp.access_token'),
            config('notifications.whatsapp.phone_number_id'),
            config('notifications.whatsapp.api_base_url'),
        ));
        // No SMS vendor has been selected yet — see config/notifications.php
        // and the Phase 11 report. Swap this binding once one is chosen.
        $this->app->bind(SmsProviderInterface::class, LogSmsProvider::class);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Gate::policy(Tenant::class, TenantPolicy::class);
        Gate::policy(Staff::class, StaffPolicy::class);
        Gate::define('manage-platform', fn (User $user): bool => $user->role === UserRole::SUPER_ADMIN);
        RateLimiter::for('auth', fn (Request $request) => Limit::perMinute(5)->by(strtolower((string) $request->input('email')).'|'.$request->ip()));

        // General authenticated-API ceiling — every business route was
        // previously reachable with no application-level throttle at all
        // beyond login/register. 120/min comfortably covers real mobile
        // usage (dashboard/report polling, list screens, normal booking
        // flow) while bounding what a leaked token or a scripted client can
        // do against expensive endpoints (report aggregation, availability
        // computation). Keyed by user id where authenticated, IP otherwise
        // (the webhook route deliberately doesn't use this limiter at all —
        // see routes/api.php). See "Rate limiting" in SECURITY_HARDENING.md.
        RateLimiter::for('api', fn (Request $request) => Limit::perMinute(120)->by($request->user()?->id ?? $request->ip()));

        // A tighter limit for the specific endpoints that either call an
        // external payment gateway or run the heaviest server-side
        // computation per request (booking creation/price-preview, which
        // re-run full availability/coupon/loyalty validation) — these are
        // the ones worth bounding independently of general API traffic.
        RateLimiter::for('checkout', fn (Request $request) => Limit::perMinute(10)->by($request->user()?->id ?? $request->ip()));

        Event::subscribe(BookingNotificationSubscriber::class);
        Event::subscribe(BillingNotificationSubscriber::class);
        Event::subscribe(MembershipNotificationSubscriber::class);
        Event::listen(BookingCompleted::class, AwardLoyaltyPointsOnBookingCompleted::class);
    }
}
