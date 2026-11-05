import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_storage_service.dart';

void main() {
  late Directory temporary;
  late Directory external;
  late Directory documents;
  late Directory support;

  AnimationStorageService service({
    String platform = 'android',
    AnimationDirectoryProvider? externalProvider,
    AnimationDirectoryProvider? documentsProvider,
    AnimationDirectoryProvider? supportProvider,
  }) =>
      AnimationStorageService(
        operatingSystem: platform,
        externalDirectory: externalProvider ?? () async => external,
        documentsDirectory: documentsProvider ?? () async => documents,
        supportDirectory: supportProvider ?? () async => support,
      );

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('healthmap-storage-');
    // Deliberately absent: resolving candidate paths must not create them.
    external = Directory(p.join(temporary.path, 'external'));
    documents = Directory(p.join(temporary.path, 'documents'));
    support = Directory(p.join(temporary.path, 'support'));
  });

  tearDown(() async {
    expect(await temporary.list().toList(), isEmpty);
    expect(
        p.isWithin(Directory.systemTemp.absolute.path, temporary.path), isTrue);
    expect(p.basename(temporary.path), startsWith('healthmap-storage-'));
    await temporary.delete();
  });

  test('Android canonical root prefers external without looking up Documents',
      () async {
    final storage = service(documentsProvider: () async {
      fail('Documents must not be requested');
    });
    expect((await storage.getCanonicalRoot()).path, external.path);
  });

  test('Android null external root falls back to Documents', () async {
    expect(
        (await service(externalProvider: () async => null).getCanonicalRoot())
            .path,
        documents.path);
  });

  test('Android throwing external lookup falls back to Documents', () async {
    for (final error in [
      const FileSystemException('unavailable'),
      UnsupportedError('unavailable'),
    ]) {
      final storage = service(externalProvider: () async => throw error);
      expect((await storage.getCanonicalRoot()).path, documents.path);
    }
  });

  test('iOS canonical root is Support and never requests external storage',
      () async {
    final storage = service(
      platform: 'ios',
      externalProvider: () async => fail('External must not be requested'),
      documentsProvider: () async => fail('Documents must not be requested'),
    );
    expect((await storage.getCanonicalRoot()).path, support.path);
  });

  test('normalizes canonical paths for each provider branch', () async {
    Directory alias(Directory root) =>
        Directory(p.join(root.path, 'unused', '..', '.'));
    final cases = [
      (service(externalProvider: () async => alias(external)), external),
      (
        service(
            externalProvider: () async => null,
            documentsProvider: () async => alias(documents)),
        documents
      ),
      (
        service(platform: 'ios', supportProvider: () async => alias(support)),
        support
      ),
      (
        service(
            externalProvider: () async => Directory(p
                .relative(alias(external).path, from: Directory.current.path))),
        external
      ),
    ];
    for (final (storage, expected) in cases) {
      final root = await storage.getCanonicalRoot();
      expect(root.path, expected.path);
      expect(p.isAbsolute(root.path), isTrue);
    }
  });

  test('Android unavailable Documents fallback fails safely', () async {
    for (final externalProvider in <AnimationDirectoryProvider>[
      () async => null,
      () async => throw const FileSystemException('External unavailable'),
    ]) {
      await expectLater(
        service(
            externalProvider: externalProvider,
            documentsProvider: () async => null).getCanonicalRoot(),
        throwsA(isA<FileSystemException>()),
      );
      final error = const FileSystemException('Documents unavailable');
      await expectLater(
        service(
            externalProvider: externalProvider,
            documentsProvider: () async => throw error).getCanonicalRoot(),
        throwsA(same(error)),
      );
    }
  });

  test('iOS Support lookup failure propagates without falling back', () async {
    final error = const FileSystemException('Support unavailable');
    await expectLater(
      service(
              platform: 'ios',
              supportProvider: () async => throw error,
              documentsProvider: () async => fail('No Documents fallback'))
          .getCanonicalRoot(),
      throwsA(same(error)),
    );
  });

  test('missing canonical root fails instead of using an incorrect iOS root',
      () async {
    await expectLater(
      service(platform: 'ios', supportProvider: () async => null)
          .getCanonicalRoot(),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('unsupported platforms fail before any provider is called', () async {
    for (final platform in ['windows', 'linux', 'macos']) {
      final storage = service(
        platform: platform,
        externalProvider: () async => fail('Unexpected provider call'),
        documentsProvider: () async => fail('Unexpected provider call'),
        supportProvider: () async => fail('Unexpected provider call'),
      );
      await expectLater(storage.getCanonicalRoot(), throwsUnsupportedError);
    }
  });
}
