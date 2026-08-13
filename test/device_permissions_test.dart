import 'package:flutter_test/flutter_test.dart';
import 'package:asa/core/device_permissions.dart';

void main() {
  setUp(() {
    DevicePermissions.localNetworkPermissionOverride = null;
  });

  group('DevicePermissions', () {
    test(
      'requests local network permission through the platform hook',
      () async {
        DevicePermissions.localNetworkPermissionOverride = () async => false;

        expect(
          await DevicePermissions.requestLocalNetworkPermission(),
          isFalse,
        );
      },
    );
  });
}
