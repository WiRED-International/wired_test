import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/services/module_download_service.dart';

class _IsolatedService extends ModuleDownloadService {
  _IsolatedService(this.folder);
  final Directory folder;
  @override
  Future<Directory> getDownloadsDirectory() async {
    await folder.create(recursive: true);
    return folder;
  }
}

// Test-only self-signed localhost certificate, never used by the app.
const _cert = r'''
-----BEGIN CERTIFICATE-----
MIIDJTCCAg2gAwIBAgIUCBA2p6Bm4O4Nahon7fvU4Hvsp4YwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MTAxOTExMjMyM1oXDTI2MTAy
MTExMjMyM1owFDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEF
AAOCAQ8AMIIBCgKCAQEAt02bRKu7loMoi/kMGblaQkiKwpY6yqo5rr1Vp+eDYy2x
eKGUiYsFqp+xkkw5osAoucUXo3uFwLsvxRKuEgP1sDzOXyISoimBVVIyqKPcn1O/
yzghML86Blt1aTFUHxH4pKhzBZWCDMCsJolUkRvNTeS/rV5aXsU+meNmlxnDy00N
r2eqX3XlLkzg1UEy/08i1a3zJH2Ai/8cO1wNVyUnUbipEjJlpeImGz0nQ91Fx+ob
f0w+FPXAXilRhhVX53lWQJpKFXJWj9rJxKs0wanWZX6ulE2/ACAQrnOvjmErcmGS
n/w1uuq+0ZN1T9AtvkQOQ707R7YeHKpWdc2Qy3YHZQIDAQABo28wbTAdBgNVHQ4E
FgQUlUApuymcsBqP82fDrkEysAdF6zgwHwYDVR0jBBgwFoAUlUApuymcsBqP82fD
rkEysAdF6zgwDwYDVR0TAQH/BAUwAwEB/zAaBgNVHREEEzARgglsb2NhbGhvc3SH
BH8AAAEwDQYJKoZIhvcNAQELBQADggEBACiZokscoDENlRcTSSIxYNuETF+thUO3
+/xtkQCi5PgdESmo7eo3/kB1QNj5k8ixQ83F9bL7oUnu9qztvir7jZvbY1/5HQmi
CS0l4Mr/d/acOn6CKgA5ix0ZevJyb+eXAB52bGW1bESc5Fc5ztfyuT8nG3EGFagH
G2eFBHTK/O2H7K4jqgr2uzkLxsq6gvuowxoW8YVtxl2hEodwdxHCiQTYtBAYo817
hdfP/BtKd2zQCta8byolIxpHyicrv/5ufoRjENMte6lLuO9zE7pLtyedQPYZ7zFN
myn0Z1lJY/vc6TTU9Wegsxu3KHecgZFYOCaspiDOhSsTUQRv8u1VPLE=
-----END CERTIFICATE-----
''';
const _key = r'''
-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQC3TZtEq7uWgyiL
+QwZuVpCSIrCljrKqjmuvVWn54NjLbF4oZSJiwWqn7GSTDmiwCi5xReje4XAuy/F
Eq4SA/WwPM5fIhKiKYFVUjKoo9yfU7/LOCEwvzoGW3VpMVQfEfikqHMFlYIMwKwm
iVSRG81N5L+tXlpexT6Z42aXGcPLTQ2vZ6pfdeUuTODVQTL/TyLVrfMkfYCL/xw7
XA1XJSdRuKkSMmWl4iYbPSdD3UXH6ht/TD4U9cBeKVGGFVfneVZAmkoVclaP2snE
qzTBqdZlfq6UTb8AIBCuc6+OYStyYZKf/DW66r7Rk3VP0C2+RA5DvTtHth4cqlZ1
zZDLdgdlAgMBAAECggEACdWECv8bpUuMFVZbK9Yh3YR+zUm6Bb10Mse9nLBzABMn
fk1M5sQqnajLogms3eppRO4qAn9SAbEJMw15gUXtHHNmrvvo/AI2ChnK1flUkMex
dnmgbjkUJ9soRWh8Ft6j9FGFOjt3Kq/7jGW5v786GH+5ONfjCUqTvTXR/zFGq9Vy
6CivaLnOtRfCP8r68PeJNiQYm9DWiRuaXfOtvtoHmVKtqD0Qy9RVslGnrr8OqzRE
tGMS5ed3K0MCwRneqyJtHjy7KsO+1esMTz3kUQSs1ZJ6r4aOH7bpd5w0j/5Qts3D
ZB50D6wSUvVps4DInpilSB2Le6AME1HadEQfucma0QKBgQD+HhmCd7H0C+PQWS9g
f97mr+DWSDXluoHD1nBJQ4HlqnoIGvhKKHWEi3GB9UeW99F7zrACliX3uO1vgMsW
pZrmT39tWsYMAINWh8PPJrBWuuAwZUCb9GsPDmdz5YPhV4HoKPkv/8b4abJtluZJ
tHwBAUp6slENfa3Xeiw67doRqwKBgQC4qTd4eeEbcb1H2leFUrLFMxph5Amwz5Yj
kQpeP+wt5Wd6BLeOdu9JaftDa8zqWjiqtZPWp7RUPfnqdV89sHXdG8hWy6Tky8hK
AZ8zl2hTho4qKSLcG/Dqbv9n6eSE2p7ZzMsXV4amuzFdR7tIj6jl4wHHx4W0oqHK
jRAB2W9bLwKBgQDh0t3Yk4YQ2oAZJyhzGS980c98na9H9/ZZkrc2ZEeLUXQgv9bm
EA5fO4wjcVWtU41V+NdxdP1Ip45ZCJtyBLki8oLLK1/USqBsxTm9XSRX7rpMR66i
6RI6zxIgbFZGav2G0uKfRS4Mk+F8gh0kYr/QJNWLM+vTkVxroKatt7GTAQKBgQCp
BeKLOOwOJc6+PSGNHEQb8om8fnFMUMY5aeIWoOX6oJdVfYnSMhUWmpZtgPfArrJd
tvRKL5kE3vGpZKO3oJRRvcNjhuU4szpyWwewvm60vV3VQ2/wDvc2bkEDiXgtDrsF
2skuZWQPqxolKqpHYY+UVHPlvEArNg1njDTRrIeb6wKBgQDrLijl5LsOGi3466ow
bCDoyCh16QT4pcBgcXt57nGM+tdzT3QqltruNTXIh0pLdS3nW4s9rhLT/2wDH8xh
ThHdi0rDd96YlquC0nr+TJVOUT3ZolsPTKqz2XKBbPbmZxFz8laUNAjq2HBzokiG
3vh9yfTX23U3OfZB2HI7OK0Qbg==
-----END PRIVATE KEY-----
''';

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (cert, host, port) => host == 'localhost';
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _IsolatedService service;
  HttpServer? server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('healthmap_resume_');
    service = _IsolatedService(Directory('${temp.path}/downloads'));
  });
  tearDown(() async {
    await server?.close(force: true);
    server = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<String> startServer({required List<int> data,
    required String currentEtag,
    void Function(String?, String?)? onHeaders}) async {
    final certFile = File('${temp.path}/cert.pem');
    final keyFile = File('${temp.path}/key.pem');
    await certFile.writeAsString(_cert);
    await keyFile.writeAsString(_key);
    final context = SecurityContext()
      ..useCertificateChain(certFile.path)
      ..usePrivateKey(keyFile.path);
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    server!.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final ifRange = request.headers.value('if-range');
      onHeaders?.call(range, ifRange);
      final match = RegExp(r'^bytes=(\d+)-$').firstMatch(range ?? '');
      final canResume = match != null && ifRange == currentEtag;
      final start = canResume ? int.parse(match.group(1)!) : 0;
      request.response.headers.set('etag', currentEtag);
      if (canResume) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.contentRangeHeader,
            'bytes $start-${data.length - 1}/${data.length}');
      } else {
        request.response.statusCode = HttpStatus.ok;
      }
      request.response.headers.contentLength = data.length - start;
      request.response.add(data.sublist(start));
      await request.response.close();
    });
    return 'https://localhost:${server!.port}/module.zip';
  }

  Future<File> download(String moduleId, String url) => HttpOverrides.runZoned(
        () => service.downloadModuleZip(moduleId: moduleId, downloadUrl: url),
    createHttpClient: _TestHttpOverrides().createHttpClient,
  );

  test('changed ETag restarts with new ZIP bytes, never mixes versions', () async {
    final oldData = Uint8List.fromList(List.filled(500, 17));
    final newData = Uint8List.fromList(List.filled(500, 42));
    String? requestedRange;
    String? requestedIfRange;
    final url = await startServer(
      data: newData,
      currentEtag: '"version-2"',
      onHeaders: (range, ifRange) {
        requestedRange = range;
        requestedIfRange = ifRange;
      },
    );
    final folder = await service.getDownloadsDirectory();
    await File('${folder.path}/92001.zip.part')
        .writeAsBytes(oldData.sublist(0, 200));
    await File('${folder.path}/92001.zip.source').writeAsString(url);
    await File('${folder.path}/92001.zip.etag').writeAsString('"version-1"');

    final result = await download('92001', url);
    expect(requestedRange, 'bytes=200-');
    expect(requestedIfRange, '"version-1"');
    expect(await result.readAsBytes(), newData);
    expect(await File('${folder.path}/92001.zip.etag').exists(), isFalse);
  });

  test('matching ETag resumes safely using 206', () async {
    final data = Uint8List.fromList(List.generate(500, (i) => i % 251));
    String? requestedRange;
    String? requestedIfRange;
    final url = await startServer(
      data: data,
      currentEtag: '"same-version"',
      onHeaders: (range, ifRange) {
        requestedRange = range;
        requestedIfRange = ifRange;
      },
    );
    final folder = await service.getDownloadsDirectory();
    await File('${folder.path}/92002.zip.part')
        .writeAsBytes(data.sublist(0, 200));
    await File('${folder.path}/92002.zip.source').writeAsString(url);
    await File('${folder.path}/92002.zip.etag').writeAsString('"same-version"');

    final result = await download('92002', url);
    expect(requestedRange, 'bytes=200-');
    expect(requestedIfRange, '"same-version"');
    expect(await result.readAsBytes(), data);
  });
}