/// Mirrors `App\Enums\UserRole` (`super_admin`, `salon_owner`, `staff`,
/// `customer`) and groups it into what this single Flutter codebase can
/// currently route to. This is a navigation/UX convenience only — every
/// actual permission check happens server-side (see `TenantManagementController`,
/// `TenantPolicy`, `StaffPolicy` in the Laravel app); a role misclassified
/// here would at worst show the wrong screen, never grant real access,
/// since every API call is still independently authorized by the backend.
enum AppRole {
  customer,
  ownerAdmin,
  staff,
  unknown;

  /// [backendRole] is the raw string from `UserResource.role`
  /// (`AppUser.role`) — never invented, always the literal backend enum value.
  static AppRole fromBackendRole(String backendRole) => switch (backendRole) {
    'customer' => AppRole.customer,
    'salon_owner' || 'super_admin' => AppRole.ownerAdmin,
    'staff' => AppRole.staff,
    _ => AppRole.unknown,
  };
}
