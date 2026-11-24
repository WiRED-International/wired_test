import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wired_test/pages/cme/forgot_password.dart';
import 'package:wired_test/pages/cme/login.dart';
import 'package:wired_test/pages/cme/register.dart';

void main() {
  for (final flow in ['register', 'login', 'forgot-password']) {
    testWidgets(
        '$flow trims email for validation and submission, retains legacy password handling',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
      addTearDown(dotenv.clean);
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
              request.url.path == '/countries'
                  ? '[{"id":1,"name":"Test Country"}]'
                  : '[{"id":1,"name":"Independent","countries":[{"id":1}]}]',
              200);
        }
        requests.add(request);
        // Avoid successful-login side effects; exercise the real request path.
        return http.Response('{}', 400);
      });
      addTearDown(client.close);
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(0.5)),
                child: child!),
            home: switch (flow) {
              'register' => Register(),
              'login' => Login(),
              _ => const ForgotPassword(),
            }));
        await tester.pumpAndSettle();
        TextFormField field(String label) =>
            tester.widget<TextFormField>(find.ancestor(
                of: find.byWidgetPredicate((widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == label),
                matching: find.byType(TextFormField)));
        final emailField = field('Email');
        for (final email in ['person@example.com', 'person123@example2.com']) {
          for (final input in [email, '  $email', '$email  ', '\t$email \n']) {
            expect(emailField.validator!(input), isNull, reason: input);
          }
        }
        for (final input in [
          '',
          ' \t\n',
          'person 123@example.com',
          'person123@exam ple.com',
          'person\t123@example.com',
          'person123@example.com\nother'
        ]) {
          expect(emailField.validator!(input), isNotNull, reason: input);
        }
        if (flow == 'register') {
          for (final input in ['person123', 'person@', 'person@example']) {
            expect(emailField.validator!(input), isNotNull);
          }
          field('First Name').controller!.text = 'Test';
          field('Last Name').controller!.text = 'User';
          // Select the actual loaded country through the field's dropdown.
          final button = tester
              .widgetList<DropdownButton<Map<String, dynamic>>>(
                  find.byType(DropdownButton<Map<String, dynamic>>))
              .first;
          button.onChanged!(button.items!.first.value);
          await tester.pump();
          final organization = tester
              .widgetList<DropdownButton<Map<String, dynamic>>>(
                  find.byType(DropdownButton<Map<String, dynamic>>))
              .last;
          organization.onChanged!(organization.items!.first.value);
          await tester.pump();
        }
        const password = '  secret 123  ';
        if (flow != 'forgot-password') {
          field('Password').controller!.text = password;
          if (flow == 'register') {
            field('Confirm Password').controller!.text = password;
          }
        }
        Future<void> submit() async {
          if (flow == 'forgot-password') {
            tester
                .widget<ElevatedButton>(find.byType(ElevatedButton))
                .onPressed!();
          } else {
            final semantics = find.byWidgetPredicate((widget) =>
                widget is Semantics &&
                widget.properties.label ==
                    (flow == 'login' ? 'Login Button' : 'Register Button'));
            tester
                .widget<GestureDetector>(find
                    .descendant(
                        of: semantics, matching: find.byType(GestureDetector))
                    .first)
                .onTap!();
          }
          await tester.pumpAndSettle();
        }

        for (final input in [
          '  person@example.com ',
          '\tperson123@example2.com \n'
        ]) {
          emailField.controller!.text = input;
          await submit();
          expect(requests.last.url.path, '/auth/$flow');
          final body = jsonDecode(requests.last.body) as Map;
          expect(body['email'], input.trim());
          // Keep the pre-existing password submission behavior, including internal spaces.
          if (flow != 'forgot-password') {
            expect(body['password'], password.trim());
            expect(field('Password').controller!.text, password);
          }
          if (find.text('OK').evaluate().isNotEmpty) {
            await tester.tap(find.text('OK'));
          }
          await tester.pumpAndSettle();
        }
        expect(requests, hasLength(2));
        emailField.controller!.text = 'person 123@example.com';
        await submit();
        expect(requests, hasLength(2));
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    });
  }
}
