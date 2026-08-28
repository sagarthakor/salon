<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\NotificationChannel;
use App\Enums\NotificationEventType;
use App\Enums\TenantMembershipRole;
use App\Http\Controllers\Controller;
use App\Http\Requests\Notifications\NotificationPreferenceRequest;
use App\Models\NotificationPreference;
use App\Support\ApiResponse;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

/**
 * Two independent scopes over the same `notification_preferences` table —
 * see NOTIFICATION_ARCHITECTURE.md, "Notification preferences":
 *  - personal (`tenant_id` null, `user_id` = caller): any authenticated
 *    user's own channel opt-out, honored regardless of which tenant an
 *    event happens under.
 *  - tenant (`user_id` null, `tenant_id` = current tenant): the owner's
 *    tenant-wide default, only the owner may change.
 * Only channels NotificationChannel::external() are exposed — in-app is
 * always on and not user-configurable in this phase.
 */
class NotificationPreferenceController extends Controller
{
    public function personal(Request $request): JsonResponse
    {
        $overrides = NotificationPreference::query()
            ->whereNull('tenant_id')->where('user_id', $request->user()->id)
            ->get()->keyBy(fn (NotificationPreference $p) => "{$p->event_type->value}:{$p->channel->value}");

        return ApiResponse::success($this->matrix($overrides), 'Notification preferences retrieved.');
    }

    public function updatePersonal(NotificationPreferenceRequest $request): JsonResponse
    {
        foreach ($request->validated('preferences') as $row) {
            NotificationPreference::query()->updateOrCreate(
                ['tenant_id' => null, 'user_id' => $request->user()->id, 'event_type' => $row['event_type'], 'channel' => $row['channel']],
                ['enabled' => $row['enabled']],
            );
        }

        return $this->personal($request);
    }

    public function tenant(Request $request): JsonResponse
    {
        $tenant = app(TenantContext::class)->require();
        $overrides = NotificationPreference::query()
            ->where('tenant_id', $tenant->id)->whereNull('user_id')
            ->get()->keyBy(fn (NotificationPreference $p) => "{$p->event_type->value}:{$p->channel->value}");

        return ApiResponse::success($this->matrix($overrides), 'Tenant notification settings retrieved.');
    }

    public function updateTenant(NotificationPreferenceRequest $request): JsonResponse
    {
        $tenant = app(TenantContext::class)->require();
        $isOwner = $tenant->users()->wherePivot('user_id', $request->user()->id)->wherePivot('role', TenantMembershipRole::SALON_OWNER->value)->exists();
        abort_unless($isOwner, 403, 'Only the salon owner can change tenant notification settings.');

        foreach ($request->validated('preferences') as $row) {
            NotificationPreference::query()->updateOrCreate(
                ['tenant_id' => $tenant->id, 'user_id' => null, 'event_type' => $row['event_type'], 'channel' => $row['channel']],
                ['enabled' => $row['enabled']],
            );
        }

        return $this->tenant($request);
    }

    /**
     * @param  Collection<string, NotificationPreference>  $overrides
     * @return list<array{event_type: string, channel: string, enabled: bool, is_override: bool}>
     */
    private function matrix($overrides): array
    {
        // Not a dotted config() lookup — NotificationEventType values (e.g.
        // 'booking.confirmed') contain a literal dot that would otherwise be
        // misparsed as nesting; see NotificationPreferenceResolver.
        $defaults = config('notifications.default_channels', []);

        $rows = [];
        foreach (NotificationEventType::cases() as $event) {
            foreach (NotificationChannel::external() as $channel) {
                $key = "{$event->value}:{$channel->value}";
                $override = $overrides->get($key);
                $rows[] = [
                    'event_type' => $event->value,
                    'channel' => $channel->value,
                    'enabled' => $override?->enabled ?? (bool) ($defaults[$event->value][$channel->value] ?? false),
                    'is_override' => $override !== null,
                ];
            }
        }

        return $rows;
    }
}
