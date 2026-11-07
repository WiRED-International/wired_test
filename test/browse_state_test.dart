import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/widgets/browse/browse_state.dart';

void main() {
  testWidgets('loading inherits theme color or uses explicit color',
      (tester) async {
    for (final color in <Color?>[null, const Color(0xFF0070C0)]) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          progressIndicatorTheme:
              const ProgressIndicatorThemeData(color: Colors.purple),
        ),
        home: BrowseState.loading(indicatorColor: color),
      ));
      final indicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      expect(indicator.color, color);
      expect(indicator.value, isNull);
      expect(
          find.ancestor(
              of: find.byType(CircularProgressIndicator),
              matching: find.byType(Center)),
          findsOneWidget);
      final progress = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      expect(
          progress.color ??
              Theme.of(tester.element(find.byType(BrowseState)))
                  .progressIndicatorTheme
                  .color,
          color ?? Colors.purple);
      expect(find.byType(ElevatedButton), findsNothing);
    }
  });

  testWidgets('message preserves presentation and optional retry',
      (tester) async {
    var retries = 0;
    for (final retry in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BrowseState.message(
            icon: Icons.wifi_off_rounded,
            title: 'Unable to load modules',
            detail: 'Check your connection and try again.',
            onRetry: retry ? () => retries++ : null,
          ),
        ),
      ));
      final icon = tester.widget<Icon>(find.byIcon(Icons.wifi_off_rounded));
      expect(icon.size, 48);
      expect(icon.color, const Color(0xFF358347));
      final title = tester.widget<Text>(find.text('Unable to load modules'));
      expect(title.textAlign, TextAlign.center);
      expect(title.style!.fontSize, 19);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(title.style!.color, const Color(0xFF16466A));
      final detail = tester
          .widget<Text>(find.text('Check your connection and try again.'));
      expect(detail.textAlign, TextAlign.center);
      expect(detail.style!.color, const Color(0xFF607889));
      final padding = tester.widget<Padding>(find
          .descendant(
              of: find.byType(BrowseState), matching: find.byType(Padding))
          .first);
      expect(padding.padding, const EdgeInsets.all(24));
      final column = tester.widget<Column>(find.descendant(
          of: find.byType(BrowseState), matching: find.byType(Column)));
      expect(column.mainAxisSize, MainAxisSize.min);
      expect(column.children.whereType<SizedBox>().map((box) => box.height),
          retry ? [14.0, 8.0, 18.0] : [14.0, 8.0]);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try Again'), retry ? findsOneWidget : findsNothing);
      if (retry) {
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        await tester.tap(find.text('Try Again'));
        expect(retries, 1);
      }
    }
  });
}
