import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewScreen extends StatelessWidget {
  final URLRequest urlRequest;

  const WebViewScreen({required this.urlRequest});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Offline Module"),
      ),
      body: InAppWebView(
        initialUrlRequest: urlRequest,
        //url: Uri.parse("file:///storage/emulated/0/Android/data/com.example.wired_test/files/Flu - Influenza.htm"),
        initialOptions: InAppWebViewGroupOptions(
          crossPlatform: InAppWebViewOptions(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            useOnLoadResource: true,
            useOnDownloadStart: true,
          ),
          android: AndroidInAppWebViewOptions(
            allowFileAccess: true,
            useWideViewPort: true,
            useHybridComposition: true,
          ),
          ios: IOSInAppWebViewOptions(
            allowsInlineMediaPlayback: true,
          ),
        ),
        // onDownloadStart: (controller, url) async {
        //   if (url != null) {
        //     _downloadFile(url);
        //   }
        // }
      ),
    );
  }
}