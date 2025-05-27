import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_file/open_file.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'email_success_screen.dart';

class PdfPreviewScreen extends StatelessWidget {
  final File pdfFile;

  const PdfPreviewScreen({super.key, required this.pdfFile});

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
          onPressed: () async {
            final result = await promptEmailForm(context);
            if (result == null) return;

            final pdfBytes = await pdfFile.readAsBytes();

            final success = await sendPdfToBackendWithRecipient(
              pdfBytes,
              recipientEmail: result['email']!,
              senderName: result['name']!,
              message: result['message']!,
            );

            if (success) {
              // Delete the local file
              if (await pdfFile.exists()) {
                await pdfFile.delete();
              }

              // Navigate to success screen
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => EmailSuccessScreen(email: result['email']!)),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Failed to send email")),
              );
            }
          },
        ),
      ),
    );
  }

  Future<Map<String, String>?> promptEmailForm(BuildContext context) async {
    String email = '';
    String name = '';
    String message = '';

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
                if (email.isEmpty || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Name and email are required')),
                  );
                } else {
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

  Future<bool> sendPdfToBackendWithRecipient(
      Uint8List pdfBytes, {
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

    final response = await request.send();
    return response.statusCode == 200;
  }
}





