import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AnimationDirectoryProvider = Future<Directory?> Function();

/// Storage policy for standalone animations only. Returned roots exclude
/// `modules/`; resolving a root never creates that directory.
class AnimationStorageService {
  AnimationStorageService({
    String? operatingSystem,
    AnimationDirectoryProvider? externalDirectory,
    AnimationDirectoryProvider? documentsDirectory,
    AnimationDirectoryProvider? supportDirectory,
  })  : _operatingSystem = operatingSystem ?? Platform.operatingSystem,
        _externalDirectory = externalDirectory ?? getExternalStorageDirectory,
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final String _operatingSystem;
  final AnimationDirectoryProvider _externalDirectory;
  final AnimationDirectoryProvider _documentsDirectory;
  final AnimationDirectoryProvider _supportDirectory;

  void _checkPlatform() {
    if (_operatingSystem != 'android' && _operatingSystem != 'ios') {
      throw UnsupportedError('Animation storage: $_operatingSystem');
    }
  }

  Future<Directory?> _available(AnimationDirectoryProvider provider) async {
    try {
      return await provider();
    } on Exception {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  /// Destination base for future installations; does not create `modules/`.
  Future<Directory> getCanonicalRoot() async {
    _checkPlatform();
    if (_operatingSystem == 'android') {
      final external = await _available(_externalDirectory);
      if (external != null) return _normalized(external);
      final documents = await _documentsDirectory();
      if (documents != null) return _normalized(documents);
    } else {
      final support = await _supportDirectory();
      if (support != null) return _normalized(support);
    }
    throw FileSystemException('Canonical animation storage is unavailable.');
  }

  Directory _normalized(Directory root) =>
      Directory(p.normalize(p.absolute(root.path)));
}
