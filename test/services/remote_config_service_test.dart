import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/config/firebase_config.dart';
import 'package:pos_app/services/remote_config_service.dart';

void main() {
  group('RemoteConfigService.parseTrialDays', () {
    test('parses valid numeric string', () {
      expect(RemoteConfigService.parseTrialDays('5'), 5);
    });

    test('parses integer value directly', () {
      expect(RemoteConfigService.parseTrialDays(6), 6);
    });

    test('clamps values above maximum to 7', () {
      expect(RemoteConfigService.parseTrialDays('9999'), 7);
    });

    test('clamps negative values to zero', () {
      expect(RemoteConfigService.parseTrialDays('-5'), 0);
    });

    test('falls back to default on non-numeric text', () {
      expect(
        RemoteConfigService.parseTrialDays('abc'),
        FirebaseConfig.trialDays,
      );
    });

    test('falls back to default on empty string', () {
      expect(
        RemoteConfigService.parseTrialDays(''),
        FirebaseConfig.trialDays,
      );
    });

    test('falls back to default on null', () {
      expect(
        RemoteConfigService.parseTrialDays(null),
        FirebaseConfig.trialDays,
      );
    });
  });
}
