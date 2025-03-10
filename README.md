# wired_test

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

#For Development

If it is necessary to make API calls to a local database rather than the remote database during development, switch the API endpoints from the "remoteServer" variable to "localServer". 

Here is an example on the home_page.dart file:

  Future<Alert?> getAlert() async {
    const remoteServer = 'http://widm.wiredhealthresources.net/apiv2/alerts/latest';
    const localServer = 'http://10.0.2.2:3000/alerts/latest';
    try {
      final response = await http.get(Uri.parse(localServer));

It may be necessary to make the switch from remote to local on more than one page depending on the nature of the development. Making calls to the remote server and to a local server will most likely result in errors. It will probably not be required to switch all API calls to "localServer", so be aware of which API endpoints need to be switched for development. 

Please try to remember to switch the endpoints back to "remoteServer" before making a pull request. 




