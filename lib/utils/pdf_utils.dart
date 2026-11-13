import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Process-local pins only; no persisted registry or background work.
final _activeCmePdfs = <String, int>{};
String _pdfKey(File file) => p.normalize(p.absolute(file.path));

void retainCmePdf(File file) {
  final key = _pdfKey(file);
  _activeCmePdfs[key] = (_activeCmePdfs[key] ?? 0) + 1;
}

void releaseCmePdf(File file) {
  final key = _pdfKey(file);
  final count = _activeCmePdfs[key] ?? 0;
  if (count <= 1) {
    _activeCmePdfs.remove(key);
  } else {
    _activeCmePdfs[key] = count - 1;
  }
}

/// Only known, flat export directories are eligible. Both the directory and
/// its PDF must have been unmodified for seven days.
/// Optional root/clock keep filesystem tests independent of device storage.
Future<void> cleanupOldCmePdfExports({Directory? root, DateTime? now}) async {
  try {
    final directory = root ?? await getTemporaryDirectory();
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! Directory ||
          !RegExp(r'^cme_history_[A-Za-z0-9]+$')
              .hasMatch(p.basename(entry.path))) {
        continue;
      }
      try {
        final file = File(p.join(entry.path, 'cme_history.pdf'));
        final children = await entry.list(followLinks: false).toList();
        // Never recurse into unknown contents, subdirectories, or links.
        if (children.isNotEmpty &&
            (children.length != 1 ||
                children.single is! File ||
                p.basename(children.single.path) != 'cme_history.pdf')) {
          continue;
        }
        if (!(await entry.stat()).modified.isBefore(cutoff)) continue;
        if (children.isNotEmpty &&
            !(await file.stat()).modified.isBefore(cutoff)) {
          continue;
        }
        // No await between the final activity/type checks and deletion: a
        // preview cannot acquire a pin midway through this small operation.
        if (_activeCmePdfs.containsKey(_pdfKey(file)) ||
            FileSystemEntity.typeSync(entry.path, followLinks: false) !=
                FileSystemEntityType.directory) {
          continue;
        }
        if (children.isNotEmpty) {
          if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
              FileSystemEntityType.file) {
            continue;
          }
          file.deleteSync();
        }
        entry.deleteSync(); // Non-recursive; never follows nested links.
      } catch (_) {
        // A busy/missing/unreadable export must not block a new export.
      }
    }
  } catch (_) {
    // Temporary storage or directory enumeration may be unavailable.
  }
}

Future<File> generateAndSavePdfToFile(
    Uint8List pdfBytes, String filename) async {
  final root = await getTemporaryDirectory();
  await cleanupOldCmePdfExports(root: root);
  final dir = await root.createTemp('cme_history_');
  final file = File('${dir.path}/$filename');
  retainCmePdf(file);
  try {
    await file.writeAsBytes(pdfBytes, flush: true);
    return file;
  } catch (_) {
    // This directory belongs exclusively to this failed export.
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // Preserve the original write failure if cleanup also fails.
    }
    rethrow;
  } finally {
    releaseCmePdf(file);
  }
}
