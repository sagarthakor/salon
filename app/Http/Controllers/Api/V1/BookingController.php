<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BookingStatus;
use App\Http\Requests\Booking\BookingCancelRequest;
use App\Http\Requests\Booking\BookingPricePreviewRequest;
use App\Http\Requests\Booking\BookingRequest;
use App\Http\Requests\Booking\BookingRescheduleRequest;
use App\Http\Requests\Booking\BookingUpdateRequest;
use App\Http\Resources\BookingResource;
use App\Models\Booking;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\Service;
use App\Services\Booking\BookingService;
use App\Services\Booking\Exceptions\BookingUnavailableException;
use App\Services\Pricing\BookingPricingService;
use App\Support\ApiResponse;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class BookingController extends TenantManagementController
{
    public function __construct(
        private readonly BookingService $bookings,
        private readonly BookingPricingService $pricing,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $this->viewableTenant();
        $query = Booking::query()->with(['customer', 'items']);
        if ($request->filled('date')) {
            $query->where('booking_date', $request->string('date'));
        }
        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }
        if ($request->filled('branch_id')) {
            $query->where('branch_id', $request->string('branch_id'));
        }
        if ($request->filled('customer_id')) {
            $query->where('customer_id', $request->string('customer_id'));
        }
        if ($request->filled('staff_id')) {
            $staffId = $request->string('staff_id');
            $query->whereHas('items', fn ($q) => $q->where('staff_id', $staffId));
        }
        $query->orderByDesc('booking_date')->orderByDesc('start_time');

        return ApiResponse::success(BookingResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Bookings retrieved.');
    }

    public function store(BookingRequest $request): JsonResponse
    {
        $tenant = $this->viewableTenant();
        $branch = Branch::query()->findOrFail($request->validated('branch_id'));
        $customer = Customer::query()->findOrFail($request->validated('customer_id'));
        $date = CarbonImmutable::createFromFormat('Y-m-d', $request->validated('date'), $branch->timezone ?: 'UTC')->startOfDay();
        try {
            $booking = $this->bookings->create(
                $tenant, $branch, $customer, $request->validated('items'), $date, $request->validated('start_time'),
                $request->validated('notes'), $request->user(),
                $request->validated('coupon_code'), $request->validated('loyalty_points_to_redeem'),
            );
        } catch (BookingUnavailableException $e) {
            return ApiResponse::error($e->getMessage(), $e->errors(), 409);
        }

        return ApiResponse::success(new BookingResource($booking), 'Booking created.', 201);
    }

    /**
     * Read-only — never creates a booking, never mutates a coupon's usage
     * count or a loyalty balance. The exact same BookingPricingService::reserve()
     * path runs again (and is the only thing that actually counts) when the
     * booking is created — see "Price preview" in
     * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
     */
    public function pricePreview(BookingPricePreviewRequest $request): JsonResponse
    {
        $tenant = $this->viewableTenant();
        $branch = Branch::query()->findOrFail($request->validated('branch_id'));
        $services = Service::query()->whereIn('id', $request->validated('service_ids'))->where('branch_id', $branch->id)->get();
        if ($services->count() !== count(array_unique($request->validated('service_ids')))) {
            return ApiResponse::error('One or more services are invalid for this branch.', [], 422);
        }
        if (! $request->filled('customer_id')) {
            return ApiResponse::error('A customer must be selected to preview pricing.', ['customer_id' => ['This field is required.']], 422);
        }
        $customer = Customer::query()->findOrFail($request->validated('customer_id'));

        $breakdown = $this->pricing->preview($tenant, $branch->salon, $customer, $services, $request->validated('coupon_code'), $request->validated('loyalty_points_to_redeem'));

        return ApiResponse::success($breakdown->toArray(), 'Price calculated.');
    }

    public function show(string $booking): JsonResponse
    {
        $this->viewableTenant();

        return ApiResponse::success(new BookingResource($this->booking($booking)->load(['items.staff', 'items.service', 'customer', 'statusHistories'])), 'Booking retrieved.');
    }

    public function update(BookingUpdateRequest $request, string $booking): JsonResponse
    {
        $this->viewableTenant();
        $model = $this->booking($booking);
        try {
            if ($request->filled('status')) {
                $model = $this->bookings->transition($model, BookingStatus::from($request->validated('status')), $request->user());
            }
            if ($request->filled('notes')) {
                $model->update(['notes' => $request->validated('notes')]);
            }
        } catch (BookingUnavailableException $e) {
            return ApiResponse::error($e->getMessage(), $e->errors(), 409);
        }

        return ApiResponse::success(new BookingResource($model->fresh(['items.staff', 'items.service', 'customer'])), 'Booking updated.');
    }

    public function confirm(Request $request, string $booking): JsonResponse
    {
        $this->viewableTenant();
        try {
            $model = $this->bookings->transition($this->booking($booking), BookingStatus::CONFIRMED, $request->user());
        } catch (BookingUnavailableException $e) {
            return ApiResponse::error($e->getMessage(), $e->errors(), 409);
        }

        return ApiResponse::success(new BookingResource($model), 'Booking confirmed.');
    }

    public function cancel(BookingCancelRequest $request, string $booking): JsonResponse
    {
        $this->viewableTenant();
        try {
            $model = $this->bookings->cancel($this->booking($booking), $request->validated('reason'), $request->user(), true);
        } catch (BookingUnavailableException $e) {
            return ApiResponse::error($e->getMessage(), $e->errors(), 409);
        }

        return ApiResponse::success(new BookingResource($model), 'Booking cancelled.');
    }

    public function reschedule(BookingRescheduleRequest $request, string $booking): JsonResponse
    {
        $this->viewableTenant();
        $model = $this->booking($booking);
        $branch = $model->branch;
        $date = CarbonImmutable::createFromFormat('Y-m-d', $request->validated('date'), $branch->timezone ?: 'UTC')->startOfDay();
        try {
            $model = $this->bookings->reschedule($model, $date, $request->validated('start_time'), $request->user());
        } catch (BookingUnavailableException $e) {
            return ApiResponse::error($e->getMessage(), $e->errors(), 409);
        }

        return ApiResponse::success(new BookingResource($model), 'Booking rescheduled.');
    }

    private function booking(string $id): Booking
    {
        return Booking::query()->findOrFail($id);
    }
}
