import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_file/open_file.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
// Existing multipart MIME dependency, also supplied by http/printing.
// ignore: depend_on_referenced_packages
import 'package:http_parser/http_parser.dart';

import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'email_success_screen.dart';
import 'pdf_utils.dart';

enum _EmailOutcome { accepted, rejected, uncertain, notSent }

class PdfPreviewScreen extends StatefulWidget {
  final File pdfFile;

  const PdfPreviewScreen({super.key, required this.pdfFile});

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  AuthProvider? _auth;
  // Only logout cancels pending work; previews are not permanently account-bound.
  int _logoutGeneration = 0;
  bool _emailBusy = false;
  bool _emailSent = false;

  File get pdfFile => widget.pdfFile;

  @override
  void initState() {
    super.initState();
    retainCmePdf(pdfFile);
    _auth = context.read<AuthProvider?>();
    _auth?.addListener(_authChanged);
  }

  bool _hasAuthentication() {
    final auth = _auth;
    final token = auth?.authToken;
    return auth != null &&
        auth.isLoggedIn &&
        !auth.isLoading &&
        token != null &&
        token.trim().isNotEmpty &&
        !auth.isTokenExpired();
  }

  void _authChanged() {
    if (_auth?.isLoggedIn != true) _logoutGeneration++;
  }

  bool _canContinue(int logoutGeneration) =>
      mounted && logoutGeneration == _logoutGeneration && _hasAuthentication();

  @override
  void didUpdateWidget(covariant PdfPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfFile.path != pdfFile.path) {
      releaseCmePdf(oldWidget.pdfFile);
      retainCmePdf(pdfFile);
    }
  }

  @override
  void dispose() {
    releaseCmePdf(pdfFile);
    _auth?.removeListener(_authChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Preview PDF"),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async {
              await Printing.sharePdf(
                bytes: await pdfFile.readAsBytes(),
                filename: 'cme_history.pdf',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              await OpenFile.open(pdfFile.path);
            },
          ),
        ],
      ),
      body: SfPdfViewer.file(pdfFile),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ElevatedButton.icon(
          icon: Icon(Icons.send),
          label: Text("Email CME History"),
          onPressed: _emailBusy || _emailSent ? null : _emailPdf,
        ),
      ),
    );
  }

  Future<void> _emailPdf() async {
    // Set synchronously: callbacks already queued before a rebuild also stop.
    if (_emailBusy || _emailSent || !mounted) return;
    setState(() => _emailBusy = true);
    final logoutGeneration = _logoutGeneration;
    try {
      final token = _auth?.authToken;
      if (!_canContinue(logoutGeneration)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please log in before emailing.'),
        ));
        return;
      }
      final result = await promptEmailForm(context);
      if (result == null || !_canContinue(logoutGeneration)) return;

      final pdfBytes = await pdfFile.readAsBytes();
      if (!_canContinue(logoutGeneration)) return;

      final outcome = await sendPdfToBackendWithRecipient(
        pdfBytes,
        token: token!,
        logoutGeneration: logoutGeneration,
        recipientEmail: result['email']!,
        senderName: result['name']!,
        message: result['message']!,
      );

      if (outcome == _EmailOutcome.accepted) _emailSent = true;
      if (!_canContinue(logoutGeneration)) return;
      if (outcome == _EmailOutcome.accepted) {
        // Delete the local file
        final exists = await pdfFile.exists();
        if (!_canContinue(logoutGeneration)) return;
        if (exists) {
          await pdfFile.delete();
        }

        if (!_canContinue(logoutGeneration)) return;

        if (!mounted) return;

        // Navigate to success screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => EmailSuccessScreen(email: result['email']!)),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(switch (outcome) {
            _EmailOutcome.uncertain =>
              'The email may have been sent. Check with the recipient before retrying.',
            _EmailOutcome.rejected =>
              'The server rejected the email request. Please try again later.',
            _ => 'Email was not sent. Please check your session and try again.',
          })),
        );
      }
    } catch (_) {
      if (mounted && _canContinue(logoutGeneration)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_emailSent
              ? 'Email sent, but the preview could not be closed.'
              : 'Email was not sent. Please try again.'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _emailBusy = false);
      }
    }
  }

  Future<Map<String, String>?> promptEmailForm(BuildContext context) async {
    String email = '';
    String name = '';
    String message = '';
    bool submitted = false;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Email CME History'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(labelText: 'Recipient Email'),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (value) => email = value,
                ),
                TextField(
                  decoration: InputDecoration(labelText: 'Your Name'),
                  onChanged: (value) => name = value,
                ),
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Message (optional)',
                  ),
                  maxLines: 3,
                  onChanged: (value) => message = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            TextButton(
              onPressed: () {
                if (submitted) return;
                if (email.isEmpty || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Name and email are required')),
                  );
                } else {
                  submitted = true;
                  Navigator.pop(context, {
                    'email': email,
                    'name': name,
                    'message': message,
                  });
                }
              },
              child: Text('Send'),
            ),
          ],
        );
      },
    );
  }

  Future<_EmailOutcome> sendPdfToBackendWithRecipient(
    Uint8List pdfBytes, {
    required String token,
    required int logoutGeneration,
    required String recipientEmail,
    required String senderName,
    required String message,
  }) async {
    final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final apiEndpoint = '/email/upload-pdf';

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBaseUrl$apiEndpoint'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    request.fields['recipient'] = recipientEmail;
    request.fields['senderName'] = senderName;
    request.fields['message'] = message;

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        pdfBytes,
        filename: 'cme_history.pdf',
        contentType: MediaType('application', 'pdf'),
      ),
    );

    if (!_canContinue(logoutGeneration)) {
      return _EmailOutcome.notSent;
    }
    final client = http.Client();
    try {
      // Bound the upload/response wait, not the recipient dialog. A timeout
      // cannot retract server processing or establish that email was not sent.
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      return response.statusCode == 200
          ? _EmailOutcome.accepted
          : _EmailOutcome.rejected;
    } catch (_) {
      // Once sending has begun, transport failures cannot prove rejection.
      return _EmailOutcome.uncertain;
    } finally {
      client.close();
    }
  }
}
