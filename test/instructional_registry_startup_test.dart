import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wired_test/main.dart';
import 'package:wired_test/services/module_installation_registry.dart';

class _StartupRegistry extends ModuleInstallationRegistry {
  final completion = Completer<Box>();
  String? directory;
  @override
  Future<Box> initialize({required String? storageDirectory}) {
    directory = storageDirectory;
    return completion.future;
  }
}

void main() {
  testWidgets('registry failure logs a diagnostic and permits app startup',
      (tester) async {
    final registry = _StartupRegistry();
    final logs = <String>[];
    final startup = initializeInstructionalRegistryForStartup(
        storageDirectory: '/existing-hive-root',
        registry: registry,
        log: logs.add);
    registry.completion.completeError(StateError('storage unavailable'));
    await startup;
    await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('Application continues')));
    expect(find.text('Application continues'), findsOneWidget);
    expect(registry.directory, '/existing-hive-root');
    expect(logs.single, contains('storage unavailable'));
    expect(logs.single, contains('continuing startup'));
  });

  test('startup awaits registry readiness and keeps the real box open',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('registry_startup_');
    Hive.init(directory.path);
    try {
      final logs = <String>[];
      await initializeInstructionalRegistryForStartup(
          storageDirectory: directory.path, log: logs.add);
      expect(Hive.isBoxOpen(ModuleInstallationRegistry.boxName), isTrue);
      expect(logs, isEmpty);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });

  test('startup does not continue until initialization settles', () async {
    final registry = _StartupRegistry();
    var continued = false;
    final startup = initializeInstructionalRegistryForStartup(
      storageDirectory: '/existing-hive-root',
      registry: registry,
      log: (_) {},
    ).then((_) {
      continued = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(continued, isFalse);
    registry.completion.completeError(StateError('failed attempt'));
    await startup;
    expect(continued, isTrue);
  });
}
