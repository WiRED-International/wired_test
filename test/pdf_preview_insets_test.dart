import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:wired_test/utils/pdf_preview_screen.dart';

class _PendingPdf extends Fake implements File {
  final _bytes = Completer<Uint8List>();

  @override
  String get path => 'insets-preview.pdf';

  @override
  Future<Uint8List> readAsBytes() => _bytes.future;
}

void main() {
  final scenarios = <String, (Size, EdgeInsets)>{
    'no system insets': (const Size(400, 800), EdgeInsets.zero),
    'gesture navigation': (
      const Size(400, 800),
      const EdgeInsets.only(top: 24, bottom: 24),
    ),
    'three-button navigation': (
      const Size(400, 800),
      const EdgeInsets.only(top: 24, bottom: 48),
    ),
    'landscape cutout and side navigation': (
      const Size(800, 400),
      const EdgeInsets.only(left: 44, top: 24, right: 48),
    ),
  };

  for (final scenario in scenarios.entries) {
    testWidgets('PDF preview respects ${scenario.key}', (tester) async {
      final (size, insets) = scenario.value;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: insets,
            viewPadding: insets,
          ),
          child: child!,
        ),
        home: PdfPreviewScreen(pdfFile: _PendingPdf()),
      ));
      // Let the viewer's dependency-change timer finish before disposal.
      await tester.pump(const Duration(milliseconds: 600));

      final scaffold = tester.getRect(find.byType(Scaffold));
      final button = tester.getRect(
        find.byWidgetPredicate((widget) => widget is ElevatedButton),
      );
      final viewer = tester.getRect(find.byType(SfPdfViewer));
      final appBar = tester.getRect(find.byType(AppBar));

      // Preserve the original 12px spacing, adding each system inset once.
      expect(
          scaffold.bottom - button.bottom, closeTo(insets.bottom + 12, 0.01));
      expect(button.left - scaffold.left, closeTo(insets.left + 12, 0.01));
      expect(scaffold.right - button.right, closeTo(insets.right + 12, 0.01));
      expect(viewer.left - scaffold.left, closeTo(insets.left, 0.01));
      expect(scaffold.right - viewer.right, closeTo(insets.right, 0.01));
      expect(viewer.top, closeTo(appBar.bottom, 0.01));
      expect(viewer.bottom, closeTo(button.top - 12, 0.01));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
