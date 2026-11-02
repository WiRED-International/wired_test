import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wired_test/services/animation_installation_inspection_service.dart';

void main() {
  final service = AnimationInstallationInspectionService();
  late Directory root;
  late File sentinel;
  const bytes = [0, 1, 2, 3, 255];

  ArchiveFile video(String name, [List<int> content = bytes]) =>
      ArchiveFile(name, content.length, content);
  ArchiveFile directory(String name) =>
      ArchiveFile(name, 0, [])..isFile = false;

  Future<File> zip(List<ArchiveFile> entries) async {
    final archive = Archive();
    for (final entry in entries) {
      archive.addFile(entry);
    }
    final encoded = ZipEncoder().encode(archive);
    // ZipEncoder on Windows marks entries as DOS-created. Encode the Unix
    // creator and mode explicitly for the symlink regression fixture.
    var entryIndex = 0;
    for (var i = 0; i + 46 <= encoded.length; i++) {
      if (encoded[i] == 0x50 &&
          encoded[i + 1] == 0x4b &&
          encoded[i + 2] == 1 &&
          encoded[i + 3] == 2) {
        if (entries[entryIndex].symbolicLink != null) {
          encoded[i + 5] = 3;
          encoded[i + 38] = 0;
          encoded[i + 39] = 0;
          encoded[i + 40] = 0xff;
          encoded[i + 41] = 0xa1;
        }
        entryIndex++;
      }
    }
    final file =
        await File(p.join(root.path, 'fixture.zip')).writeAsBytes(encoded);
    final decoded = ZipDecoder().decodeBytes(await file.readAsBytes());
    expect(decoded.length, entries.length,
        reason: 'ZIP fixture must retain all requested entries');
    return file;
  }

  Future<AnimationInstallationInspection> inspect() =>
      service.inspectInstallation(root: root, animationId: 42);
  String getDestination() => p.join(root.path, 'modules', 'animations', '42');
  Future<File> installedFile(String relative, List<int> content) async {
    final file = File(p.join(getDestination(), relative));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(content);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-inspection-');
    sentinel = await File(p.join(root.path, 'sentinel')).writeAsBytes(bytes);
  });
  tearDown(() async {
    expect(await sentinel.readAsBytes(), bytes);
    expect(p.isWithin(Directory.systemTemp.absolute.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('healthmap-inspection-'));
    await root.delete(recursive: true);
  });

  test('positive database IDs accepted; zero and negatives rejected', () {
    for (final id in [1, 42, 2147483647]) {
      service.validateAnimationId(id);
    }
    for (final id in [0, -1]) {
      expect(() => service.validateAnimationId(id), throwsArgumentError);
    }
  });

  for (final path in ['clip.MP4', 'deep/topic/clip.mp4', r'deep\clip.mp4']) {
    test('valid archive preserves safe relative path: $path', () async {
      final file = await zip([directory('deep/'), video(path)]);
      final before = await file.readAsBytes();
      expect(
          await service.inspectArchive(file.path), path.replaceAll('\\', '/'));
      expect(await file.readAsBytes(), before);
      expect(await Directory(p.join(root.path, 'modules')).exists(), isFalse);
    });
  }

  final invalid = <String, List<ArchiveFile> Function()>{
    'empty archive': () => [],
    'empty MP4': () => [video('clip.mp4', [])],
    'extra file': () => [video('clip.mp4'), video('readme.txt')],
    'two MP4s': () => [video('one.mp4'), video('two.mp4')],
    'directory only': () => [directory('folder/')],
    'traversal': () => [video('../clip.mp4')],
    'absolute': () => [video('/clip.mp4')],
    'drive path': () => [video('C:/clip.mp4')],
    'dot component': () => [video('a/./clip.mp4')],
    'empty component': () => [video('a//clip.mp4')],
    'normalized duplicate': () => [video('a/clip.mp4'), video(r'a\clip.mp4')],
    'file before child directory': () =>
        [video('clip.mp4'), directory('clip.mp4/child/')],
    'directory before conflicting file': () =>
        [directory('clip.mp4/child/'), video('clip.mp4')],
    'archive symlink': () => [
          video('clip.mp4', 'outside'.codeUnits)
            ..symbolicLink = 'outside'
            ..mode = 0xa1ff
        ],
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} without extracting', () async {
      final file = await zip(entry.value());
      if (entry.key == 'archive symlink') {
        expect(
            ZipDecoder()
                .decodeBytes(await file.readAsBytes())
                .single
                .isSymbolicLink,
            isTrue,
            reason: 'Fixture must actually encode a symlink');
      }
      final before = await file.readAsBytes();
      await expectLater(
          service.inspectArchive(file.path), throwsA(isA<FormatException>()));
      expect(await file.readAsBytes(), before);
      expect(await Directory(p.join(root.path, 'modules')).exists(), isFalse);
    });
  }

  test('invalid ZIP fails and closes input', () async {
    final file = await File(p.join(root.path, 'bad.zip')).writeAsBytes(bytes);
    await expectLater(service.inspectArchive(file.path), throwsA(anything));
    // Windows deletion also verifies that inspection released the input handle.
    await file.delete();
  });

  test('absent destination ignores unrelated historical MP4', () async {
    await File(p.join(root.path, 'historical.mp4')).writeAsBytes(bytes);
    expect((await inspect()).status, AnimationInstallationStatus.notInstalled);
    expect(await Directory(getDestination()).exists(), isFalse);
  });

  test('nested installation returns its own path without modifying bytes',
      () async {
    final file = await installedFile('deep/clip.mp4', bytes);
    final result = await inspect();
    expect(result.status, AnimationInstallationStatus.installed);
    expect(result.mp4RelativePath, 'deep/clip.mp4');
    expect(await file.readAsBytes(), bytes);
  });

  test('root-level installation accepted', () async {
    await installedFile('clip.MP4', bytes);
    expect((await inspect()).status, AnimationInstallationStatus.installed);
  });

  test('empty installation directory is conflict', () async {
    await Directory(getDestination()).create(recursive: true);
    expect((await inspect()).status, AnimationInstallationStatus.conflict);
  });

  for (final layout in <String, Map<String, List<int>>>{
    'empty video': {'clip.mp4': []},
    'extra file': {'clip.mp4': bytes, 'index.html': bytes},
    'two videos': {'one.mp4': bytes, 'two.mp4': bytes},
    'nonvideo': {'module.json': bytes},
  }.entries) {
    test('malformed installation: ${layout.key}', () async {
      for (final entry in layout.value.entries) {
        await installedFile(entry.key, entry.value);
      }
      expect((await inspect()).status, AnimationInstallationStatus.conflict);
      for (final entry in layout.value.entries) {
        expect(await File(p.join(getDestination(), entry.key)).readAsBytes(),
            entry.value);
      }
    });
  }

  test('file in place of animations ancestor is conflict', () async {
    final modules = await Directory(p.join(root.path, 'modules')).create();
    await File(p.join(modules.path, 'animations')).writeAsBytes(bytes);
    expect((await inspect()).status, AnimationInstallationStatus.conflict);
  });

  test('installation rejects links where supported', () async {
    final target =
        await File(p.join(root.path, 'outside.mp4')).writeAsBytes(bytes);
    await Directory(getDestination()).create(recursive: true);
    final link = Link(p.join(getDestination(), 'clip.mp4'));
    try {
      await link.create(target.path);
    } on FileSystemException catch (error) {
      markTestSkipped('Symlink creation unavailable: $error');
      return;
    }
    expect((await inspect()).status, AnimationInstallationStatus.conflict);
    expect(await target.readAsBytes(), bytes);
  });
}
