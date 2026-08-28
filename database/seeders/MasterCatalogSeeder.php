<?php

namespace Database\Seeders;

use App\Enums\ServiceAudience;
use App\Models\MasterService;
use App\Models\MasterServiceCategory;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * The platform's starting service catalog — a professional template for a
 * general Indian hair/beauty salon, not a claim that every salon offers
 * every service (see MASTER_CATALOG_ARCHITECTURE.md). Safe to run
 * repeatedly: every category/service is `updateOrCreate`d against a stable
 * key (audience+slug for categories, category+slug for services), so
 * re-running never creates duplicates and never touches any tenant's own
 * already-provisioned services — this seeder only ever writes to
 * `master_service_categories`/`master_services`.
 *
 * `duration`/`price` are per-category defaults applied to every service
 * listed under it — a deliberate simplification over hand-tuning ~90
 * individual values, and, per the task's own framing, "suggested/default"
 * data only: the tenant's own `Service.price`/`duration_minutes` (set once
 * at provisioning, then fully independent) is what booking/pricing actually
 * uses. An owner can change either freely with zero effect on this catalog
 * or on any other tenant.
 */
class MasterCatalogSeeder extends Seeder
{
    private const CATALOG = [
        'male' => [
            'Hair' => [
                'duration' => 30, 'price' => 200,
                'services' => ['Hair Cut', 'Hair Wash', 'Hair Styling', 'Hair Blow Dry', 'Hair Color', 'Hair Highlights', 'Hair Spa', 'Hair Treatment', 'Hair Straightening', 'Hair Smoothening'],
            ],
            'Beard & Shaving' => [
                'duration' => 20, 'price' => 100,
                'services' => ['Beard Trim', 'Beard Styling', 'Beard Shaping', 'Clean Shave', 'Beard Color'],
            ],
            'Facial & Skin' => [
                'duration' => 40, 'price' => 500,
                'services' => ['Basic Facial', 'Cleanup', 'Bleach', 'Face Massage'],
            ],
        ],
        'female' => [
            'Hair' => [
                'duration' => 45, 'price' => 400,
                'services' => ['Hair Cut', 'Hair Wash', 'Hair Styling', 'Blow Dry', 'Hair Color', 'Global Hair Color', 'Hair Highlights', 'Balayage', 'Hair Spa', 'Hair Treatment', 'Hair Straightening', 'Hair Smoothening', 'Hair Keratin Treatment'],
            ],
            'Facial & Skin' => [
                'duration' => 45, 'price' => 700,
                'services' => ['Basic Facial', 'Cleanup', 'Fruit Facial', 'Gold Facial', 'Diamond Facial', 'Anti-Aging Facial', 'Bleach', 'Face Massage'],
            ],
            'Threading' => [
                'duration' => 10, 'price' => 50,
                'services' => ['Eyebrow Threading', 'Upper Lip Threading', 'Forehead Threading', 'Full Face Threading'],
            ],
            'Waxing' => [
                'duration' => 20, 'price' => 150,
                'services' => ['Full Arms Wax', 'Half Arms Wax', 'Full Legs Wax', 'Half Legs Wax', 'Underarms Wax', 'Full Body Wax'],
            ],
            'Nails' => [
                'duration' => 30, 'price' => 250,
                'services' => ['Manicure', 'Pedicure', 'Nail Cleaning', 'Nail Polish'],
            ],
            'Makeup' => [
                'duration' => 60, 'price' => 1500,
                'services' => ['Basic Makeup', 'Party Makeup', 'Engagement Makeup', 'Bridal Makeup', 'Reception Makeup'],
            ],
        ],
        'unisex' => [
            'Hair' => [
                'duration' => 35, 'price' => 300,
                'services' => ['Hair Wash', 'Hair Styling', 'Blow Dry', 'Hair Spa', 'Hair Treatment', 'Hair Color'],
            ],
            'Skin' => [
                'duration' => 40, 'price' => 500,
                'services' => ['Cleanup', 'Basic Facial', 'Face Massage'],
            ],
            'Nails' => [
                'duration' => 30, 'price' => 250,
                'services' => ['Manicure', 'Pedicure'],
            ],
            'Spa' => [
                'duration' => 45, 'price' => 800,
                'services' => ['Head Massage', 'Relaxation Massage'],
            ],
        ],
        'kids' => [
            'Hair' => [
                'duration' => 20, 'price' => 150,
                'services' => ['Kids Hair Cut', 'Kids Hair Wash', 'Kids Hair Styling'],
            ],
        ],
    ];

    public function run(): void
    {
        foreach (self::CATALOG as $audienceValue => $categories) {
            $audience = ServiceAudience::from($audienceValue);
            $categorySortOrder = 0;
            foreach ($categories as $categoryName => $definition) {
                $category = MasterServiceCategory::query()->updateOrCreate(
                    ['audience' => $audience->value, 'slug' => Str::slug($audienceValue.' '.$categoryName)],
                    ['name' => $categoryName, 'sort_order' => $categorySortOrder, 'is_active' => true],
                );

                $serviceSortOrder = 0;
                foreach ($definition['services'] as $serviceName) {
                    MasterService::query()->updateOrCreate(
                        ['master_service_category_id' => $category->id, 'slug' => Str::slug($serviceName)],
                        [
                            'audience' => $audience->value,
                            'name' => $serviceName,
                            'default_duration_minutes' => $definition['duration'],
                            'default_price' => $definition['price'],
                            'sort_order' => $serviceSortOrder,
                            'is_active' => true,
                        ],
                    );
                    $serviceSortOrder++;
                }
                $categorySortOrder++;
            }
        }
    }
}
