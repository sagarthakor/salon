import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salon_customer/core/network/api_client.dart';
import 'package:salon_customer/features/auth/data/repositories/auth_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient client;

  setUp(() {
    client = MockApiClient();
  });

  group('AuthRepository.registerOwner', () {
    test('posts to /auth/register-owner with all fields including slug when supplied', () async {
      when(() => client.post<Map<String, dynamic>>(any(), data: captureAny(named: 'data'))).thenAnswer(
        (_) async => {
          'user': {'id': 9, 'name': 'Asha Owner', 'email': 'asha-owner@example.test', 'role': 'salon_owner'},
          'token': 'owner-token',
          'tenant_slug': 'asha-hair-studio',
        },
      );

      final result = await AuthRepository(client).registerOwner(
        name: 'Asha Owner',
        email: 'asha-owner@example.test',
        password: 'SecurePassword1!',
        passwordConfirmation: 'SecurePassword1!',
        salonName: 'Asha Hair Studio',
        slug: 'my-custom-slug',
      );

      final captured = verify(() => client.post<Map<String, dynamic>>('/auth/register-owner', data: captureAny(named: 'data'))).captured.single as Map;
      expect(captured['name'], 'Asha Owner');
      expect(captured['email'], 'asha-owner@example.test');
      expect(captured['password'], 'SecurePassword1!');
      expect(captured['password_confirmation'], 'SecurePassword1!');
      expect(captured['salon_name'], 'Asha Hair Studio');
      expect(captured['slug'], 'my-custom-slug');

      expect(result.user.email, 'asha-owner@example.test');
      expect(result.user.role, 'salon_owner');
      expect(result.token, 'owner-token');
      expect(result.tenantSlug, 'asha-hair-studio');
    });

    test('omits slug from the request body entirely when not supplied, never sending a literal null', () async {
      when(() => client.post<Map<String, dynamic>>(any(), data: captureAny(named: 'data'))).thenAnswer(
        (_) async => {
          'user': {'id': 10, 'name': 'Owner Two', 'email': 'owner2@example.test', 'role': 'salon_owner'},
          'token': 'owner-token-2',
          'tenant_slug': 'owner-two-salon',
        },
      );

      await AuthRepository(client).registerOwner(
        name: 'Owner Two',
        email: 'owner2@example.test',
        password: 'SecurePassword1!',
        passwordConfirmation: 'SecurePassword1!',
        salonName: 'Owner Two Salon',
      );

      final captured = verify(() => client.post<Map<String, dynamic>>('/auth/register-owner', data: captureAny(named: 'data'))).captured.single as Map;
      expect(captured.containsKey('slug'), isFalse);
    });
  });
}
