import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/features/profile/data/models/customer_profile.dart';
import 'package:salon_customer/features/salon/data/models/address.dart';
import 'package:salon_customer/features/salon/data/models/branch.dart';
import 'package:salon_customer/features/salon/data/models/salon.dart';
import 'package:salon_customer/features/services/data/models/salon_service.dart';

void main() {
  group('Salon.fromJson', () {
    test('parses instagram_url — the salon\'s own official profile link, separate from any service\'s', () {
      final json = {
        'id': 'sal_1',
        'name': 'Prime Hair Studio',
        'slug': 'prime-hair-studio',
        'gender_type': 'unisex',
        'instagram_url': 'https://www.instagram.com/primehairstudio/',
        'address': null,
        'status': 'active',
      };

      final salon = Salon.fromJson(json);

      expect(salon.instagramUrl, 'https://www.instagram.com/primehairstudio/');
    });

    test('instagram_url is null when absent (existing salons keep working)', () {
      final json = {
        'id': 'sal_1',
        'name': 'Prime Hair Studio',
        'slug': 'prime-hair-studio',
        'gender_type': 'unisex',
        'address': null,
        'status': 'active',
      };

      final salon = Salon.fromJson(json);

      expect(salon.instagramUrl, isNull);
    });
  });

  group('SalonService.fromJson', () {
    test('parses price as a num from the decimal-cast string the backend sends', () {
      final json = {
        'id': 'sv_1',
        'branch_id': 'br_1',
        'category': {
          'id': 'cat_1',
          'branch_id': 'br_1',
          'name': 'Hair',
          'slug': 'hair',
          'status': 'active',
          'sort_order': 0,
        },
        'name': 'Haircut',
        'slug': 'haircut',
        'gender': 'unisex',
        'price': '300.00',
        'duration_minutes': 30,
        'status': 'active',
        'sort_order': 0,
      };

      final service = SalonService.fromJson(json);

      expect(service.price, 300);
      expect(service.durationMinutes, 30);
      expect(service.category?.name, 'Hair');
      expect(service.isActive, isTrue);
    });

    test('parses image_url, description, and instagram_url', () {
      final json = {
        'id': 'sv_1',
        'branch_id': 'br_1',
        'name': 'Haircut',
        'slug': 'haircut',
        'description': 'A precision fade with hot towel finish.',
        'gender': 'unisex',
        'price': '300.00',
        'duration_minutes': 30,
        'image_url': 'https://cdn.example.test/storage/services/haircut.jpg',
        'instagram_url': 'https://www.instagram.com/reel/Cabc123/',
        'status': 'active',
        'sort_order': 0,
      };

      final service = SalonService.fromJson(json);

      expect(service.imageUrl, 'https://cdn.example.test/storage/services/haircut.jpg');
      expect(service.description, 'A precision fade with hot towel finish.');
      expect(service.instagramUrl, 'https://www.instagram.com/reel/Cabc123/');
    });

    test('image_url, description, and instagram_url are all null when absent (existing services keep working)', () {
      final json = {
        'id': 'sv_1',
        'branch_id': 'br_1',
        'name': 'Haircut',
        'slug': 'haircut',
        'gender': 'unisex',
        'price': '300.00',
        'duration_minutes': 30,
        'status': 'active',
        'sort_order': 0,
      };

      final service = SalonService.fromJson(json);

      expect(service.imageUrl, isNull);
      expect(service.description, isNull);
      expect(service.instagramUrl, isNull);
    });

    test('category is null when not eager-loaded', () {
      final json = {
        'id': 'sv_1',
        'branch_id': 'br_1',
        'name': 'Haircut',
        'slug': 'haircut',
        'gender': 'unisex',
        'price': '300.00',
        'duration_minutes': 30,
        'status': 'inactive',
        'sort_order': 0,
      };

      final service = SalonService.fromJson(json);

      expect(service.category, isNull);
      expect(service.isActive, isFalse);
    });
  });

  group('Address', () {
    test('singleLine skips null/empty parts', () {
      final address = Address.fromJson({'line_1': 'Shop 4', 'city': 'Vadodara', 'country': null});
      expect(address.singleLine, 'Shop 4, Vadodara');
      expect(address.isEmpty, isFalse);
    });

    test('is empty when every part is null', () {
      final address = Address.fromJson(null);
      expect(address.isEmpty, isTrue);
    });
  });

  group('Branch.fromJson', () {
    test('isActive reflects the status field', () {
      final active = Branch.fromJson({
        'id': 'br_1',
        'name': 'Main',
        'slug': 'main',
        'timezone': 'UTC',
        'status': 'active',
      });
      final inactive = Branch.fromJson({
        'id': 'br_2',
        'name': 'Old',
        'slug': 'old',
        'timezone': 'UTC',
        'status': 'inactive',
      });

      expect(active.isActive, isTrue);
      expect(inactive.isActive, isFalse);
    });
  });

  group('CustomerProfile.fromJson', () {
    test('parses the self-service profile shape and never carries notes', () {
      final profile = CustomerProfile.fromJson({
        'id': 'cu_1',
        'user_id': 3,
        'name': 'Rahul',
        'phone': '9876543210',
        'country_code': '+91',
        'email': 'rahul@example.test',
        'gender': 'male',
        'date_of_birth': '1995-01-01',
        'profile_photo': null,
        'address': null,
        'status': 'active',
      });

      expect(profile.name, 'Rahul');
      expect(profile.countryCode, '+91');
      expect(profile.status, 'active');
    });
  });
}
