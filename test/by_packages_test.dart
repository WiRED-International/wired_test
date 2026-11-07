import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/pages/byPackage/by_packages.dart';
import 'package:wired_test/pages/specialization_selection_page.dart';

void main() {
  for (final specializationStatus in [200, 503]) {
    testWidgets(
        'programs load independently of specialization status $specializationStatus',
        (tester) async {
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      addTearDown(dotenv.clean);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final requests = <Uri>[];
      final programsUri =
          Uri.parse('https://example.invalid/learning-catalog/programs');
      final specializationsUri =
          Uri.parse('https://example.invalid/learning-catalog/specializations');
      final client = MockClient((request) async {
        requests.add(request.url);
        expect(request.method, 'GET');
        if (request.url == programsUri) {
          return http.Response(
              jsonEncode([
                for (final type in ['specialization', 'act', 'other', 'basic'])
                  {
                    'id': ['basic', 'act', 'specialization', 'other']
                            .indexOf(type) +
                        1,
                    'name': type,
                    'training_type': type,
                    'description': '$type description',
                  },
              ]),
              200);
        }
        if (request.url == specializationsUri) {
          return http.Response(
              jsonEncode([
                {'id': 1, 'name': 'Mental Health'},
              ]),
              specializationStatus);
        }
        throw StateError('Unexpected request: ${request.url}');
      });
      addTearDown(client.close);

      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: ByPackages()));
        await tester.pumpAndSettle();

        expect(requests, [programsUri]);
        expect(find.text('Unable to load training programs'), findsNothing);
        expect(find.text('basic description'), findsOneWidget);
        expect(find.text('act description'), findsOneWidget);
        expect(find.text('specialization description'), findsOneWidget);
        expect(find.text('other description'), findsNothing);
        final basic = find.text('Basic CHW Training');
        final advanced = find.text('Advanced CHW Training (ACT)');
        final specialization = find.text('Specialization Programs');
        expect(tester.getTopLeft(basic).dy,
            lessThan(tester.getTopLeft(advanced).dy));
        expect(tester.getTopLeft(advanced).dy,
            lessThan(tester.getTopLeft(specialization).dy));

        // Only the destination page should request specialization data.
        await tester.ensureVisible(specialization);
        await tester.tap(specialization);
        await tester.pumpAndSettle();
        expect(find.byType(SpecializationSelectionPage), findsOneWidget);
        expect(requests, [programsUri, specializationsUri]);
        if (specializationStatus == 200) {
          expect(find.text('Mental Health'), findsOneWidget);
        } else {
          expect(
              find.text('Unable to load specializations. '
                  'Please check your connection.'),
              findsOneWidget);
        }

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(ByPackages), findsOneWidget);
        expect(find.text('Basic CHW Training'), findsOneWidget);
        expect(requests, [programsUri, specializationsUri]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    });
  }
}
