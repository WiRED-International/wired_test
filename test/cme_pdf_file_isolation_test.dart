import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wired_test/utils/pdf_utils.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform original;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cme_file_isolation_test_');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = original;
    await root.delete(recursive: true);
  });

  for (final concurrent in [false, true]) {
    test(
        '${concurrent ? 'concurrent' : 'sequential'} files have independent paths and bytes',
        () async {
      final firstBytes = Uint8List.fromList([1, 2, 3]);
      final secondBytes = Uint8List.fromList([4, 5, 6]);
      final first = generateAndSavePdfToFile(firstBytes, 'cme_history.pdf');
      if (!concurrent) await first;
      final second = generateAndSavePdfToFile(secondBytes, 'cme_history.pdf');
      final files = await Future.wait([first, second]);
      expect(files[0].path, isNot(files[1].path));
      expect(files[0].parent.path, isNot(files[1].parent.path));
      for (final file in files) {
        expect(file.uri.pathSegments.last, 'cme_history.pdf');
        expect(file.parent.parent.path, root.path);
      }
      expect(await files[0].readAsBytes(), firstBytes);
      expect(await files[1].readAsBytes(), secondBytes);
      await files[0].delete();
      expect(await files[1].readAsBytes(), secondBytes);
    });
  }

  test(
      'write failure removes only its allocated directory and preserves the error',
      () async {
    final kept = await generateAndSavePdfToFile(
        Uint8List.fromList([7]), 'cme_history.pdf');
    // The nested parent does not exist, so the write fails after allocation.
    await expectLater(
      generateAndSavePdfToFile(
          Uint8List.fromList([8]), 'missing/cme_history.pdf'),
      throwsA(isA<FileSystemException>()),
    );
    expect((await root.list().toList()).map((entry) => entry.path),
        [kept.parent.path]);
    expect(await kept.readAsBytes(), [7]);
  });

  test('sweep removes only old recognized exports and keeps recent PDFs',
      () async {
    final old = await generateAndSavePdfToFile(
        Uint8List.fromList([1]), 'cme_history.pdf');
    final recent = await generateAndSavePdfToFile(
        Uint8List.fromList([2]), 'cme_history.pdf');
    final unrelated = await Directory('${root.path}/other_export').create();
    final unrelatedFile =
        await File('${unrelated.path}/keep.pdf').writeAsString('keep');
    final unknown =
        await Directory('${root.path}/cme_history_unknown').create();
    await File('${unknown.path}/other.txt').writeAsString('keep');
    final empty = await Directory('${root.path}/cme_history_empty').create();
    final now = DateTime.now().add(const Duration(days: 8));
    await recent.setLastModified(now.subtract(const Duration(days: 1)));
    await cleanupOldCmePdfExports(root: root, now: now);
    expect(await old.parent.exists(), isFalse);
    expect(await recent.readAsBytes(), [2]);
    expect(await unrelatedFile.readAsString(), 'keep');
    expect(await unknown.exists(), isTrue);
    expect(await empty.exists(), isFalse);
  });

  test('current exports survive automatic sweep before another export',
      () async {
    final first = await generateAndSavePdfToFile(
        Uint8List.fromList([1]), 'cme_history.pdf');
    await generateAndSavePdfToFile(Uint8List.fromList([2]), 'cme_history.pdf');
    expect(await first.readAsBytes(), [1]);
  });

  test('active old PDF is retained until all preview pins are released',
      () async {
    final file = await generateAndSavePdfToFile(
        Uint8List.fromList([1]), 'cme_history.pdf');
    final now = DateTime.now().add(const Duration(days: 8));
    retainCmePdf(file);
    retainCmePdf(file);
    try {
      await cleanupOldCmePdfExports(root: root, now: now);
      expect(await file.exists(), isTrue);
      releaseCmePdf(file);
      await cleanupOldCmePdfExports(root: root, now: now);
      expect(await file.exists(), isTrue);
    } finally {
      releaseCmePdf(file);
    }
    await cleanupOldCmePdfExports(root: root, now: now);
    expect(await file.parent.exists(), isFalse);
  });

  test('cleanup enumeration failure does not prevent PDF creation', () async {
    await cleanupOldCmePdfExports(root: Directory('${root.path}/missing'));
    final file = await generateAndSavePdfToFile(
        Uint8List.fromList([7]), 'cme_history.pdf');
    expect(await file.readAsBytes(), [7]);
  });
}
