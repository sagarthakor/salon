<?php

namespace Tests\Unit;

use App\Support\InstagramUrl;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

class InstagramUrlShortcodeTest extends TestCase
{
    /** @return array<string, array{0: string}> */
    public static function equivalentSpellings(): array
    {
        return [
            'canonical' => ['https://www.instagram.com/reel/AbC_123-x/'],
            'no www' => ['https://instagram.com/reel/AbC_123-x/'],
            'no trailing slash' => ['https://www.instagram.com/reel/AbC_123-x'],
            'share query' => ['https://www.instagram.com/reel/AbC_123-x/?igsh=MWRh'],
            'utm query no slash' => ['https://instagram.com/reel/AbC_123-x?utm_source=ig_web_copy_link'],
            'post path' => ['https://www.instagram.com/p/AbC_123-x/'],
            'username-prefixed permalink' => ['https://www.instagram.com/nil_hairport_unisex/reel/AbC_123-x/'],
            'upper-case host' => ['https://WWW.Instagram.COM/reel/AbC_123-x/'],
        ];
    }

    #[DataProvider('equivalentSpellings')]
    public function test_every_equivalent_spelling_yields_the_same_shortcode(string $url): void
    {
        $this->assertSame('AbC_123-x', InstagramUrl::shortcode($url));
    }

    public function test_shortcode_is_case_sensitive_and_rejects_non_post_or_foreign_urls(): void
    {
        $this->assertSame('abc', InstagramUrl::shortcode('https://www.instagram.com/reel/abc/'));
        $this->assertNull(InstagramUrl::shortcode('https://www.instagram.com/nil_hairport_unisex/'));
        $this->assertNull(InstagramUrl::shortcode('https://evil.example/reel/abc/'));
        $this->assertNull(InstagramUrl::shortcode('http://www.instagram.com/reel/abc/'));
        $this->assertNull(InstagramUrl::shortcode('javascript:alert(1)'));
        $this->assertNull(InstagramUrl::shortcode('https://notinstagram.com/reel/abc/'));
    }

    public function test_canonical_drops_query_and_host_variants_and_rejects_invalid_links(): void
    {
        $this->assertSame('https://www.instagram.com/reel/AbC/', InstagramUrl::canonical('https://instagram.com/reel/AbC?igsh=1'));
        $this->assertSame('https://www.instagram.com/p/AbC/', InstagramUrl::canonical('https://www.instagram.com/p/AbC/'));
        $this->assertNull(InstagramUrl::canonical('https://www.instagram.com/someuser/'));
        $this->assertNull(InstagramUrl::canonical('https://evil.example/reel/AbC/'));
    }
}
