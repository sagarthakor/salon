<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BookingStatus;
use App\Enums\BusinessStatus;
use App\Http\Requests\Customer\CustomerRequest;
use App\Http\Resources\CustomerResource;
use App\Models\Booking;
use App\Models\Customer;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CustomerController extends TenantManagementController
{
    public function index(Request $request): JsonResponse
    {
        $this->viewableTenant();
        $query = Customer::query();
        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }
        if ($request->filled('gender')) {
            $query->where('gender', $request->string('gender'));
        }
        if ($request->filled('search')) {
            $search = $request->string('search');
            $normalized = Customer::normalizePhone((string) $search, null);
            $query->where(function ($q) use ($search, $normalized): void {
                $q->where('name', 'like', "%{$search}%")
                    ->orWhere('email', 'like', "%{$search}%")
                    ->orWhere('phone', 'like', "%{$search}%")
                    ->when($normalized !== '', fn ($inner) => $inner->orWhere('normalized_phone', 'like', "%{$normalized}%"));
            });
        }
        $sorts = ['name', 'newest'];
        $sort = $request->input('sort', 'name');
        if (! in_array($sort, $sorts, true)) {
            return ApiResponse::error('Invalid sort field.', ['sort' => ['The selected sort field is invalid.']], 422);
        }
        $sort === 'newest' ? $query->latest() : $query->orderBy($sort)->orderBy('id');

        return ApiResponse::success(CustomerResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Customers retrieved.');
    }

    public function store(CustomerRequest $request): JsonResponse
    {
        $this->managedTenant();
        $data = $request->validated();
        $data['status'] ??= BusinessStatus::ACTIVE;
        $data['normalized_phone'] = Customer::normalizePhone($data['phone'], $data['country_code'] ?? null);
        $data['profile_photo'] = $request->hasFile('profile_photo') ? $request->file('profile_photo')->store('customers', 'public') : null;

        return ApiResponse::success(new CustomerResource(Customer::query()->create($data)), 'Customer created.', 201);
    }

    public function show(string $customer): JsonResponse
    {
        $this->viewableTenant();

        return ApiResponse::success(new CustomerResource($this->customer($customer)), 'Customer retrieved.');
    }

    public function update(CustomerRequest $request, string $customer): JsonResponse
    {
        $this->managedTenant();
        $model = $this->customer($customer);
        $data = $request->validated();
        $data['status'] ??= $model->status;
        $data['normalized_phone'] = Customer::normalizePhone($data['phone'], $data['country_code'] ?? null);
        if ($request->hasFile('profile_photo')) {
            $data['profile_photo'] = $request->file('profile_photo')->store('customers', 'public');
        } else {
            unset($data['profile_photo']);
        }
        $model->update($data);

        return ApiResponse::success(new CustomerResource($model->fresh()), 'Customer updated.');
    }

    public function destroy(string $customer): JsonResponse
    {
        $this->managedTenant();
        $this->customer($customer)->delete();

        return ApiResponse::success(null, 'Customer deleted.');
    }

    public function summary(string $customer): JsonResponse
    {
        $this->managedTenant();
        $model = $this->customer($customer);

        $bookings = Booking::query()->where('customer_id', $model->id)->get(['id', 'booking_date', 'start_time', 'status', 'total']);
        $completed = $bookings->where('status', BookingStatus::COMPLETED);
        $upcoming = $bookings
            ->whereIn('status', [BookingStatus::PENDING, BookingStatus::CONFIRMED, BookingStatus::CHECKED_IN, BookingStatus::IN_SERVICE])
            ->filter(fn (Booking $b) => $b->booking_date->isToday() || $b->booking_date->isFuture())
            ->sortBy([['booking_date', 'asc'], ['start_time', 'asc']])
            ->first();

        return ApiResponse::success([
            'customer' => new CustomerResource($model),
            'summary' => [
                'total_visits' => $bookings->count(),
                'completed_appointments' => $completed->count(),
                'cancelled_appointments' => $bookings->where('status', BookingStatus::CANCELLED)->count(),
                'no_show_count' => $bookings->where('status', BookingStatus::NO_SHOW)->count(),
                'total_spent' => number_format((float) $completed->sum('total'), 2, '.', ''),
                'last_visit_at' => $completed->sortByDesc('booking_date')->first()?->booking_date->format('Y-m-d'),
                'upcoming_appointment' => $upcoming ? [
                    'id' => $upcoming->id,
                    'booking_date' => $upcoming->booking_date->format('Y-m-d'),
                    'start_time' => substr((string) $upcoming->start_time, 0, 5),
                    'status' => $upcoming->status->value,
                ] : null,
            ],
        ], 'Customer summary retrieved.');
    }

    private function customer(string $id): Customer
    {
        return Customer::query()->findOrFail($id);
    }
}
