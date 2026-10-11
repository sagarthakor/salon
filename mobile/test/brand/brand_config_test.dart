import 'package:flutter_test/flutter_test.dart';
import 'package:salon_customer/core/brand/brand_config.dart';

void main() {
  test('BrandConfig.standard is the unbranded multi-tenant app, with discovery enabled', () {
    expect(BrandConfig.standard.singleSalon, isFalse);
    expect(BrandConfig.standard.tenantId, isNull);
    expect(BrandConfig.standard.brandHeaderValue, isNull, reason: 'the default app must never send X-App-Brand');
  });

  test('BrandConfig.nilHairPort is locked to the verified production tenant id', () {
    expect(BrandConfig.nilHairPort.singleSalon, isTrue);
    expect(BrandConfig.nilHairPort.tenantId, '01m16303p8xgzejrr9ezvtvwfv');
    expect(BrandConfig.nilHairPort.appName, 'Nil Hair Port Unisex');
    expect(BrandConfig.nilHairPort.brandHeaderValue, 'nil_hair_port');
  });

  test('BrandConfig.current defaults to standard until an entrypoint overrides it', () {
    expect(BrandConfig.current, BrandConfig.standard);
  });
}
