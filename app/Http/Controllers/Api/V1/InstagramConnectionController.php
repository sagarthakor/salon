<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\InstagramConnection;
use App\Services\Instagram\InstagramApiException;
use App\Services\Instagram\InstagramClient;
use App\Services\Instagram\InstagramConnectionService;
use App\Services\Instagram\InstagramMediaSyncService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Owner-side Instagram connection management. Responses never include the
 * access token — only status metadata.
 */
class InstagramConnectionController extends TenantManagementController
{
    public function show(InstagramClient $client): JsonResponse
    {
        $this->managedTenant();

        return ApiResponse::success($this->payload(InstagramConnection::query()->first(), $client), 'Instagram connection retrieved.');
    }

    public function connect(Request $request, InstagramConnectionService $service): JsonResponse
    {
        $tenant = $this->managedTenant();
        try {
            $url = $service->beginAuthorization($tenant, $request->user());
        } catch (InstagramApiException $exception) {
            return $this->failure($exception);
        }

        return ApiResponse::success(['authorization_url' => $url], 'Open this URL to authorize Instagram.');
    }

    public function disconnect(InstagramConnectionService $service, InstagramClient $client): JsonResponse
    {
        $this->managedTenant();
        $connection = InstagramConnection::query()->first();
        if ($connection !== null) {
            $service->disconnect($connection);
        }

        return ApiResponse::success($this->payload(null, $client), 'Instagram disconnected.');
    }

    public function sync(InstagramMediaSyncService $sync): JsonResponse
    {
        $this->managedTenant();
        $connection = InstagramConnection::query()->first();
        if ($connection === null) {
            return response()->json(['success' => false, 'message' => 'Connect your Instagram account first.', 'errors' => (object) ['instagram' => ['Not connected.']], 'kind' => 'not_connected'], 409);
        }
        try {
            $result = $sync->sync($connection);
        } catch (InstagramApiException $exception) {
            return $this->failure($exception);
        }

        return ApiResponse::success($result, 'Instagram media synchronized.');
    }

    /**
     * Same envelope as ApiResponse::error plus a top-level machine-readable `kind`
     * (see InstagramApiException::publicKind). Never carries provider payloads or tokens.
     */
    private function failure(InstagramApiException $exception): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => $exception->getMessage(),
            'errors' => (object) [],
            'kind' => $exception->publicKind(),
        ], $exception->httpStatus());
    }

    /** @return array<string, mixed> */
    private function payload(?InstagramConnection $connection, InstagramClient $client): array
    {
        return [
            'configured' => $client->isConfigured(),
            'connected' => $connection !== null,
            'status' => $connection?->status,
            'needs_reconnect' => $connection !== null && ! $connection->isUsable(),
            'username' => $connection?->username,
            'account_type' => $connection?->account_type,
            'token_expires_at' => $connection?->token_expires_at?->toIso8601String(),
            'last_synced_at' => $connection?->last_synced_at?->toIso8601String(),
            'last_error' => $connection?->last_error,
        ];
    }
}
