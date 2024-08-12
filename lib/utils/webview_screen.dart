import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Offline Module"),
      ),
      body: InAppWebView(
        //initialFile: "assets/modules/test.htm",
        initialUrlRequest: URLRequest(
          url: Uri.parse("file:///storage/emulated/0/Android/data/com.example.wired_test/files/Flu - Influenza.htm"),
          //url: WebUri("file:///android_asset/assets/modules/Family%20Planning%20Module.htm"),
        ),
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