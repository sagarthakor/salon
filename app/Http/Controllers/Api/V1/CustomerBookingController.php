<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Booking\BookingCancelRequest;
use App\Http\Requests\Booking\BookingPricePreviewRequest;
use App\Http\Requests\Booking\BookingRescheduleRequest;
use App\Http\Requests\Booking\CustomerBookingRequest;
use App\Http\Resources\BookingResource;
use App\Models\Booking;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\Service;
use App\Services\Booking\BookingService;
use App\Services\Booking\Exceptions\BookingUnavailableException;
use App\Services\Pricing\BookingPricingService;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CustomerBookingController extends Controller
{
    public function __construct(
        private readonly BookingService $bookings,
        private readonly BookingPricingService $pricing,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $customerIds = $this->ownCustomerIds($request);
        $query = Booking::withoutGlobalScope('tenant')->whereIn('customer_id', $customerIds)->orderByDesc('booking_date')->orderByDesc('start_time');

        return ApiResponse::success(BookingResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Bookings retrieved.');
    }

    public function store(CustomerBookingRequest $request): JsonResponse
    {
        $branch = Branch::withoutGlobalScope('tenant')->findOrFail($request->validated('branch_id'));
        $context = app(TenantContext::class);
        $context->set($branch->tenant);
        try {
            $customer = $this->resolveOrCreateCustomer($request, $branch);
            $date = CarbonImmutable::createFromFormat('Y-m-d', $request->validated('date'), $branch->timezone ?: 'UTC')->startOfDay();
            $booking = $this->bookings->create(
                $branch->tenant, $branch, $customer, $request->validated('items'), $date, $request->validated('start_time'),
                $request->validated('notes'), $request->user(),
                $request->validated('coupon_code'), $request->validated('loyalty_points_to_redeem'),
            );
        } catch (BookingUnavailableException $e) {
            return ApiResponse::error($e->getMessage(), $e->errors(), 409);
        } finally {
            $context->clear();
        }

        return ApiResponse::success(new BookingResource($booking), 'Booking created.', 201);
    }

    /**
     * Always prices for the caller's own customer profile — `customer_id`
     * in the request (if any) is ignored, the same rule `store()` already
     * follows. Read-only; see BookingController::pricePreview() for the
     * owner-side twin.
     */
    public function pricePreview(BookingPricePreviewRequest $request): JsonResponse
    {
        $branch = Branch::withoutGlobalScope('tenant')->findOrFail($request->validated('branch_id'));
        $context = app(TenantContext::class);
        $context->set($branch->tenant);
        try {
            $customer = $this->resolveOrCreateCustomer($request, $branch);
            $services = Service::query()->whereIn('id', $request->validated('service_ids'))->where('branch_id', $branch->id)->get();
            if ($services->count() !== count(array_unique($request->validated('service_ids')))) {
                return ApiResponse::error('One or more services are invalid for this branch.', [], 422);
            }
            $breakdown = $this->pricing->preview($branch->tenant, $branch->salon, $customer, $services, $request->validated('coupon_code'), $request->validated('loyalty_points_to_redeem'));
        } finally {
            $context->clear();
        }

        return ApiResponse::success($breakdown->toArray(), 'Price calculated.');
    }

    public function show(Request $request, string $booking): JsonResponse
    {
        $model = $this->ownedBooking($request, $booking);

        return $this->withTenantContext($model, fn (): JsonResponse => ApiResponse::success(new BookingResource($model->load(['items.staff', 'items.service', 'customer', 'statusHistories'])), 'Booking retrieved.'));
    }

    public function cancel(BookingCancelRequest $request, string $booking): JsonResponse
    {
        $model = $this->ownedBooking($request, $booking);

        return $this->withTenantContext($model, function () use ($model, $request): JsonResponse {
            try {
                $updated = $this->bookings->cancel($model, $request->validated('reason'), $request->user(), false);
            } catch (BookingUnavailableException $e) {
                return ApiResponse::error($e->getMessage(), $e->errors(), 409);
            }

            return ApiResponse::success(new BookingResource($updated), 'Booking cancelled.');
        });
    }

    public function reschedule(BookingRescheduleRequest $request, string $booking): JsonResponse
    {
        $model = $this->ownedBooking($request, $booking);

        return $this->withTenantContext($model, function () use ($model, $request): JsonResponse {
            $branch = $model->branch;
            $date = CarbonImmutable::createFromFormat('Y-m-d', $request->validated('date'), $branch->timezone ?: 'UTC')->startOfDay();
            try {
                $updated = $this->bookings->reschedule($model, $date, $request->validated('start_time'), $request->user());
            } catch (BookingUnavailableException $e) {
                return ApiResponse::error($e->getMessage(), $e->errors(), 409);
            }

            return ApiResponse::success(new BookingResource($updated), 'Booking rescheduled.');
        });
    }

    /**
     * A first-time app customer has no `customer_profiles` row for this
     * tenant yet — walk-in/offline customers are still registered by staff
     * via CustomerController::store() (unchanged), but an app customer must
     * never need that manual step just to complete their own booking.
     * Creates the row from the authenticated User's own identity only —
     * never from any `customer_id`/`tenant_id` the client could supply — the
     * moment it's actually needed. See CUSTOMER_ARCHITECTURE.md, "Customer
     * discovery and first-time booking".
     */
    private function resolveOrCreateCustomer(Request $request, Branch $branch): Customer
    {
        $user = $request->user();
        $customer = Customer::query()->where('user_id', $user->id)->first();
        if ($customer !== null) {
            return $customer;
        }

        $phone = trim((string) $request->input('phone', ''));
        if ($phone === '' || ! preg_match('/^[0-9+() .-]+$/', $phone)) {
            throw new HttpResponseException(ApiResponse::error(
                'A valid phone number is required to complete your first booking with this salon.',
                ['phone' => ['The phone field is required.']],
                422,
            ));
        }
        $countryCode = $request->input('country_code');
        $normalized = Customer::normalizePhone($phone, $countryCode);

        try {
            return Customer::query()->create([
                'user_id' => $user->id,
                'name' => $user->name,
                'phone' => $phone,
                'country_code' => $countryCode,
                'normalized_phone' => $normalized,
                'email' => $user->email,
                'status' => BusinessStatus::ACTIVE,
            ]);
        } catch (QueryException $e) {
            // Two unique constraints exist on this table (tenant_id+user_id,
            // tenant_id+normalized_phone) — a concurrent request for this
            // exact user always means we lost a race and should simply use
            // the row that won it, never fail the booking or leave a
            // duplicate. A collision against a *different*, already-
            // registered phone (e.g. a walk-in profile staff created for
            // someone else) is a real conflict, not a race — surfaced as a
            // normal validation error rather than a raw DB exception.
            $customer = Customer::query()->where('user_id', $user->id)->first();
            if ($customer !== null) {
                return $customer;
            }
            if (Customer::query()->where('normalized_phone', $normalized)->exists()) {
                throw new HttpResponseException(ApiResponse::error(
                    'A customer with this phone number is already registered at this salon. Please contact the salon to link your account.',
                    ['phone' => ['A customer with this phone number already exists.']],
                    409,
                ));
            }
            throw $e;
        }
    }

    /**
     * @return list<string>
     */
    private function ownCustomerIds(Request $request): array
    {
        return Customer::withoutGlobalScope('tenant')->where('user_id', $request->user()->id)->pluck('id')->all();
    }

    private function ownedBooking(Request $request, string $id): Booking
    {
        $booking = Booking::withoutGlobalScope('tenant')->findOrFail($id);
        abort_unless(in_array($booking->customer_id, $this->ownCustomerIds($request), true), 404);

        return $booking;
    }

    private function withTenantContext(Booking $booking, callable $callback): JsonResponse
    {
        $context = app(TenantContext::class);
        $context->set($booking->tenant);
        try {
            return $callback();
        } finally {
            $context->clear();
        }
    }
}
