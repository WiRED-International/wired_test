/// A second operation already owns this animation's reservation.
class AnimationInstallationInProgressException implements Exception {
  const AnimationInstallationInProgressException(this.animationId);

  final int animationId;

  @override
  String toString() =>
      'Animation installation already in progress for ID $animationId.';
}

/// Coordinates entire asynchronous installation operations in memory only.
///
/// All cooperating callers must share this instance. Construct/hold it in the
/// owning application isolate and keep the operation pending until any worker
/// finishes. Independent instances, isolates and processes are NOT coordinated.
/// No filesystem lock, installation, cancellation signal or timeout is created.
class AnimationInstallationCoordinator {
  final Set<int> _activeIds = {};

  /// Reserves a positive backend Modules.id before invoking [operation].
  ///
  /// The reservation is released only when the operation completes or throws,
  /// including cooperative cancellation represented by either outcome. Merely
  /// abandoning this Future or timing out a caller does not cancel the work or
  /// release the reservation. The operation must cover all installation work.
  Future<T> run<T>({
    required int animationId,
    required Future<T> Function() operation,
  }) async {
    if (animationId <= 0) throw ArgumentError.value(animationId, 'animationId');
    if (!_activeIds.add(animationId)) {
      throw AnimationInstallationInProgressException(animationId);
    }
    try {
      return await operation();
    } finally {
      _activeIds.remove(animationId);
    }
  }
}
