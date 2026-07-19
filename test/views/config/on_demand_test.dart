import 'package:fl_clash/views/config/on_demand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_ssid/wifi_ssid.dart';

void main() {
  test('location permission follow-up preserves all three states', () {
    expect(
      locationPermissionFollowUp(WifiSsidPermission.granted),
      LocationPermissionFollowUp.none,
    );
    expect(
      locationPermissionFollowUp(WifiSsidPermission.denied),
      LocationPermissionFollowUp.promptSettings,
    );
    expect(
      locationPermissionFollowUp(WifiSsidPermission.permanentlyDenied),
      LocationPermissionFollowUp.openSettings,
    );
  });
}
