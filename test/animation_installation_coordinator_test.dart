import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/services/animation_installation_coordinator.dart';

class _Cancelled implements Exception {}

void main() {
  late AnimationInstallationCoordinator coordinator;
  setUp(() => coordinator = AnimationInstallationCoordinator());

  test('runs operation and returns typed result', () async {
    var calls = 0;
    final result = await coordinator.run(
      animationId: 42,
      operation: () async {
        calls++;
        return 'installed';
      },
    );
    expect(result, 'installed');
    expect(calls, 1);
  });

  test(
      'rejects duplicate before invoking its operation and retains reservation',
      () async {
    final completion = Completer<String>();
    final first =
        coordinator.run(animationId: 42, operation: () => completion.future);
    var duplicateCalled = false;
    Future<void> duplicate() => coordinator.run(
          animationId: 42,
          operation: () async {
            duplicateCalled = true;
          },
        );
    await expectLater(
        duplicate(),
        throwsA(isA<AnimationInstallationInProgressException>()
            .having((error) => error.animationId, 'animationId', 42)));
    // Rejecting one duplicate must not release the original reservation.
    await expectLater(
        duplicate(), throwsA(isA<AnimationInstallationInProgressException>()));
    expect(duplicateCalled, isFalse);
    completion.complete('first');
    expect(await first, 'first');
  });

  test('different IDs proceed independently and finish in reverse order',
      () async {
    final firstGate = Completer<int>();
    final secondGate = Completer<int>();
    final first =
        coordinator.run(animationId: 1, operation: () => firstGate.future);
    final second =
        coordinator.run(animationId: 2, operation: () => secondGate.future);
    secondGate.complete(2);
    expect(await second, 2);
    expect(await coordinator.run(animationId: 2, operation: () async => 3), 3);
    await expectLater(coordinator.run(animationId: 1, operation: () async => 0),
        throwsA(isA<AnimationInstallationInProgressException>()));
    firstGate.complete(1);
    expect(await first, 1);
  });

  test('success releases reservation for a later attempt', () async {
    for (var attempt = 0; attempt < 3; attempt++) {
      expect(
          await coordinator.run(
              animationId: 42, operation: () async => attempt),
          attempt);
    }
  });

  test('asynchronous failure propagates and allows retry', () async {
    final gate = Completer<void>();
    final error = StateError('installation failed');
    final first =
        coordinator.run(animationId: 42, operation: () => gate.future);
    final assertion = expectLater(first, throwsA(same(error)));
    gate.completeError(error);
    await assertion;
    expect(
        await coordinator.run(animationId: 42, operation: () async => 'retry'),
        'retry');
  });

  test('synchronous operation exception releases reservation', () async {
    final error = StateError('before first await');
    await expectLater(
        coordinator.run<void>(animationId: 42, operation: () => throw error),
        throwsA(same(error)));
    await coordinator.run<void>(animationId: 42, operation: () async {});
  });

  test('failed operation result also releases reservation', () async {
    expect(await coordinator.run(animationId: 42, operation: () async => false),
        isFalse);
    expect(await coordinator.run(animationId: 42, operation: () async => true),
        isTrue);
  });

  test('cancellation error releases reservation', () async {
    final gate = Completer<void>();
    final cancelled = _Cancelled();
    final pending =
        coordinator.run(animationId: 42, operation: () => gate.future);
    final assertion = expectLater(pending, throwsA(same(cancelled)));
    gate.completeError(cancelled);
    await assertion;
    await coordinator.run<void>(animationId: 42, operation: () async {});
  });

  test('cancellation represented by completion releases reservation', () async {
    final gate = Completer<void>();
    final pending =
        coordinator.run(animationId: 42, operation: () => gate.future);
    gate.complete();
    await pending;
    await coordinator.run<void>(animationId: 42, operation: () async {});
  });

  test('invalid IDs never invoke supplied operations', () async {
    for (final id in [0, -1, -42]) {
      await expectLater(
          coordinator.run<void>(
              animationId: id,
              operation: () async => fail('Invalid ID invoked operation')),
          throwsArgumentError);
    }
  });

  test('reservation spans multiple awaits', () async {
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final reachedSecond = Completer<void>();
    final pending = coordinator.run(
        animationId: 42,
        operation: () async {
          await firstGate.future;
          reachedSecond.complete();
          await secondGate.future;
        });
    firstGate.complete();
    await reachedSecond.future;
    await expectLater(
        coordinator.run<void>(animationId: 42, operation: () async {}),
        throwsA(isA<AnimationInstallationInProgressException>()));
    secondGate.complete();
    await pending;
  });

  test('many simultaneous same-ID callers run exactly one operation', () async {
    final gate = Completer<int>();
    var invocations = 0;
    final attempts = List.generate(
        20,
        (_) => coordinator.run(
            animationId: 42,
            operation: () {
              invocations++;
              return gate.future;
            }));
    final rejected = attempts
        .skip(1)
        .map((future) => expectLater(
            future, throwsA(isA<AnimationInstallationInProgressException>())))
        .toList();
    await Future.wait(rejected);
    expect(invocations, 1);
    gate.complete(7);
    expect(await attempts.first, 7);
  });

  test('independent coordinator instances do not share reservations', () async {
    final gate = Completer<void>();
    final first =
        coordinator.run(animationId: 42, operation: () => gate.future);
    expect(
        await AnimationInstallationCoordinator()
            .run(animationId: 42, operation: () async => 'independent'),
        'independent');
    gate.complete();
    await first;
  });

  test('coordination performs no filesystem access', () async {
    await IOOverrides.runZoned(() async {
      await coordinator.run<void>(animationId: 42, operation: () async {});
      await expectLater(
          coordinator.run<void>(
              animationId: 42,
              operation: () => throw StateError('operation failed')),
          throwsStateError);
      await coordinator.run<void>(animationId: 42, operation: () async {});
    },
        createFile: (_) =>
            throw StateError('Unexpected filesystem file access'),
        createDirectory: (_) =>
            throw StateError('Unexpected filesystem directory access'),
        createLink: (_) =>
            throw StateError('Unexpected filesystem link access'));
  });
}
