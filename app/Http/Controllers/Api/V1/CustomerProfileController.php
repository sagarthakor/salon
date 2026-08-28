<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Customer\CustomerProfileRequest;
use App\Http\Resources\CustomerResource;
use App\Models\Customer;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CustomerProfileController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $profile = $this->resolve($request);

        return ApiResponse::success(new CustomerResource($profile), 'Customer profile retrieved.');
    }

    public function update(CustomerProfileRequest $request): JsonResponse
    {
        $profile = $this->resolve($request);
        $data = $request->validated();
        $normalized = Customer::normalizePhone($data['phone'], $data['country_code'] ?? null);
        $duplicate = Customer::withoutGlobalScope('tenant')
            ->where('tenant_id', $profile->tenant_id)
            ->where('normalized_phone', $normalized)
            ->whereKeyNot($profile->id)
            ->exists();
        if ($duplicate) {
            return ApiResponse::error('A customer with this phone number already exists.', ['phone' => ['A customer with this phone number already exists.']], 422);
        }
        $data['normalized_phone'] = $normalized;
        if ($request->hasFile('profile_photo')) {
            $data['profile_photo'] = $request->file('profile_photo')->store('customers', 'public');
        } else {
            unset($data['profile_photo']);
        }
        $profile->update($data);

        return ApiResponse::success(new CustomerResource($profile->fresh()), 'Customer profile updated.');
    }

    private function resolve(Request $request): Customer
    {
        $userId = $request->user()->id;
        $slug = $request->header('X-Tenant-Slug');
        $query = Customer::withoutGlobalScope('tenant')->where('user_id', $userId);
        if ($slug) {
            $profile = $query->whereHas('tenant', fn ($q) => $q->where('slug', $slug))->first();
            abort_if($profile === null, 404, 'No customer profile found for this tenant.');

            return $profile;
        }
        $profiles = $query->get();
        abort_if($profiles->isEmpty(), 404, 'No customer profile found.');
        if ($profiles->count() > 1) {
            abort(422, 'Multiple customer profiles found. Specify X-Tenant-Slug to select one.');
        }

        return $profiles->first();
    }
}
