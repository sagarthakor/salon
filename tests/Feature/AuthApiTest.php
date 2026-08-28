<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_customer_can_register_and_receive_a_token(): void
    {
        $response = $this->postJson('/api/v1/auth/register', ['name' => 'Asha Customer', 'email' => 'asha@example.test', 'password' => 'SecurePassword1!', 'password_confirmation' => 'SecurePassword1!', 'role' => 'super_admin', 'tenant_id' => 'untrusted']);

        $response->assertCreated()->assertJsonPath('success', true)->assertJsonPath('data.user.role', 'customer')->assertJsonStructure(['data' => ['token']]);
        $this->assertDatabaseHas('users', ['email' => 'asha@example.test', 'role' => UserRole::CUSTOMER->value]);
    }

    public function test_a_user_can_login_logout_and_retrieve_their_profile(): void
    {
        $user = User::factory()->create(['email' => 'login@example.test', 'password' => 'SecurePassword1!']);
        $login = $this->postJson('/api/v1/auth/login', ['email' => $user->email, 'password' => 'SecurePassword1!'])->assertOk();
        $token = $login->json('data.token');

        $this->withToken($token)->getJson('/api/v1/auth/me')->assertOk()->assertJsonPath('data.email', $user->email);
        $this->withToken($token)->postJson('/api/v1/auth/logout')->assertOk()->assertJsonPath('success', true);
        $this->assertDatabaseCount('personal_access_tokens', 0);
        Auth::forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/me')->assertUnauthorized();
    }

    public function test_invalid_credentials_and_missing_tokens_are_rejected(): void
    {
        $this->postJson('/api/v1/auth/login', ['email' => 'missing@example.test', 'password' => 'wrong'])->assertStatus(422)->assertJsonPath('success', false);
        $this->getJson('/api/v1/auth/me')->assertUnauthorized()->assertJsonPath('success', false);
    }

    /**
     * Regression test found during Phase 15 production smoke testing: every
     * other test in this suite uses `getJson()`/`postJson()`, which Laravel's
     * test helpers force an `Accept: application/json` header for — so none
     * of them could have caught this. A plain `get()` (no forced Accept
     * header, matching a bare curl request, a health-check probe, or any
     * client that doesn't set it) used to 500 instead of 401, because
     * Laravel's default `redirectGuestsTo` tries to build a URL for a
     * `login` route this pure-API app has never defined. Fixed in
     * `bootstrap/app.php` via `redirectGuestsTo(fn () => null)`.
     */
    public function test_an_unauthenticated_request_without_an_accept_header_still_gets_401_not_500(): void
    {
        $this->get('/api/v1/auth/me')->assertUnauthorized();
    }
}
