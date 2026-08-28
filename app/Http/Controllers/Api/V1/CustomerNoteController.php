<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Customer\CustomerNoteRequest;
use App\Http\Resources\CustomerNoteResource;
use App\Models\Customer;
use App\Models\CustomerNote;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;

class CustomerNoteController extends TenantManagementController
{
    public function index(string $customer): JsonResponse
    {
        $this->managedTenant();
        $model = $this->customer($customer);

        return ApiResponse::success(CustomerNoteResource::collection($model->notes()->with('author')->latest()->get()), 'Customer notes retrieved.');
    }

    public function store(CustomerNoteRequest $request, string $customer): JsonResponse
    {
        $this->managedTenant();
        $model = $this->customer($customer);
        $note = $model->notes()->create([...$request->validated(), 'author_id' => $request->user()->id]);

        return ApiResponse::success(new CustomerNoteResource($note->load('author')), 'Customer note created.', 201);
    }

    public function update(CustomerNoteRequest $request, string $customer, string $note): JsonResponse
    {
        $this->managedTenant();
        $model = $this->note($this->customer($customer), $note);
        $model->update($request->validated());

        return ApiResponse::success(new CustomerNoteResource($model->fresh()->load('author')), 'Customer note updated.');
    }

    public function destroy(string $customer, string $note): JsonResponse
    {
        $this->managedTenant();
        $this->note($this->customer($customer), $note)->delete();

        return ApiResponse::success(null, 'Customer note deleted.');
    }

    private function customer(string $id): Customer
    {
        return Customer::query()->findOrFail($id);
    }

    private function note(Customer $customer, string $id): CustomerNote
    {
        return $customer->notes()->findOrFail($id);
    }
}
