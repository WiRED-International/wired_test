import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Use the installed plugin's platform adapter without native network access.
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:wired_test/utils/network_utils.dart';

class _Connectivity extends ConnectivityPlatform {
  List<ConnectivityResult> results = [];
  PlatformException? error;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (error != null) throw error!;
    return results;
  }
}

void main() {
  late ConnectivityPlatform original;
  late _Connectivity platform;

  setUp(() {
    original = ConnectivityPlatform.instance;
    platform = _Connectivity();
    ConnectivityPlatform.instance = platform;
  });

  tearDown(() => ConnectivityPlatform.instance = original);

  for (final scenario in [
    (name: 'no network', results: [ConnectivityResult.none], available: false),
    (name: 'Wi-Fi', results: [ConnectivityResult.wifi], available: true),
    (name: 'mobile', results: [ConnectivityResult.mobile], available: true),
    (
      name: 'multiple active interfaces',
      results: [ConnectivityResult.wifi, ConnectivityResult.mobile],
      available: true,
    ),
    (name: 'empty results', results: <ConnectivityResult>[], available: false),
    (
      name: 'none alongside an active interface',
      results: [ConnectivityResult.none, ConnectivityResult.wifi],
      available: false,
    ),
  ]) {
    test('${scenario.name} reports availability without a DNS prerequisite',
        () async {
      platform.results = scenario.results;
      // A platform-only result must complete without waiting for external I/O.
      bool? available;
      final request =
          NetworkUtils.isOnline().then((value) => available = value);
      await pumpEventQueue();
      expect(available, scenario.available);
      await request;
    });
  }

  test('plugin exceptions propagate as before for callers to handle', () async {
    final error = PlatformException(code: 'unavailable');
    platform.error = error;
    await expectLater(NetworkUtils.isOnline(), throwsA(same(error)));
  });
}
