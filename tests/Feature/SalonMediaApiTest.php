<?php

namespace Tests\Feature;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Enums\TenantMembershipRole;
use App\Enums\UserRole;
use App\Models\Branch;
use App\Models\Salon;
use App\Models\SalonMedia;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Tenant;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/** Hair Inspiration gallery: owner management + public listing. See SALON_MEDIA_ARCHITECTURE.md. */
class SalonMediaApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('public');
    }

    public function test_owner_uploads_a_video_and_thumbnail_which_are_stored_under_the_tenant_folder_and_playable_natively(): void
    {
        $f = $this->fixture('a');
        $response = $this->owner($f)->post('/api/v1/salon-media', [
            'video' => UploadedFile::fake()->create('cut.mp4', 2000, 'video/mp4'),
            'thumbnail' => UploadedFile::fake()->image('thumb.jpg', 300, 300),
            'caption' => 'Layered cut',
            'category' => 'haircut',
        ]);

        $response->assertCreated()->assertJsonPath('data.playback', 'native')->assertJsonPath('data.has_native_video', true)->assertJsonPath('data.source', 'upload');
        $media = SalonMedia::withoutGlobalScope('tenant')->findOrFail($response->json('data.id'));
        $this->assertStringStartsWith("salon-media/{$f['tenant']->id}/videos/", $media->video_path);
        Storage::disk('public')->assertExists($media->video_path);
        Storage::disk('public')->assertExists($media->thumbnail_path);
        $this->assertStringContainsString('/storage/salon-media/', $response->json('data.video_url'));
        $this->assertSame($f['tenant']->id, $media->tenant_id);
    }

    public function test_owner_can_add_an_instagram_reel_url_without_a_native_video(): void
    {
        $f = $this->fixture('a');
        $response = $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'instagram.com/reel/ABC123/']);

        $response->assertCreated()->assertJsonPath('data.playback', 'instagram')->assertJsonPath('data.has_native_video', false)->assertJsonPath('data.video_url', null)
            ->assertJsonPath('data.instagram_url', 'https://www.instagram.com/reel/ABC123/');
    }

    public function test_instagram_url_must_be_a_real_instagram_post_link_and_not_a_duplicate(): void
    {
        $f = $this->fixture('a');
        $api = $this->owner($f);
        $api->postJson('/api/v1/salon-media', ['instagram_url' => 'https://evil.example/reel/ABC/'])->assertUnprocessable()->assertJsonValidationErrors('instagram_url');
        $api->postJson('/api/v1/salon-media', ['instagram_url' => 'javascript:alert(1)'])->assertUnprocessable();
        $api->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/nil_hairport_unisex/'])->assertUnprocessable();
        $api->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/ABC/'])->assertCreated();
        $api->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/ABC/'])->assertUnprocessable()->assertJsonValidationErrors('instagram_url');
    }

    public function test_equivalent_instagram_url_spellings_are_the_same_reel_and_cannot_be_added_twice(): void
    {
        $f = $this->fixture('a');
        $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AbC_123-x/'])->assertCreated()
            ->assertJsonPath('data.instagram_url', 'https://www.instagram.com/reel/AbC_123-x/');

        foreach (['instagram.com/reel/AbC_123-x', 'http://WWW.Instagram.com/reel/AbC_123-x/', 'https://instagram.com/reel/AbC_123-x/?igsh=abc123', 'https://www.instagram.com/reel/AbC_123-x?utm_source=ig_web_copy_link', 'https://www.instagram.com/p/AbC_123-x/'] as $variant) {
            $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => $variant])->assertUnprocessable()->assertJsonValidationErrors('instagram_url');
        }
        // Shortcodes are case-sensitive: a different code is a different Reel.
        $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/abc_123-x/'])->assertCreated();
        $this->assertSame(2, SalonMedia::withoutGlobalScope('tenant')->count());
    }

    public function test_editing_cannot_point_an_item_at_another_items_reel_but_may_resave_its_own(): void
    {
        $f = $this->fixture('a');
        $one = $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->json('data.id');
        $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/BBB/'])->assertCreated();

        $this->owner($f)->patchJson("/api/v1/salon-media/{$one}", ['instagram_url' => 'instagram.com/reel/BBB?igsh=1'])->assertUnprocessable()->assertJsonValidationErrors('instagram_url');
        $this->owner($f)->patchJson("/api/v1/salon-media/{$one}", ['instagram_url' => 'https://instagram.com/reel/AAA/?igsh=2', 'caption' => 'ok'])->assertOk()->assertJsonPath('data.instagram_url', 'https://www.instagram.com/reel/AAA/');
    }

    public function test_the_same_reel_may_exist_in_different_tenants(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $this->owner($a)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->assertCreated();
        $this->owner($b)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->assertCreated();
    }

    public function test_a_missing_or_null_sort_order_never_nulls_the_column_and_keeps_the_current_position(): void
    {
        $f = $this->fixture('a');
        $id = $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/', 'sort_order' => 5])->json('data.id');

        $this->owner($f)->patchJson("/api/v1/salon-media/{$id}", ['caption' => 'omitted'])->assertOk()->assertJsonPath('data.sort_order', 5);
        $this->owner($f)->patchJson("/api/v1/salon-media/{$id}", ['sort_order' => null, 'caption' => 'null'])->assertOk()->assertJsonPath('data.sort_order', 5);
        $this->owner($f)->patchJson("/api/v1/salon-media/{$id}", ['sort_order' => 9])->assertOk()->assertJsonPath('data.sort_order', 9);
        $this->owner($f)->post("/api/v1/salon-media/{$id}", ['_method' => 'PUT', 'sort_order' => '', 'caption' => 'multipart'], ['Accept' => 'application/json'])->assertOk()->assertJsonPath('data.sort_order', 9);

        $created = $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/BBB/', 'sort_order' => null])->assertCreated();
        $this->assertSame(0, $created->json('data.sort_order'));
    }

    public function test_owner_uploads_a_photo_which_customers_see_as_an_image(): void
    {
        $f = $this->fixture('a');
        $response = $this->owner($f)->post('/api/v1/salon-media', [
            'image' => UploadedFile::fake()->image('look.jpg', 800, 800),
            'caption' => 'Balayage', 'category' => 'hair_colour', 'service_id' => $f['service']->id,
        ])->assertCreated()->assertJsonPath('data.media_type', 'photo')->assertJsonPath('data.playback', 'image')->assertJsonPath('data.has_native_video', false);
        $media = SalonMedia::withoutGlobalScope('tenant')->findOrFail($response->json('data.id'));
        $this->assertStringStartsWith("salon-media/{$f['tenant']->id}/images/", $media->thumbnail_path);
        Storage::disk('public')->assertExists($media->thumbnail_path);
        $this->assertSame($response->json('data.thumbnail_url'), $response->json('data.image_url'));

        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($customer, 'sanctum')->getJson("/api/v1/branches/{$f['branch']->id}/gallery")->assertOk()
            ->assertJsonPath('data.0.playback', 'image')->assertJsonPath('data.0.service.id', $f['service']->id);

        // A photo stays valid with no video/link, and can have its image replaced; deleting removes the file.
        $this->owner($f)->post("/api/v1/salon-media/{$media->id}", ['_method' => 'PUT', 'image' => UploadedFile::fake()->image('new.png', 600, 600)])->assertOk();
        Storage::disk('public')->assertMissing($media->thumbnail_path);
        $replaced = $media->fresh()->thumbnail_path;
        Storage::disk('public')->assertExists($replaced);
        $this->owner($f)->deleteJson("/api/v1/salon-media/{$media->id}")->assertOk();
        Storage::disk('public')->assertMissing($replaced);
    }

    public function test_photo_upload_validates_type_and_rejects_photo_plus_video(): void
    {
        $f = $this->fixture('a');
        $this->owner($f)->post('/api/v1/salon-media', ['image' => UploadedFile::fake()->create('x.pdf', 10, 'application/pdf')], ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('image');
        $this->owner($f)->post('/api/v1/salon-media', [
            'image' => UploadedFile::fake()->image('a.jpg'), 'video' => UploadedFile::fake()->create('c.mp4', 100, 'video/mp4'),
        ], ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('image');
    }

    public function test_creating_requires_a_video_or_an_instagram_link(): void
    {
        $f = $this->fixture('a');
        $this->owner($f)->postJson('/api/v1/salon-media', ['caption' => 'nothing'])->assertUnprocessable()->assertJsonValidationErrors('video');
    }

    public function test_video_upload_validates_extension_size_and_actual_content(): void
    {
        $f = $this->fixture('a');
        $api = $this->owner($f);
        $api->post('/api/v1/salon-media', ['video' => UploadedFile::fake()->create('notes.txt', 10, 'text/plain')], ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('video');
        $api->post('/api/v1/salon-media', ['video' => UploadedFile::fake()->create('big.mp4', 60000, 'video/mp4')], ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('video');

        // A real PHP script merely named .mp4: the content sniff must reject it.
        $path = tempnam(sys_get_temp_dir(), 'vid');
        file_put_contents($path, '<?php echo "pwned";');
        $disguised = new UploadedFile($path, 'evil.mp4', 'video/mp4', null, true);
        $api->post('/api/v1/salon-media', ['video' => $disguised], ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('video');
        $this->assertSame(0, SalonMedia::withoutGlobalScope('tenant')->count());
        @unlink($path);
    }

    public function test_thumbnail_must_be_a_real_image(): void
    {
        $f = $this->fixture('a');
        $this->owner($f)->post('/api/v1/salon-media', [
            'video' => UploadedFile::fake()->create('cut.mp4', 100, 'video/mp4'),
            'thumbnail' => UploadedFile::fake()->create('thumb.pdf', 10, 'application/pdf'),
        ], ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('thumbnail');
        $this->assertSame([], Storage::disk('public')->allFiles());
    }

    public function test_owner_updates_caption_visibility_order_category_and_service_link(): void
    {
        $f = $this->fixture('a');
        $api = $this->owner($f);
        $id = $api->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/ABC/'])->json('data.id');

        $api->patchJson("/api/v1/salon-media/{$id}", [
            'caption' => 'New caption', 'is_active' => false, 'sort_order' => 7, 'category' => 'hair_colour', 'service_id' => $f['service']->id, 'branch_id' => $f['branch']->id,
        ])->assertOk()->assertJsonPath('data.caption', 'New caption')->assertJsonPath('data.is_active', false)->assertJsonPath('data.sort_order', 7)
            ->assertJsonPath('data.category', 'hair_colour')->assertJsonPath('data.service.id', $f['service']->id);

        $api->patchJson("/api/v1/salon-media/{$id}", ['category' => 'nope'])->assertUnprocessable();
    }

    public function test_replacing_and_removing_the_video_cleans_up_old_files_and_item_stays_presentable(): void
    {
        $f = $this->fixture('a');
        $api = $this->owner($f);
        $created = $api->post('/api/v1/salon-media', ['video' => UploadedFile::fake()->create('one.mp4', 100, 'video/mp4')])->json('data');
        $old = SalonMedia::withoutGlobalScope('tenant')->findOrFail($created['id'])->video_path;

        $api->post("/api/v1/salon-media/{$created['id']}", ['_method' => 'PUT', 'video' => UploadedFile::fake()->create('two.mp4', 100, 'video/mp4')])->assertOk();
        Storage::disk('public')->assertMissing($old);
        $new = SalonMedia::withoutGlobalScope('tenant')->findOrFail($created['id'])->video_path;
        Storage::disk('public')->assertExists($new);

        // No Instagram link and no video would leave nothing to show.
        $api->patchJson("/api/v1/salon-media/{$created['id']}", ['remove_video' => true])->assertUnprocessable();
        Storage::disk('public')->assertExists($new);
    }

    public function test_delete_removes_row_and_files(): void
    {
        $f = $this->fixture('a');
        $api = $this->owner($f);
        $id = $api->post('/api/v1/salon-media', ['video' => UploadedFile::fake()->create('one.mp4', 100, 'video/mp4'), 'thumbnail' => UploadedFile::fake()->image('t.png')])->json('data.id');
        $this->assertCount(2, Storage::disk('public')->allFiles());

        $api->deleteJson("/api/v1/salon-media/{$id}")->assertOk();
        $this->assertSame([], Storage::disk('public')->allFiles());
        $this->assertSame(0, SalonMedia::withoutGlobalScope('tenant')->count());
    }

    public function test_reorder_sets_positions_and_rejects_other_tenants_ids(): void
    {
        $f = $this->fixture('a');
        $b = $this->fixture('b');
        $other = $this->owner($b)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/CCC/'])->json('data.id');
        $api = $this->owner($f);
        $one = $api->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->json('data.id');
        $two = $api->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/BBB/'])->json('data.id');

        $api->postJson('/api/v1/salon-media/reorder', ['ids' => [$two, $one]])->assertOk();
        $ids = collect($api->getJson('/api/v1/salon-media')->json('data'))->pluck('id')->all();
        $this->assertSame([$two, $one], $ids);

        $api->postJson('/api/v1/salon-media/reorder', ['ids' => [$one, $other]])->assertUnprocessable();
        $this->assertSame(0, SalonMedia::withoutGlobalScope('tenant')->findOrFail($other)->sort_order);
    }

    public function test_tenants_cannot_read_edit_delete_or_link_each_others_media(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $aId = $this->owner($a)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->json('data.id');

        $this->owner($b)->getJson("/api/v1/salon-media/{$aId}")->assertNotFound();
        $this->owner($b)->patchJson("/api/v1/salon-media/{$aId}", ['caption' => 'hijack'])->assertNotFound();
        $this->owner($b)->deleteJson("/api/v1/salon-media/{$aId}")->assertNotFound();
        $this->assertSame([], $this->owner($b)->getJson('/api/v1/salon-media')->json('data'));
        $this->assertNull(SalonMedia::withoutGlobalScope('tenant')->findOrFail($aId)->caption);

        // Cannot attach another tenant's branch/service, and a client tenant_id is ignored.
        $this->owner($b)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/BBB/', 'branch_id' => $a['branch']->id])->assertUnprocessable()->assertJsonValidationErrors('branch_id');
        $this->owner($b)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/BBB/', 'service_id' => $a['service']->id])->assertUnprocessable()->assertJsonValidationErrors('service_id');
        $created = $this->owner($b)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/BBB/', 'tenant_id' => $a['tenant']->id])->assertCreated()->json('data.id');
        $this->assertSame($b['tenant']->id, SalonMedia::withoutGlobalScope('tenant')->findOrFail($created)->tenant_id);
    }

    public function test_a_service_must_belong_to_the_selected_branch(): void
    {
        $f = $this->fixture('a');
        app(TenantContext::class)->set($f['tenant']);
        $otherBranch = Branch::query()->create(['salon_id' => $f['salon']->id, 'name' => 'Second', 'slug' => 'second', 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/', 'branch_id' => $otherBranch->id, 'service_id' => $f['service']->id])
            ->assertUnprocessable()->assertJsonValidationErrors('service_id');
    }

    public function test_customers_and_staff_cannot_manage_the_gallery_and_guests_are_rejected(): void
    {
        $f = $this->fixture('a');
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $this->actingAs($customer, 'sanctum')->withHeader('X-Tenant-Slug', $f['tenant']->slug)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->assertForbidden();
        $this->app['auth']->forgetGuards();
        $this->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->assertUnauthorized();
        $this->getJson("/api/v1/branches/{$f['branch']->id}/gallery")->assertUnauthorized();
    }

    public function test_customer_gallery_lists_only_active_items_for_salon_wide_or_this_branch_with_pagination(): void
    {
        $f = $this->fixture('a');
        app(TenantContext::class)->set($f['tenant']);
        $branch2 = Branch::query()->create(['salon_id' => $f['salon']->id, 'name' => 'Second', 'slug' => 'second', 'status' => BusinessStatus::ACTIVE]);
        SalonMedia::query()->create(['source' => 'instagram', 'instagram_url' => 'https://www.instagram.com/reel/WIDE/', 'is_active' => true, 'sort_order' => 1, 'category' => 'haircut']);
        SalonMedia::query()->create(['source' => 'instagram', 'instagram_url' => 'https://www.instagram.com/reel/B1/', 'branch_id' => $f['branch']->id, 'is_active' => true, 'sort_order' => 2, 'category' => 'styling']);
        SalonMedia::query()->create(['source' => 'instagram', 'instagram_url' => 'https://www.instagram.com/reel/B2/', 'branch_id' => $branch2->id, 'is_active' => true, 'sort_order' => 3]);
        SalonMedia::query()->create(['source' => 'instagram', 'instagram_url' => 'https://www.instagram.com/reel/HIDDEN/', 'is_active' => false, 'sort_order' => 4]);
        app(TenantContext::class)->clear();
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum');

        $response = $api->getJson("/api/v1/branches/{$f['branch']->id}/gallery")->assertOk();
        $urls = collect($response->json('data'))->pluck('instagram_url')->all();
        $this->assertSame(['https://www.instagram.com/reel/WIDE/', 'https://www.instagram.com/reel/B1/'], $urls);
        $this->assertArrayNotHasKey('is_active', $response->json('data.0'));
        $this->assertArrayNotHasKey('source', $response->json('data.0'));

        $api->getJson("/api/v1/branches/{$f['branch']->id}/gallery?per_page=1")->assertOk()->assertJsonCount(1, 'data');
        $api->getJson("/api/v1/branches/{$f['branch']->id}/gallery?per_page=1&page=2")->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.instagram_url', 'https://www.instagram.com/reel/B1/');
        $api->getJson("/api/v1/branches/{$f['branch']->id}/gallery?per_page=1&page=3")->assertOk()->assertJsonCount(0, 'data');
        $api->getJson("/api/v1/branches/{$f['branch']->id}/gallery?category=styling")->assertOk()->assertJsonCount(1, 'data');
        $api->getJson("/api/v1/branches/{$f['branch']->id}/gallery?category=bogus")->assertUnprocessable();
    }

    public function test_customer_gallery_never_leaks_another_tenants_media_and_honours_the_brand_guard(): void
    {
        $a = $this->fixture('a');
        $b = $this->fixture('b');
        $this->owner($a)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/'])->assertCreated();
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum');

        $this->assertSame([], $api->getJson("/api/v1/branches/{$b['branch']->id}/gallery")->json('data'));

        config(['brand_apps.test_brand' => $b['tenant']->id]);
        $api->getJson("/api/v1/branches/{$a['branch']->id}/gallery", ['X-App-Brand' => 'test_brand'])->assertForbidden();
        $api->getJson("/api/v1/branches/{$b['branch']->id}/gallery", ['X-App-Brand' => 'test_brand'])->assertOk();
    }

    public function test_customer_gallery_hides_the_service_link_when_the_service_is_inactive_and_exposes_it_otherwise(): void
    {
        $f = $this->fixture('a');
        $this->owner($f)->postJson('/api/v1/salon-media', ['instagram_url' => 'https://www.instagram.com/reel/AAA/', 'service_id' => $f['service']->id])->assertCreated();
        $customer = User::factory()->create(['role' => UserRole::CUSTOMER]);
        $api = $this->actingAs($customer, 'sanctum');

        $api->getJson("/api/v1/branches/{$f['branch']->id}/gallery")->assertJsonPath('data.0.service.id', $f['service']->id);

        Service::withoutGlobalScope('tenant')->whereKey($f['service']->id)->update(['status' => BusinessStatus::INACTIVE->value]);
        $api->getJson("/api/v1/branches/{$f['branch']->id}/gallery")->assertJsonPath('data.0.service', null);
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
        app(TenantContext::class)->set($tenant);
        $salon = Salon::query()->create(['name' => $slug, 'slug' => $slug, 'gender_type' => GenderType::UNISEX, 'status' => BusinessStatus::ACTIVE]);
        $branch = Branch::query()->create(['salon_id' => $salon->id, 'name' => 'Main', 'slug' => 'main', 'status' => BusinessStatus::ACTIVE]);
        $category = ServiceCategory::query()->create(['branch_id' => $branch->id, 'name' => 'Hair', 'slug' => 'hair', 'status' => BusinessStatus::ACTIVE]);
        $service = Service::query()->create(['branch_id' => $branch->id, 'category_id' => $category->id, 'name' => 'Haircut', 'slug' => 'haircut', 'gender' => GenderType::UNISEX, 'price' => 300, 'duration_minutes' => 30, 'status' => BusinessStatus::ACTIVE]);
        app(TenantContext::class)->clear();

        return compact('tenant', 'owner', 'salon', 'branch', 'category', 'service');
    }
}
