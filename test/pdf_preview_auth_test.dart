import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:wired_test/providers/auth_provider.dart';
import 'package:wired_test/utils/pdf_preview_screen.dart';
import 'package:wired_test/utils/email_success_screen.dart';

class _Auth extends AuthProvider {
  String? token = 'A';
  bool expired = false;
  @override
  String? get authToken => token;
  @override
  bool get isLoggedIn => token != null;
  @override
  bool get isLoading => false;
  @override
  bool isTokenExpired() => expired;
  void change(String? value) {
    token = value;
    notifyListeners();
  }
}

class _Pdf extends Fake implements File {
  Completer<Uint8List>? pending;
  bool failRead = false;
  bool present = true;
  int deletions = 0;
  Completer<bool>? existence;
  @override
  Future<File> delete({bool recursive = false}) async {
    deletions++;
    present = false;
    return this;
  }

  bool failCleanup = false;
  @override
  Future<bool> exists() async {
    if (failCleanup) throw FileSystemException("cleanup failed");
    return existence == null ? present : await existence!.future;
  }

  final bytes = Uint8List.fromList([37, 80, 68, 70]);
  @override
  String get path => 'preview.pdf';
  @override
  Future<Uint8List> readAsBytes() async {
    if (failRead) {
      failRead = false;
      throw FileSystemException('read failed');
    }
    return pending == null ? bytes : await pending!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  late _Pdf pdf;
  late List<http.Request> requests;
  late MockClient client;
  Completer<http.Response>? response;
  const printing = MethodChannel('net.nfet.printing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> shares;

  setUp(() {
    auth = _Auth();
    pdf = _Pdf();
    requests = [];
    response = null;
    shares = [];
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
    client = MockClient((request) async {
      requests.add(request);
      // Keep the preview/file mounted; success handling is unchanged.
      return response == null
          ? http.Response('{}', 403)
          : await response!.future;
    });
    messenger.setMockMethodCallHandler(printing, (call) async {
      shares.add(call);
      return 1;
    });
  });
  tearDown(() {
    auth.dispose();
    client.close();
    dotenv.clean();
    messenger.setMockMethodCallHandler(printing, null);
  });

  Future<void> mount(WidgetTester tester, {bool provider = true}) async {
    final app = MaterialApp(home: PdfPreviewScreen(pdfFile: pdf));
    await tester.pumpWidget(provider
        ? ChangeNotifierProvider<AuthProvider>.value(value: auth, child: app)
        : app);
    await tester.pump();
  }

  Future<void> dialog(WidgetTester tester) async {
    await tester.tap(find.text('Email CME History'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(
        find.byType(TextField).at(0), 'recipient@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'Sender');
    await tester.enterText(find.byType(TextField).at(2), 'Message');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
  }

  testWidgets('valid session preserves multipart payload and Bearer token',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await dialog(tester);
      await submit(tester);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(
          request.url.toString(), 'https://example.invalid/email/upload-pdf');
      expect(request.headers['authorization'], 'Bearer A');
      expect(request.headers['content-type'],
          startsWith('multipart/form-data; boundary='));
      final body = request.body;
      for (final value in [
        'recipient',
        'recipient@example.com',
        'senderName',
        'Sender',
        'message',
        'Message',
        'file',
        'cme_history.pdf',
        'application/pdf',
        '%PDF'
      ]) {
        expect(body, contains(value));
      }
    }, () => client);
  });

  for (final scenario in [
    'no provider',
    'missing',
    'blank',
    'expired',
    'logout',
    'switch',
    'reuse'
  ]) {
    testWidgets('$scenario prevents email but preserves preview and sharing',
        (tester) async {
      await http.runWithClient(() async {
        if (scenario == 'missing') auth.token = null;
        if (scenario == 'blank') auth.token = '  ';
        if (scenario == 'expired') auth.expired = true;
        await mount(tester, provider: scenario != 'no provider');
        if (scenario == 'logout' || scenario == 'reuse') auth.change(null);
        if (scenario == 'switch') auth.change('B');
        if (scenario == 'reuse') auth.change('A');
        await dialog(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(requests, isEmpty);
        expect(find.byType(SfPdfViewer), findsOneWidget);
        await tester.tap(find.byIcon(Icons.share));
        await tester.pumpAndSettle();
        expect(shares.single.method, 'sharePdf');
        expect((shares.single.arguments as Map)['doc'], pdf.bytes);
      }, () => client);
    });
  }

  testWidgets('unchanged session notifications allow sending', (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      auth.change('A');
      await dialog(tester);
      auth.change('A');
      await submit(tester);
      expect(requests.single.headers['authorization'], 'Bearer A');
    }, () => client);
  });

  for (final stage in ['dialog', 'read']) {
    testWidgets(
        'account switch during $stage never sends cross-account request',
        (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        await dialog(tester);
        if (stage == 'dialog') auth.change('B');
        if (stage == 'read') pdf.pending = Completer<Uint8List>();
        await submit(tester);
        if (stage == 'read') {
          auth.change('B');
          pdf.pending!.complete(pdf.bytes);
          await tester.pumpAndSettle();
          // The PDF viewer schedules a delayed update after provider rebuilds.
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(requests, isEmpty);
        expect(find.byType(SfPdfViewer), findsOneWidget);
      }, () => client);
    });
  }

  ElevatedButton emailButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(
          find.byWidgetPredicate((widget) => widget is ElevatedButton));

  testWidgets('rapid callbacks open one dialog and cancellation releases guard',
      (tester) async {
    await mount(tester);
    final action = emailButton(tester).onPressed!;
    action();
    action(); // No frame between callbacks.
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(emailButton(tester).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(emailButton(tester).onPressed, isNotNull);
    await dialog(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  for (final stage in ['read', 'response']) {
    testWidgets(
        'guard blocks repeated confirmation and actions during pending $stage',
        (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        final action = emailButton(tester).onPressed!;
        await dialog(tester);
        await tester.enterText(
            find.byType(TextField).at(0), 'recipient@example.com');
        await tester.enterText(find.byType(TextField).at(1), 'Sender');
        if (stage == 'read') pdf.pending = Completer<Uint8List>();
        if (stage == 'response') response = Completer<http.Response>();
        final confirm = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Send'))
            .onPressed!;
        confirm();
        confirm();
        await tester.pumpAndSettle();
        action();
        expect(emailButton(tester).onPressed, isNull);
        expect(requests, hasLength(stage == 'read' ? 0 : 1));
        if (stage == 'read') pdf.pending!.complete(pdf.bytes);
        if (stage == 'response') response!.complete(http.Response('{}', 403));
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        expect(emailButton(tester).onPressed, isNotNull);
      }, () => client);
    });
  }

  testWidgets('explicit rejection permits a later submission', (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await dialog(tester);
      await submit(tester);
      await dialog(tester);
      await submit(tester);
      expect(requests, hasLength(2));
    }, () => client);
  });

  testWidgets('PDF read failure releases guard without uploading',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await dialog(tester);
      pdf.failRead = true;
      await submit(tester);
      expect(requests, isEmpty);
      expect(emailButton(tester).onPressed, isNotNull);
      pdf.failRead = false;
      await dialog(tester);
      await submit(tester);
      expect(requests, hasLength(1));
    }, () => client);
  });

  testWidgets('confirmed success stays blocked after cleanup failure',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      final action = emailButton(tester).onPressed!;
      response = Completer<http.Response>()
        ..complete(http.Response('{"message":"Email sent successfully"}', 200));
      pdf.failCleanup = true;
      await dialog(tester);
      await submit(tester);
      expect(emailButton(tester).onPressed, isNull);
      action();
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SfPdfViewer), findsOneWidget);
    }, () => client);
  });

  testWidgets(
      'session invalidation during upload cannot produce another request',
      (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      final action = emailButton(tester).onPressed!;
      response = Completer<http.Response>();
      await dialog(tester);
      await submit(tester);
      auth.change('B');
      action();
      response!.complete(http.Response('{}', 403));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      action();
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(requests.single.headers['authorization'], 'Bearer A');
      expect(find.byType(AlertDialog), findsNothing);
    }, () => client);
  });

  testWidgets('HTTP 200 deletes owned PDF and navigates to success',
      (tester) async {
    await http.runWithClient(() async {
      response = Completer<http.Response>()
        ..complete(http.Response('{"message":"Email sent successfully"}', 200));
      await mount(tester);
      await dialog(tester);
      await submit(tester);
      expect(pdf.deletions, 1);
      expect(pdf.present, isFalse);
      expect(find.byType(EmailSuccessScreen), findsOneWidget);
      expect(requests, hasLength(1));
    }, () => client);
  });

  for (final status in [401, 403, 500]) {
    testWidgets('HTTP $status is explicit rejection and retains PDF',
        (tester) async {
      await http.runWithClient(() async {
        response = Completer<http.Response>()
          ..complete(http.Response('{}', status));
        await mount(tester);
        await dialog(tester);
        await submit(tester);
        expect(
            find.text(
                'The server rejected the email request. Please try again later.'),
            findsOneWidget);
        expect(pdf.deletions, 0);
        expect(pdf.present, isTrue);
        expect(emailButton(tester).onPressed, isNotNull);
        expect(auth.token, 'A');
        expect(requests, hasLength(1));
      }, () => client);
    });
  }

  for (final failure in ['timeout', 'connection']) {
    testWidgets(
        '$failure is uncertain, retains PDF, releases busy, and never retries',
        (tester) async {
      await http.runWithClient(() async {
        response = Completer<http.Response>();
        await mount(tester);
        await dialog(tester);
        await submit(tester);
        expect(emailButton(tester).onPressed, isNull);
        if (failure == 'timeout') {
          await tester.pump(const Duration(seconds: 30));
        } else {
          response!.completeError(
              http.ClientException('Connection lost during upload'));
        }
        await tester.pumpAndSettle();
        expect(
            find.text(
                'The email may have been sent. Check with the recipient before retrying.'),
            findsOneWidget);
        expect(emailButton(tester).onPressed, isNotNull);
        expect(pdf.deletions, 0);
        expect(pdf.present, isTrue);
        expect(requests, hasLength(1));
        if (failure == 'timeout') {
          // A late accepted response must not resume cleanup/navigation.
          response!.complete(http.Response('{}', 200));
        }
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        expect(pdf.deletions, 0);
        expect(find.byType(EmailSuccessScreen), findsNothing);
      }, () => client);
    });
  }

  for (final stage in ['HTTP', 'exists']) {
    for (final transition in ['switch', 'logout', 'dispose']) {
      testWidgets('$transition during $stage prevents stale deletion and UI',
          (tester) async {
        await http.runWithClient(() async {
          response = Completer<http.Response>();
          if (stage == 'exists') pdf.existence = Completer<bool>();
          await mount(tester);
          await dialog(tester);
          await submit(tester);
          if (stage == 'exists') {
            response!.complete(http.Response('{}', 200));
            await tester.pumpAndSettle();
          }
          if (transition == 'dispose') {
            await tester
                .pumpWidget(const MaterialApp(home: Text('New screen')));
          } else {
            auth.change(transition == 'switch' ? 'B' : null);
          }
          if (stage == 'HTTP') response!.complete(http.Response('{}', 200));
          if (stage == 'exists') pdf.existence!.complete(true);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 300));
          expect(pdf.deletions, 0);
          expect(pdf.present, isTrue);
          expect(find.byType(EmailSuccessScreen), findsNothing);
          expect(find.byType(SnackBar), findsNothing);
          expect(tester.takeException(), isNull);
          expect(requests, hasLength(1));
        }, () => client);
      });
    }
  }
}
