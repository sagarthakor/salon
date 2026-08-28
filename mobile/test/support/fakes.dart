import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/storage/secure_storage.dart';
import 'package:salon_customer/features/auth/data/repositories/auth_repository.dart';
import 'package:salon_customer/features/booking/data/repositories/booking_repository.dart';
import 'package:salon_customer/features/owner/billing/data/repositories/subscription_repository.dart';
import 'package:salon_customer/features/owner/branches/data/repositories/owner_branch_repository.dart';
import 'package:salon_customer/features/owner/customers/data/repositories/owner_customer_repository.dart';
import 'package:salon_customer/features/owner/dashboard/data/repositories/dashboard_repository.dart';
import 'package:salon_customer/features/owner/salon/data/repositories/owner_salon_repository.dart';
import 'package:salon_customer/features/owner/services/data/repositories/owner_service_repository.dart';
import 'package:salon_customer/features/owner/staff/data/repositories/staff_repository.dart';
import 'package:salon_customer/features/notifications/data/repositories/notification_repository.dart';
import 'package:salon_customer/features/profile/data/repositories/profile_repository.dart';
import 'package:salon_customer/features/salon/data/repositories/salon_repository.dart';
import 'package:salon_customer/features/services/data/repositories/service_repository.dart';

/// In-memory stand-in for [SecureStorage] so widget tests never touch a real
/// platform channel (which would throw `MissingPluginException` under
/// `flutter_test`).
class FakeSecureStorage implements SecureStorage {
  String? _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> clearToken() async => _token = null;
}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBookingRepository extends Mock implements BookingRepository {}

class MockServiceRepository extends Mock implements ServiceRepository {}

class MockSalonRepository extends Mock implements SalonRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

// --- Owner/admin surface (Phase 8) ---

class MockDashboardRepository extends Mock implements DashboardRepository {}

class MockStaffRepository extends Mock implements StaffRepository {}

class MockOwnerCustomerRepository extends Mock implements OwnerCustomerRepository {}

class MockOwnerServiceRepository extends Mock implements OwnerServiceRepository {}

class MockOwnerBranchRepository extends Mock implements OwnerBranchRepository {}

class MockOwnerSalonRepository extends Mock implements OwnerSalonRepository {}

// --- Billing / subscription (Phase 10) ---

class MockSubscriptionRepository extends Mock implements SubscriptionRepository {}

// --- Notifications (Phase 11) ---

class MockNotificationRepository extends Mock implements NotificationRepository {}
