<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\NotificationResource;
use App\Models\Notification;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Every query and mutation here is scoped to `user_id === $request->user()->id`
 * — deliberately not tenant-scoped, since a customer's inbox spans every
 * tenant they hold a customer profile with (see
 * NOTIFICATION_ARCHITECTURE.md, "Tenant isolation"). This is what makes
 * cross-tenant/cross-user access structurally impossible rather than
 * something each action has to remember to check.
 */
class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = Notification::query()->where('user_id', $request->user()->id)->orderByDesc('created_at');
        if ($request->boolean('unread_only')) {
            $query->whereNull('read_at');
        }

        return ApiResponse::success(NotificationResource::collection($query->paginate(min($request->integer('per_page', 20), 100))), 'Notifications retrieved.');
    }

    public function unreadCount(Request $request): JsonResponse
    {
        $count = Notification::query()->where('user_id', $request->user()->id)->whereNull('read_at')->count();

        return ApiResponse::success(['unread_count' => $count], 'Unread count retrieved.');
    }

    public function markRead(Request $request, string $notification): JsonResponse
    {
        $model = $this->owned($request, $notification);
        if ($model->read_at === null) {
            $model->update(['read_at' => now()]);
        }

        return ApiResponse::success(new NotificationResource($model), 'Notification marked as read.');
    }

    public function markAllRead(Request $request): JsonResponse
    {
        $updated = Notification::query()->where('user_id', $request->user()->id)->whereNull('read_at')->update(['read_at' => now()]);

        return ApiResponse::success(['updated' => $updated], 'All notifications marked as read.');
    }

    private function owned(Request $request, string $id): Notification
    {
        $notification = Notification::query()->findOrFail($id);
        abort_unless($notification->user_id === $request->user()->id, 404);

        return $notification;
    }
}
