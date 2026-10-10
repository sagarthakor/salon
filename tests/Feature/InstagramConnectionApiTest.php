<?php

namespace Tests\Feature;

use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\InstagramConnection;
use App\Models\SalonMedia;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/** Instagram OAuth connection, metadata sync and token lifecycle. Every Meta call is faked — nothing here touches the network. */
class InstagramConnectionApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.instagram.app_id' => 'app-id', 'services.instagram.app_secret' => 'app-secret', 'services.instagram.redirect_uri' => 'https://salon.test/api/v1/instagram/callback']);
    }

    public function test_status_reports_not_connected_and_configuration(): void
    {
        $f = $this->fixture('a');
        $this->owner($f)->getJson('/api/v1/instagram/connection')->assertOk()->assertJsonPath('data.connected', false)->assertJsonPath('data.configured', true);

        config(['services.instagram.app_secret' => null]);
        $this->owner($f)->getJson('/api/v1/instagram/connection')->assertJsonPath('data.configured', false);
    }

    public function test_connect_returns_an_official_authorization_url_with_state_and_minimal_scope(): void
    {
        $f = $this->fixture('a');
        $url = $this->owner($f)->postJson('/api/v1/instagram/connect')->assertOk()->json('data.authorization_url');

        $this->assertStringStartsWith('https://www.instagram.com/oauth/authorize?', $url);
        parse_str(parse_url($url, PHP_URL_QUERY), $query);
        $this->assertSame('app-id', $query['client_id']);
        $this->assertSame('code', $query['response_type']);
        $this->assertSame('instagram_business_basic', $query['scope']);
        $this->assertSame('https://salon.test/api/v1/instagram/callback', $query['redirect_uri']);
        $this->assertGreaterThanOrEqual(32, strlen($query['state']));
        $this->assertStringNotContainsString('app-secret', $url);
    }

    public function test_connect_fails_cleanly_when_not_configured_and_for_non_owners(): void
    {
        $f = $this->fixture('a');
        config(['services.instagram.app_id' => null]);
        $this->owner($f)->postJson('/api/v1/instagram/connect')->assertStatus(503)->assertJsonPath('kind', 'not_configured');

        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($customer, 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug)->postJson('/api/v1/instagram/connect')->assertForbidden();
    }

    public function test_callback_stores_an_encrypted_long_lived_token_and_never_leaks_it(): void
    {
        $f = $this->fixture('a');
        $state = $this->beginState($f);
        $this->fakeOAuthSuccess();

        $response = $this->get("/api/v1/instagram/callback?code=THECODE%23_&state={$state}");

        $response->assertOk()->assertSee('@nil_hairport_unisex');
        $this->assertStringNotContainsString('LONG_TOKEN', $response->getContent());
        Http::assertSent(fn ($r) => str_contains($r->url(), 'api.instagram.com/oauth/access_token') && $r['code'] === 'THECODE' && $r['client_secret'] === 'app-secret');
        Http::assertSent(fn ($r) => str_contains($r->url(), 'ig_exchange_token'));

        $connection = InstagramConnection::withoutGlobalScope('tenant')->firstOrFail();
        $this->assertSame($f['tenant']->id, $connection->tenant_id);
        $this->assertSame('LONG_TOKEN', $connection->access_token);
        $raw = DB::table('instagram_connections')->value('access_token');
        $this->assertStringNotContainsString('LONG_TOKEN', $raw);
        $this->assertTrue($connection->token_expires_at->between(now()->addDays(59), now()->addDays(61)));
        $this->assertArrayNotHasKey('access_token', $connection->toArray());

        $status = $this->owner($f)->getJson('/api/v1/instagram/connection')->assertOk()->assertJsonPath('data.connected', true)->assertJsonPath('data.username', 'nil_hairport_unisex');
        $this->assertStringNotContainsString('LONG_TOKEN', $status->getContent());
    }

    public function test_callback_rejects_missing_forged_replayed_and_denied_requests(): void
    {
        $f = $this->fixture('a');
        $this->fakeOAuthSuccess();

        $this->get('/api/v1/instagram/callback?code=X&state=forged')->assertStatus(400);
        $this->get('/api/v1/instagram/callback?error=access_denied&state=x')->assertStatus(400);
        $this->get('/api/v1/instagram/callback')->assertStatus(400);

        $state = $this->beginState($f);
        $this->get("/api/v1/instagram/callback?code=X&state={$state}")->assertOk();
        // The state is single-use.
        $this->get("/api/v1/instagram/callback?code=X&state={$state}")->assertStatus(400);
        $this->assertSame(1, InstagramConnection::withoutGlobalScope('tenant')->count());
    }

    public function test_callback_reports_meta_errors_without_storing_a_connection(): void
    {
        $f = $this->fixture('a');
        Http::fake(['api.instagram.com/*' => Http::response(['error_type' => 'OAuthException', 'code' => 400, 'error_message' => 'Invalid authorization code'], 400)]);
        $state = $this->beginState($f);

        $this->get("/api/v1/instagram/callback?code=BAD&state={$state}")->assertStatus(400)->assertDontSee('Invalid authorization code');
        $this->assertSame(0, InstagramConnection::withoutGlobalScope('tenant')->count());
    }

    public function test_sync_imports_paginated_metadata_hidden_by_default_and_skips_unsupported_types(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        Http::fake([
            'graph.instagram.com/me/media*' => Http::sequence()
                ->push(['data' => [
                    ['id' => '1', 'media_type' => 'VIDEO', 'media_product_type' => 'REELS', 'permalink' => 'https://www.instagram.com/reel/AAA/', 'thumbnail_url' => 'https://cdn.example/1.jpg', 'caption' => 'First', 'timestamp' => '2026-09-01T10:00:00+0000'],
                    ['id' => '2', 'media_type' => 'IMAGE', 'permalink' => 'https://www.instagram.com/p/BBB/'],
                    ['id' => '3', 'media_type' => 'STORY_X', 'permalink' => 'https://www.instagram.com/p/CCC/'],
                ], 'paging' => ['cursors' => ['after' => 'CURSOR1'], 'next' => 'https://graph.instagram.com/next']])
                ->push(['data' => [['id' => '4', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/DDD/']], 'paging' => ['cursors' => ['after' => 'CURSOR2']]]),
        ]);

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 3)->assertJsonPath('data.skipped', 1);

        $items = SalonMedia::withoutGlobalScope('tenant')->orderBy('instagram_media_id')->get();
        $this->assertCount(3, $items);
        $this->assertFalse($items[0]->is_active);
        $this->assertSame('video', $items[0]->media_type);
        $this->assertSame('image', $items[1]->media_type);
        $this->assertNull($items[0]->video_path);
        $this->assertSame('https://cdn.example/1.jpg', $items[0]->instagram_thumbnail_url);
        Http::assertSent(fn ($r) => str_contains($r->url(), 'after=CURSOR1'));
        Http::assertSent(fn ($r) => str_contains($r->url(), 'me/media') && ! str_contains($r->url(), 'media_url'));
        $this->assertNotNull(InstagramConnection::withoutGlobalScope('tenant')->first()->last_synced_at);
    }

    public function test_resync_refreshes_instagram_fields_but_preserves_owner_curation(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        $page = fn (string $caption, string $thumb) => ['data' => [['id' => '1', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/AAA/', 'caption' => $caption, 'thumbnail_url' => $thumb]]];
        Http::fake(['graph.instagram.com/me/media*' => Http::sequence()->push($page('IG caption', 'https://cdn.example/old.jpg'))->push($page('Changed on IG', 'https://cdn.example/new.jpg'))]);

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk();
        $id = SalonMedia::withoutGlobalScope('tenant')->value('id');
        $this->owner($f)->patchJson("/api/v1/salon-media/{$id}", ['is_active' => true, 'caption' => 'Owner caption', 'category' => 'styling', 'sort_order' => 3])->assertOk();

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 0)->assertJsonPath('data.updated', 1);

        $media = SalonMedia::withoutGlobalScope('tenant')->findOrFail($id);
        $this->assertSame(1, SalonMedia::withoutGlobalScope('tenant')->count());
        $this->assertTrue($media->is_active);
        $this->assertSame('Owner caption', $media->caption);
        $this->assertSame('styling', $media->category->value);
        $this->assertSame(3, $media->sort_order);
        $this->assertSame('https://cdn.example/new.jpg', $media->instagram_thumbnail_url);
    }

    public function test_sync_requires_a_connection_and_handles_rate_limits(): void
    {
        $f = $this->fixture('a');
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertStatus(409)->assertJsonPath('kind', 'not_connected');

        $this->connect($f);
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['error' => ['message' => 'limit', 'type' => 'OAuthException', 'code' => 4]], 400)]);
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertStatus(429);
        $this->assertSame('active', InstagramConnection::withoutGlobalScope('tenant')->first()->status);
    }

    public function test_sync_marks_the_connection_expired_when_meta_rejects_the_token(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['error' => ['message' => 'Error validating access token', 'type' => 'OAuthException', 'code' => 190]], 400)]);

        $response = $this->owner($f)->postJson('/api/v1/instagram/sync')->assertStatus(409);
        $this->assertStringNotContainsString('LONG_TOKEN', $response->getContent());
        $this->assertSame('expired', InstagramConnection::withoutGlobalScope('tenant')->first()->status);

        Http::fake();
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertStatus(409);
        Http::assertNothingSent();
        $this->owner($f)->getJson('/api/v1/instagram/connection')->assertJsonPath('data.needs_reconnect', true);
    }

    public function test_media_request_only_asks_for_fields_valid_for_instagram_login(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => []])]);

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk();

        Http::assertSent(function ($request) {
            parse_str((string) parse_url($request->url(), PHP_URL_QUERY), $query);

            return $query['fields'] === 'id,caption,media_type,permalink,thumbnail_url,timestamp'
                && ! str_contains($query['fields'], 'media_product_type') && ! str_contains($query['fields'], 'media_url');
        });
    }

    /**
     * @return array<string, array{0: int, 1: array<string, mixed>, 2: int}>
     */
    public static function nonAuthErrors(): array
    {
        return [
            'invalid field (100)' => [400, ['error' => ['message' => 'Tried accessing nonexisting field', 'type' => 'OAuthException', 'code' => 100]], 502, 'invalid_request'],
            'invalid parameter, no code' => [400, ['error' => ['message' => 'Invalid parameter']], 502, 'unavailable'],
            'permission error (10)' => [403, ['error' => ['message' => 'Permission denied', 'type' => 'OAuthException', 'code' => 10]], 409, 'permission_denied'],
            'permission error (200 range)' => [403, ['error' => ['message' => 'Requires permission', 'type' => 'OAuthException', 'code' => 230]], 409, 'permission_denied'],
            'instagram rate limit (80002)' => [400, ['error' => ['message' => 'Rate limit', 'type' => 'OAuthException', 'code' => 80002]], 429, 'rate_limited'],
            'app rate limit (4)' => [400, ['error' => ['message' => 'Rate limit', 'code' => 4]], 429, 'rate_limited'],
            'http 429' => [429, [], 429, 'rate_limited'],
            'server error' => [500, ['error' => ['message' => 'oops', 'code' => 2]], 502, 'unavailable'],
        ];
    }

    #[DataProvider('nonAuthErrors')]
    public function test_errors_that_are_not_token_problems_never_expire_the_connection(int $httpStatus, array $body, int $expectedStatus, string $expectedKind): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        Http::fake(['graph.instagram.com/me/media*' => Http::response($body, $httpStatus)]);

        $response = $this->owner($f)->postJson('/api/v1/instagram/sync')->assertStatus($expectedStatus)->assertJsonPath('kind', $expectedKind)->assertJsonPath('success', false);

        $this->assertStringNotContainsString('LONG_TOKEN', $response->getContent());
        $connection = InstagramConnection::withoutGlobalScope('tenant')->first();
        $this->assertSame('active', $connection->status);
        $this->assertNull($connection->last_error);
        $this->owner($f)->getJson('/api/v1/instagram/connection')->assertJsonPath('data.needs_reconnect', false);
    }

    /**
     * @return array<string, array{0: int, 1: array<string, mixed>}>
     */
    public static function tokenErrors(): array
    {
        return [
            'code 190' => [400, ['error' => ['message' => 'Error validating access token', 'type' => 'OAuthException', 'code' => 190]]],
            'code 190 with expired subcode' => [400, ['error' => ['message' => 'Session expired', 'type' => 'OAuthException', 'code' => 190, 'error_subcode' => 463]]],
            'subcode 460 password changed' => [400, ['error' => ['message' => 'x', 'code' => 190, 'error_subcode' => 460]]],
            'code 102 session' => [400, ['error' => ['message' => 'Session invalid', 'type' => 'OAuthException', 'code' => 102]]],
            'http 401' => [401, ['error' => ['message' => 'Unauthorized']]],
        ];
    }

    #[DataProvider('tokenErrors')]
    public function test_genuine_token_errors_expire_the_connection_and_ask_to_reconnect(int $httpStatus, array $body): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        Http::fake(['graph.instagram.com/me/media*' => Http::response($body, $httpStatus)]);

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertStatus(409)->assertJsonPath('kind', 'reconnect_required');

        $this->assertSame('expired', InstagramConnection::withoutGlobalScope('tenant')->first()->status);
        $this->owner($f)->getJson('/api/v1/instagram/connection')->assertJsonPath('data.needs_reconnect', true);
    }

    public function test_a_rejected_oauth_code_exchange_is_an_authorization_failure_but_a_rate_limit_is_not(): void
    {
        $f = $this->fixture('a');
        $badState = $this->beginState($f);
        $limitedState = $this->beginState($f);
        Http::fake(['api.instagram.com/*' => Http::sequence()
            ->push(['error_type' => 'OAuthException', 'code' => 400, 'error_message' => 'Matching code was not found'], 400)
            ->push(['error' => ['message' => 'limit', 'code' => 80002]], 400)]);

        $this->get("/api/v1/instagram/callback?code=BAD&state={$badState}")->assertStatus(400);
        $this->get("/api/v1/instagram/callback?code=X&state={$limitedState}")->assertStatus(429);
        $this->assertSame(0, InstagramConnection::withoutGlobalScope('tenant')->count());
    }

    public function test_a_non_auth_failure_while_refreshing_does_not_expire_the_token(): void
    {
        $f = $this->fixture('a');
        $this->connect($f, ['token_expires_at' => now()->addDays(3), 'token_refreshed_at' => now()->subDays(40)]);
        Http::fake(['graph.instagram.com/refresh_access_token*' => Http::response(['error' => ['message' => 'bad param', 'code' => 100]], 400)]);

        Artisan::call('instagram:refresh-tokens');

        $connection = InstagramConnection::withoutGlobalScope('tenant')->first();
        $this->assertSame('active', $connection->status);
        $this->assertSame('LONG_TOKEN', $connection->access_token);
    }

    public function test_sync_adopts_a_manually_added_reel_instead_of_duplicating_it_and_keeps_owner_curation(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        $manualId = $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'instagram.com/reel/AbC123/?igsh=zzz', 'caption' => 'Mine', 'category' => 'styling', 'sort_order' => 4])->assertCreated()->json('data.id');
        $unrelated = $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/OTHER/', 'caption' => 'Unrelated'])->json('data.id');
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => [
            ['id' => '777', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/AbC123/', 'caption' => 'IG caption', 'thumbnail_url' => 'https://cdn.example/t.jpg', 'timestamp' => '2026-09-01T10:00:00+0000'],
        ]])]);

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 0)->assertJsonPath('data.updated', 1);

        $this->assertSame(2, SalonMedia::withoutGlobalScope('tenant')->count());
        $adopted = SalonMedia::withoutGlobalScope('tenant')->findOrFail($manualId);
        $this->assertSame('777', $adopted->instagram_media_id);
        $this->assertSame('Mine', $adopted->caption);
        $this->assertTrue($adopted->is_active);
        $this->assertSame('styling', $adopted->category->value);
        $this->assertSame(4, $adopted->sort_order);
        $this->assertSame('https://cdn.example/t.jpg', $adopted->instagram_thumbnail_url);
        $this->assertSame('Unrelated', SalonMedia::withoutGlobalScope('tenant')->findOrFail($unrelated)->caption);
        $this->assertNull(SalonMedia::withoutGlobalScope('tenant')->findOrFail($unrelated)->instagram_media_id);

        // A second sync is idempotent.
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => [
            ['id' => '777', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/AbC123/'],
        ]])]);
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 0);
        $this->assertSame(2, SalonMedia::withoutGlobalScope('tenant')->count());
    }

    public function test_sync_skips_a_reel_already_tracked_under_a_different_instagram_id(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        Http::fake(['graph.instagram.com/me/media*' => Http::sequence()
            ->push(['data' => [['id' => '1', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/SAME/']]])
            ->push(['data' => [['id' => '2', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/SAME/']]])]);

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 1);
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 0)->assertJsonPath('data.skipped', 1);
        $this->assertSame(1, SalonMedia::withoutGlobalScope('tenant')->count());
    }

    public function test_an_owner_deleted_synced_item_is_not_recreated_by_later_syncs_and_tenants_are_isolated(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $this->connect($a);
        $this->connect($b);
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => [
            ['id' => '1', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/AAA/'],
            ['id' => '2', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/BBB/'],
        ]])]);
        $this->owner($a)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 2);
        $this->owner($b)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 2);

        $deleted = SalonMedia::withoutGlobalScope('tenant')->where('tenant_id', $a['tenant']->id)->where('instagram_media_id', '1')->value('id');
        $this->owner($a)->deleteJson("/api/v1/salon-media/{$deleted}")->assertOk();

        for ($i = 0; $i < 2; $i++) {
            $this->owner($a)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 0)->assertJsonPath('data.skipped', 1);
        }
        $this->assertSame(['2'], SalonMedia::withoutGlobalScope('tenant')->where('tenant_id', $a['tenant']->id)->pluck('instagram_media_id')->all());
        // Tenant B still has its own copy of media id 1, and B's syncs are unaffected.
        $this->assertSame(2, SalonMedia::withoutGlobalScope('tenant')->where('tenant_id', $b['tenant']->id)->count());
        $this->owner($b)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 0)->assertJsonPath('data.skipped', 0);
        $this->assertDatabaseHas('instagram_ignored_media', ['tenant_id' => $a['tenant']->id, 'instagram_media_id' => '1']);
        $this->assertDatabaseMissing('instagram_ignored_media', ['tenant_id' => $b['tenant']->id]);
    }

    public function test_deleting_a_manually_added_item_records_nothing_and_re_adding_a_deleted_reel_by_link_is_adopted_again(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        $manual = $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/MAN/'])->json('data.id');
        $this->owner($f)->deleteJson("/api/v1/salon-media/{$manual}")->assertOk();
        $this->assertSame(0, DB::table('instagram_ignored_media')->count());

        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => [['id' => '5', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/DEL/']]])]);
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk();
        $id = SalonMedia::withoutGlobalScope('tenant')->value('id');
        $this->owner($f)->deleteJson("/api/v1/salon-media/{$id}")->assertOk();
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 0);
        $this->assertSame(0, SalonMedia::withoutGlobalScope('tenant')->count());

        // The owner changes their mind and pastes the link: that is an explicit re-add.
        $readded = $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'instagram.com/reel/DEL?igsh=1'])->assertCreated()->json('data.id');
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.updated', 1)->assertJsonPath('data.created', 0);
        $this->assertSame(1, SalonMedia::withoutGlobalScope('tenant')->count());
        $this->assertSame('5', SalonMedia::withoutGlobalScope('tenant')->findOrFail($readded)->instagram_media_id);
        $this->assertSame(0, DB::table('instagram_ignored_media')->count());
    }

    public function test_a_caption_the_owner_cleared_or_changed_is_never_refilled_by_sync(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => [
            ['id' => '1', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/AAA/', 'caption' => 'IG one'],
            ['id' => '2', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/BBB/', 'caption' => 'IG two'],
            ['id' => '3', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/CCC/', 'caption' => 'IG three'],
        ]])]);
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk();
        $byId = fn (string $igId) => SalonMedia::withoutGlobalScope('tenant')->where('instagram_media_id', $igId)->firstOrFail();
        $this->assertSame('IG one', $byId('1')->caption);
        $this->assertFalse($byId('1')->caption_customized);

        $this->owner($f)->patchJson('/api/v1/salon-media/'.$byId('1')->id, ['caption' => null])->assertOk();
        $this->owner($f)->patchJson('/api/v1/salon-media/'.$byId('2')->id, ['caption' => 'Owner two'])->assertOk();
        // Re-saving the unchanged caption (e.g. the app resubmitting a form) is not a customization.
        $this->owner($f)->patchJson('/api/v1/salon-media/'.$byId('3')->id, ['caption' => 'IG three', 'category' => 'styling'])->assertOk();
        $this->assertFalse($byId('3')->caption_customized);
        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk();

        $this->assertNull($byId('1')->caption);
        $this->assertTrue($byId('1')->caption_customized);
        $this->assertSame('Owner two', $byId('2')->caption);
    }

    public function test_caption_filling_is_unchanged_for_new_items_and_manual_reel_adoption(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/NOCAP/'])->assertCreated();
        $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/OWNCAP/', 'caption' => 'Mine'])->assertCreated();
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => [
            ['id' => '1', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/NOCAP/', 'caption' => 'From IG'],
            ['id' => '2', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/OWNCAP/', 'caption' => 'From IG'],
            ['id' => '3', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/NEW/', 'caption' => 'Brand new'],
        ]])]);

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 1)->assertJsonPath('data.updated', 2);

        $caption = fn (string $igId) => SalonMedia::withoutGlobalScope('tenant')->where('instagram_media_id', $igId)->value('caption');
        $this->assertSame('From IG', $caption('1'));
        $this->assertSame('Mine', $caption('2'));
        $this->assertSame('Brand new', $caption('3'));
    }

    public function test_a_unique_violation_from_a_concurrent_sync_reuses_the_existing_row_without_touching_owner_fields(): void
    {
        $f = $this->fixture('a');
        $connection = $this->connect($f);
        // Simulate the other sync winning the race: its row appears after our lookup, just before our insert.
        $raced = false;
        SalonMedia::creating(function (SalonMedia $media) use (&$raced, $f): void {
            if ($raced || $media->instagram_media_id !== '9') {
                return;
            }
            $raced = true;
            DB::table('salon_media')->insert([
                'id' => (string) Str::ulid(), 'tenant_id' => $f['tenant']->id, 'source' => 'instagram', 'media_type' => 'video',
                'instagram_media_id' => '9', 'instagram_url' => 'https://www.instagram.com/reel/RACE/', 'instagram_shortcode' => 'RACE',
                'caption' => 'Owner caption', 'caption_customized' => true, 'is_active' => true, 'sort_order' => 3, 'category' => 'styling',
                'created_at' => now(), 'updated_at' => now(),
            ]);
        });
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => [
            ['id' => '9', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/RACE/', 'caption' => 'IG caption', 'thumbnail_url' => 'https://cdn.example/r.jpg'],
        ]])]);

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertOk()->assertJsonPath('data.created', 0)->assertJsonPath('data.updated', 1);

        $this->assertTrue($raced);
        $this->assertSame(1, SalonMedia::withoutGlobalScope('tenant')->count());
        $row = SalonMedia::withoutGlobalScope('tenant')->firstOrFail();
        $this->assertSame('https://cdn.example/r.jpg', $row->instagram_thumbnail_url);
        $this->assertSame('Owner caption', $row->caption);
        $this->assertTrue($row->is_active);
        $this->assertSame(3, $row->sort_order);
        $this->assertSame('styling', $row->category->value);
        $this->assertSame('active', $connection->fresh()->status);
    }

    public function test_an_unrelated_database_error_during_sync_is_not_swallowed(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        // A genuine non-unique failure on insert (NOT NULL violation) must still surface.
        SalonMedia::creating(function (SalonMedia $media): void {
            $media->source = null;
        });
        Http::fake(['graph.instagram.com/me/media*' => Http::response(['data' => [['id' => '1', 'media_type' => 'VIDEO', 'permalink' => 'https://www.instagram.com/reel/AAA/']]])]);

        $this->withoutExceptionHandling();
        $this->expectException(QueryException::class);
        $this->owner($f)->postJson('/api/v1/instagram/sync');
    }

    public function test_sync_refuses_a_connection_past_its_expiry_without_calling_instagram(): void
    {
        $f = $this->fixture('a');
        $this->connect($f, ['token_expires_at' => now()->subDay()]);
        Http::fake();

        $this->owner($f)->postJson('/api/v1/instagram/sync')->assertStatus(409)->assertJsonPath('kind', 'reconnect_required');
        Http::assertNothingSent();
    }

    public function test_disconnect_removes_the_token_but_keeps_gallery_items(): void
    {
        $f = $this->fixture('a');
        $this->connect($f);
        $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->assertCreated();

        $this->owner($f)->deleteJson('/api/v1/instagram/connection')->assertOk()->assertJsonPath('data.connected', false);
        $this->assertSame(0, InstagramConnection::withoutGlobalScope('tenant')->count());
        $this->assertSame(1, SalonMedia::withoutGlobalScope('tenant')->count());
    }

    public function test_one_tenant_cannot_see_sync_or_disconnect_another_tenants_connection(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $this->connect($a);

        $this->owner($b)->getJson('/api/v1/instagram/connection')->assertJsonPath('data.connected', false);
        $this->owner($b)->postJson('/api/v1/instagram/sync')->assertStatus(409);
        $this->owner($b)->deleteJson('/api/v1/instagram/connection')->assertOk();
        $this->assertSame(1, InstagramConnection::withoutGlobalScope('tenant')->count());
    }

    public function test_refresh_command_extends_tokens_close_to_expiry_and_flags_rejected_ones(): void
    {
        $near = $this->fixture('near');
        $far = $this->fixture('far');
        $bad = $this->fixture('bad');
        $this->connect($near, ['token_expires_at' => now()->addDays(5), 'token_refreshed_at' => now()->subDays(40), 'access_token' => 'NEAR']);
        $this->connect($far, ['token_expires_at' => now()->addDays(50), 'token_refreshed_at' => now()->subDays(10), 'access_token' => 'FAR']);
        $this->connect($bad, ['token_expires_at' => now()->addDays(3), 'token_refreshed_at' => now()->subDays(40), 'access_token' => 'BAD']);
        Http::fake(function ($request) {
            if ($request['access_token'] === 'BAD') {
                return Http::response(['error' => ['type' => 'OAuthException', 'code' => 190, 'message' => 'x']], 400);
            }

            return Http::response(['access_token' => 'REFRESHED', 'expires_in' => 5184000]);
        });

        Artisan::call('instagram:refresh-tokens');

        $byTenant = InstagramConnection::withoutGlobalScope('tenant')->get()->keyBy('tenant_id');
        $this->assertSame('REFRESHED', $byTenant[$near['tenant']->id]->access_token);
        $this->assertTrue($byTenant[$near['tenant']->id]->token_expires_at->gt(now()->addDays(59)));
        $this->assertSame('FAR', $byTenant[$far['tenant']->id]->access_token);
        $this->assertSame('expired', $byTenant[$bad['tenant']->id]->status);
        Http::assertSentCount(2);
    }

    private function fakeOAuthSuccess(): void
    {
        Http::fake([
            'api.instagram.com/oauth/access_token' => Http::response(['access_token' => 'SHORT_TOKEN', 'user_id' => 1784, 'permissions' => 'instagram_business_basic']),
            'graph.instagram.com/access_token*' => Http::response(['access_token' => 'LONG_TOKEN', 'token_type' => 'bearer', 'expires_in' => 5183944]),
            'graph.instagram.com/me*' => Http::response(['user_id' => '1784', 'username' => 'nil_hairport_unisex', 'account_type' => 'BUSINESS']),
        ]);
    }

    private function beginState(array $f): string
    {
        $url = $this->owner($f)->postJson('/api/v1/instagram/connect')->json('data.authorization_url');
        parse_str(parse_url($url, PHP_URL_QUERY), $query);

        return $query['state'];
    }

    private function connect(array $f, array $overrides = []): InstagramConnection
    {
        app(TenantContext::class)->set($f['tenant']);
        $connection = InstagramConnection::query()->create($overrides + [
            'instagram_user_id' => '1784', 'username' => 'nil_hairport_unisex', 'access_token' => 'LONG_TOKEN',
            'token_expires_at' => now()->addDays(40), 'token_refreshed_at' => now()->subDays(20), 'status' => 'active',
        ]);
        app(TenantContext::class)->clear();

        return $connection;
    }

    private function owner(array $f)
    {
        return $this->actingAs($f['owner'], 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug);
    }

    private function fixture(string $slug): array
    {
        $tenant = Tenant::query()->create(['name' => $slug, 'slug' => $slug]);
        $owner = User::factory()->create(['role' => UserRole::SALON_OWNER]);
        $tenant->users()->attach($owner, ['role' => TenantMembershipRole::SALON_OWNER->value]);

        return compact('tenant', 'owner');
    }
}
