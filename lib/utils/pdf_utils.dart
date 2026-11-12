import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<File> generateAndSavePdfToFile(
    Uint8List pdfBytes, String filename) async {
  final root = await getTemporaryDirectory();
  final dir = await root.createTemp('cme_history_');
  try {
    final file = File('${dir.path}/$filename');
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
  }
}
