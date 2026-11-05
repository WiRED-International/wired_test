import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:wired_test/services/animation_installation_coordinator.dart';
import 'package:wired_test/services/animation_installation_inspection_service.dart';
import 'package:wired_test/pages/module_library.dart';

// Exercise the real Library UI without playback, network, or installed content.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late File sentinel;
  late AnimationInstallationCoordinator coordinator;
  final playback = <MethodCall>[];
  const playbackChannel = MethodChannel('open_file');
  const sentinelContents = 'unrelated content must survive';

  Future<File> writeFixture(String relativePath, String contents) async {
    final target = p.normalize(p.join(root.path, relativePath));
    expect(p.isWithin(root.path, target), isTrue);
    final file = File(target);
    await file.parent.create(recursive: true);
    return file.writeAsString(contents, flush: true);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('healthmap-library-mp4-');
    coordinator = AnimationInstallationCoordinator();
    playback.clear();
    messenger.setMockMethodCallHandler(playbackChannel, (call) async {
      playback.add(call);
      return '{"type":0,"message":"done"}';
    });
    sentinel = await writeFixture('modules/unrelated.keep', sentinelContents);
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getExternalStorageDirectory':
          return root.path;
        default:
          throw TestFailure('Unexpected path_provider request: ${call.method}');
      }
    });
    // Fail before mounting Library if platform registration bypasses the mock.
    expect((await getApplicationDocumentsDirectory()).path, root.path);
    expect((await getApplicationSupportDirectory()).path, root.path);
    if (Platform.isAndroid) {
      expect((await getExternalStorageDirectory())?.path, root.path);
    }
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(playbackChannel, null);
    try {
      expect(await sentinel.readAsString(), sentinelContents);
    } finally {
      final tempRoot = p.normalize(Directory.systemTemp.absolute.path);
      final target = p.normalize(root.absolute.path);
      // Never recursively delete a shared temp directory or an application path.
      expect(p.isWithin(tempRoot, target), isTrue);
      expect(p.basename(target), startsWith('healthmap-library-mp4-'));
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  Future<void> settleLibrary(WidgetTester tester) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      // Real filesystem futures must run outside the widget test's fake clock.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull,
          reason: 'Library harness exception');
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(find.textContaining('Unable to load downloaded modules:'),
            findsNothing,
            reason: 'Fixture discovery failed, rather than a safety assertion');
        return;
      }
    }
    fail('Library fixture scan did not finish');
  }

  Future<void> mountLibrary(WidgetTester tester,
      {Future<void> Function()? beforeDirectoryCleanup}) async {
    // Landscape avoids an unrelated bottom-navigation overflow with the test
    // font. Keep framework exceptions enabled; do not suppress layout errors.
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(Provider<AnimationInstallationCoordinator>.value(
        value: coordinator,
        child: MaterialApp(
            home: ModuleLibrary(
          beforeAnimationDirectoryCleanup: beforeDirectoryCleanup,
        ))));
    await settleLibrary(tester);
  }

  Future<void> requestDelete(WidgetTester tester) async {
    final remove = find.byTooltip('Remove download');
    expect(remove, findsOneWidget);
    await tester.ensureVisible(remove);
    await tester.runAsync(() => tester.tap(remove));
    await tester.pumpAndSettle();
    expect(find.text('Remove downloaded animation?'), findsOneWidget);
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    // Ownership checks now perform filesystem reads before deletion/refusal.
    // Wait for the operation's UI result, not just an idle widget frame.
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(SnackBar).evaluate().isNotEmpty) break;
    }
    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'Deletion or safety refusal must finish before assertions');
    await settleLibrary(tester);
  }

  for (final entry in <String, String>{
    'top-level': 'modules/standalone_clip.mp4',
    'deeply nested': 'modules/animations/topic/group/standalone_clip.mp4',
    'published': 'modules/animations/42/topic/group/standalone_clip.mp4',
    'published backup name':
        'modules/animations/42/topic.backup/group/standalone_clip.mp4',
  }.entries) {
    testWidgets('${entry.key} standalone MP4 is discovered and safely deleted',
        (tester) async {
      final video = await tester
          .runAsync(() => writeFixture(entry.value, 'nonempty MP4 fixture'));
      await mountLibrary(tester);
      expect(find.text('standalone clip'), findsOneWidget);
      expect(find.text('Open animation'), findsOneWidget);
      expect(find.text('1 downloaded'), findsOneWidget);
      await tester.tap(find.text('Open animation'));
      for (var i = 0; i < 100 && playback.isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(playback.single.method, 'open_file');
      expect(p.normalize(playback.single.arguments['file_path'] as String),
          video!.path);
      expect(playback.single.arguments['type'], 'video/mp4');

      // Cancellation must not delete either the video or unrelated content.
      await requestDelete(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect(await video.readAsString(), 'nonempty MP4 fixture');
        expect(await sentinel.readAsString(), sentinelContents);
      });

      await requestDelete(tester);
      await confirmDelete(tester);
      expect(find.text('Removed "standalone clip" from this device.'),
          findsOneWidget);
      await tester.runAsync(() async {
        expect(await video.exists(), isFalse);
        expect(await sentinel.readAsString(), sentinelContents);
        if (entry.key.startsWith('published')) {
          expect(
              await Directory(p.join(root.path, 'modules/animations/42'))
                  .exists(),
              isFalse);
          expect(
              (await AnimationInstallationInspectionService()
                      .inspectInstallation(root: root, animationId: 42))
                  .status,
              AnimationInstallationStatus.notInstalled);
        } else {
          expect(await video.parent.exists(), isTrue);
        }
      });
      expect(find.text('standalone clip'), findsNothing);
      expect(find.text('0 downloaded'), findsOneWidget);
    });
  }

  for (final entry in <String, String>{
    'compiler': 'index.html',
    'Storyline': 'story.html',
  }.entries) {
    testWidgets('${entry.key} module does not expose its embedded MP4',
        (tester) async {
      await tester.runAsync(() async {
        await writeFixture('modules/instruction/${entry.value}',
            '<html>Instructional module</html>');
        await writeFixture(
            'modules/instruction/assets/lesson.mp4', 'owned video');
      });
      await mountLibrary(tester);
      expect(find.text('instruction'), findsOneWidget);
      expect(find.text('Open module'), findsOneWidget);
      expect(find.text('Open animation'), findsNothing,
          reason:
              'Module-owned MP4 must not have an independent delete action');
      expect(find.text('lesson'), findsNothing);
      expect(find.text('1 downloaded'), findsOneWidget);
      await tester.runAsync(() async {
        expect(
            await File(
                    p.join(root.path, 'modules/instruction/assets/lesson.mp4'))
                .readAsString(),
            'owned video');
      });
    });
  }

  testWidgets('recovery backup and its MP4 are not normal Library entries',
      (tester) async {
    await tester.runAsync(() async {
      await writeFixture(
          'modules/1565.backup/index.html', '<html>Backup</html>');
      await writeFixture('modules/1565.backup/module.json',
          '{"module_id":"1565","module_title":"Recovery copy"}');
      await writeFixture(
          'modules/1565.backup/assets/backup_lesson.mp4', 'recovery video');
    });
    await mountLibrary(tester);
    expect(find.text('Recovery copy'), findsNothing);
    expect(find.text('backup lesson'), findsNothing);
    expect(find.text('Open module'), findsNothing);
    expect(find.text('Open animation'), findsNothing);
    expect(find.byTooltip('Remove download'), findsNothing);
    expect(find.text('0 downloaded'), findsOneWidget);
  });

  testWidgets('deletion rechecks ownership after confirmation dialog opens',
      (tester) async {
    final video = await tester.runAsync(() => writeFixture(
        'modules/changing/assets/lesson.mp4', 'newly module-owned video'));
    await mountLibrary(tester);
    expect(find.text('Open animation'), findsOneWidget);
    await requestDelete(tester);
    // Keep the original entry/dialog alive; do not refresh the Library here.
    final index = await tester.runAsync(() => writeFixture(
        'modules/changing/index.html', '<html>New module owner</html>'));
    await confirmDelete(tester);
    await tester.runAsync(() async {
      expect(await video!.exists(), isTrue,
          reason: 'A stale animation entry must not delete module-owned media');
      expect(await video.readAsString(), 'newly module-owned video');
      expect(await index!.readAsString(), '<html>New module owner</html>');
      expect(await sentinel.readAsString(), sentinelContents);
    });
  });

  testWidgets(
      'current Storyline launcher remains discoverable without MP4 copy',
      (tester) async {
    await tester.runAsync(() async {
      await writeFixture('modules/1001.htm', '''<html><head>
<meta name="module-title" content="Standalone Storyline">
<meta http-equiv="refresh" content="0; url=../files/1001/story.html">
</head></html>''');
      await writeFixture('files/1001/story.html', '<html>Storyline</html>');
      await writeFixture(
          'files/1001/story_content/lesson.mp4', 'Storyline-owned video');
    });
    await mountLibrary(tester);
    expect(find.text('Standalone Storyline'), findsOneWidget);
    expect(find.text('Open module'), findsOneWidget);
    expect(find.text('Open animation'), findsNothing);
    expect(find.text('1 downloaded'), findsOneWidget);
    expect(find.byTooltip('Remove download'), findsOneWidget);
    await tester.runAsync(() async {
      expect(
          await File(p.join(root.path, 'files/1001/story_content/lesson.mp4'))
              .readAsString(),
          'Storyline-owned video');
      expect(await sentinel.readAsString(), sentinelContents);
    });
  });
  testWidgets('active animation installation prevents Library removal',
      (tester) async {
    final video = await tester.runAsync(
        () => writeFixture('modules/animations/42/topic/active.mp4', 'keep'));
    await mountLibrary(tester);
    await requestDelete(tester);
    final release = Completer<void>();
    final owner =
        coordinator.run(animationId: 42, operation: () => release.future);
    try {
      await confirmDelete(tester);
      expect(
          find.text(
              'This animation is being installed. Try removing it after installation finishes.'),
          findsOneWidget);
      await tester.runAsync(() async {
        expect(await video!.readAsString(), 'keep');
      });
    } finally {
      release.complete();
      await owner;
    }
  });

  testWidgets(
      'backup exemption never includes recovery or nonnumeric legacy trees',
      (tester) async {
    await tester.runAsync(() async {
      await writeFixture('modules/animations/42.backup/hidden.mp4', 'recovery');
      await writeFixture(
          'modules/animations/topic.backup/hidden.mp4', 'legacy recovery');
      await writeFixture('packages/old.backup/hidden.mp4', 'package recovery');
      await writeFixture('modules/animations/43/index.html', 'module');
      await writeFixture(
          'modules/animations/43/nested.backup/hidden.mp4', 'module video');
    });
    await mountLibrary(tester);
    expect(find.text('Open animation'), findsNothing);
    expect(find.byTooltip('Remove download'), findsNothing);
    expect(find.text('0 downloaded'), findsOneWidget);
    await tester.runAsync(() async {
      expect(
          await File(
                  p.join(root.path, 'modules/animations/42.backup/hidden.mp4'))
              .readAsString(),
          'recovery');
      expect(
          await File(p.join(root.path, 'modules/animations/43/index.html'))
              .readAsString(),
          'module');
    });
  });

  testWidgets(
      'new numeric animation refuses a module owner added after confirmation',
      (tester) async {
    final video = await tester.runAsync(
        () => writeFixture('modules/animations/42/nested/clip.mp4', 'keep'));
    await mountLibrary(tester);
    await requestDelete(tester);
    await tester.runAsync(
        () => writeFixture('modules/animations/42/story.html', 'module'));
    await confirmDelete(tester);
    await tester.runAsync(() async {
      expect(await video!.readAsString(), 'keep');
      expect(
          await File(p.join(root.path, 'modules/animations/42/story.html'))
              .readAsString(),
          'module');
    });
  });
  testWidgets(
      'partial removal refreshes Library and warns after cleanup failure',
      (tester) async {
    final video = await tester.runAsync(
        () => writeFixture('modules/animations/42/nested/clip.mp4', 'video'));
    final original = FileSystemException('injected directory cleanup failure');
    final originalStack = StackTrace.current;
    await mountLibrary(tester, beforeDirectoryCleanup: () async {
      Error.throwWithStackTrace(original, originalStack);
    });
    expect(find.text('clip'), findsOneWidget);
    await requestDelete(tester);
    await confirmDelete(tester);
    expect(
        find.text(
            'Video removed, but directory cleanup was incomplete. Re-download may be blocked.'),
        findsOneWidget);
    expect(find.text('Unable to remove this module.'), findsNothing);
    expect(find.text('clip'), findsNothing);
    expect(find.text('Open animation'), findsNothing);
    expect(find.text('0 downloaded'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await video!.exists(), isFalse);
      expect(await video.parent.exists(), isTrue);
      expect(
          (await AnimationInstallationInspectionService()
                  .inspectInstallation(root: root, animationId: 42))
              .status,
          AnimationInstallationStatus.conflict);
      await coordinator.run(animationId: 42, operation: () async {});
    });
  });

  testWidgets('retained unrelated files produce a re-download warning',
      (tester) async {
    final video = await tester.runAsync(() async {
      final clip =
          await writeFixture('modules/animations/42/nested/clip.mp4', 'video');
      await writeFixture(
          'modules/animations/42/nested/unrelated.keep', 'preserve');
      return clip;
    });
    await mountLibrary(tester);
    await requestDelete(tester);
    await confirmDelete(tester);
    expect(
        find.text(
            'Animation removed, but other files remain in its folder. Re-download is blocked until they are reviewed.'),
        findsOneWidget);
    await tester.runAsync(() async {
      expect(await video!.exists(), isFalse);
      expect(
          await File(p.join(
                  root.path, 'modules/animations/42/nested/unrelated.keep'))
              .readAsString(),
          'preserve');
    });
  });

  for (final play in [false, true]) {
    testWidgets('stale linked MP4 cannot be ${play ? 'played' : 'removed'}',
        (tester) async {
      final video = await tester.runAsync(
          () => writeFixture('modules/animations/42/nested/clip.mp4', 'video'));
      await mountLibrary(tester);
      if (!play) await requestDelete(tester);
      final saved = File(p.join(root.path, 'external/clip.mp4'));
      final link = Link(video!.path);
      var linked = false;
      await tester.runAsync(() async {
        await saved.parent.create(recursive: true);
        await video.rename(saved.path);
        try {
          await link.create(saved.path);
          linked = true;
        } on FileSystemException catch (error) {
          markTestSkipped('Symlinks unavailable: $error');
        }
      });
      try {
        if (!linked) return;
        if (play) {
          await tester.runAsync(() => tester.tap(find.text('Open animation')));
          for (var i = 0; i < 100; i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)));
            await tester.pump();
            if (find.byType(SnackBar).evaluate().isNotEmpty) break;
          }
          expect(
              find.text(
                  'This animation is no longer available separately. Refresh your library.'),
              findsOneWidget);
          expect(playback, isEmpty);
        } else {
          await confirmDelete(tester);
        }
        await tester.runAsync(() async {
          expect(await saved.readAsString(), 'video');
          expect(await FileSystemEntity.type(link.path, followLinks: false),
              FileSystemEntityType.link);
        });
      } finally {
        await tester.runAsync(() async {
          if (linked) await link.delete();
          await saved.rename(video.path);
        });
      }
    });
  }
}
