<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Notifications\DeviceTokenRequest;
use App\Models\UserDeviceToken;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Device-token lifecycle for push notifications. `token` is globally unique
 * (see migration) — registering a token already owned by a different user
 * (e.g. a shared/reset device, or a re-login) simply reassigns it, since a
 * push token can only ever be meaningfully delivered to whoever is
 * currently signed in on that device.
 */
class DeviceTokenController extends Controller
{
    public function store(DeviceTokenRequest $request): JsonResponse
    {
        $tenant = app(TenantContext::class)->get();

        $token = UserDeviceToken::query()->updateOrCreate(
            ['token' => $request->validated('token')],
            [
                'user_id' => $request->user()->id,
                'tenant_id' => $tenant?->id,
                'platform' => $request->validated('platform'),
                'device_identifier' => $request->validated('device_identifier'),
                'last_seen_at' => now(),
                'is_active' => true,
            ],
        );

        return ApiResponse::success(['id' => $token->id], 'Device token registered.', 201);
    }

    /**
     * Idempotent by design (logout should never fail loudly): deactivating a
     * token that does not exist, or belongs to someone else, is a no-op
     * success rather than an error.
     */
    public function deactivate(Request $request): JsonResponse
    {
        $request->validate(['token' => ['required', 'string']]);

        UserDeviceToken::query()
            ->where('token', $request->string('token'))
            ->where('user_id', $request->user()->id)
            ->update(['is_active' => false]);

        return ApiResponse::success(null, 'Device token deactivated.');
    }
}
