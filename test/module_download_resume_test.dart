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

  Future<String> startServer({required List<int> data, required bool honorRange,
    void Function(String?)? onRange}) async {
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
      onRange?.call(range);
      final match = RegExp(r'^bytes=(\d+)-$').firstMatch(range ?? '');
      final start = honorRange && match != null ? int.parse(match.group(1)!) : 0;
      if (start > 0) {
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

  test('resumes with 206 and preserves exact bytes', () async {
    final data = Uint8List.fromList(List.generate(1024, (i) => i % 251));
    String? range;
    final url = await startServer(data: data, honorRange: true,
        onRange: (value) => range = value);
    final folder = await service.getDownloadsDirectory();
    await File('${folder.path}/91001.zip.part').writeAsBytes(data.sublist(0, 300));
    await File('${folder.path}/91001.zip.source').writeAsString(url);
    final result = await download('91001', url);
    expect(range, 'bytes=300-');
    expect(await result.readAsBytes(), data);
    expect(await File('${folder.path}/91001.zip.part').exists(), isFalse);
    expect(await File('${folder.path}/91001.zip.source').exists(), isFalse);
  });

  test('restarts rather than appending when server ignores Range', () async {
    final data = Uint8List.fromList(List.generate(512, (i) => i % 199));
    String? range;
    final url = await startServer(data: data, honorRange: false,
        onRange: (value) => range = value);
    final folder = await service.getDownloadsDirectory();
    await File('${folder.path}/91002.zip.part').writeAsBytes([1, 2, 3, 4]);
    await File('${folder.path}/91002.zip.source').writeAsString(url);
    final result = await download('91002', url);
    expect(range, 'bytes=4-');
    expect(await result.readAsBytes(), data);
  });

  test('does not reuse partial bytes from a different URL', () async {
    final data = Uint8List.fromList(List.generate(256, (i) => i % 127));
    String? range;
    final url = await startServer(data: data, honorRange: true,
        onRange: (value) => range = value);
    final folder = await service.getDownloadsDirectory();
    await File('${folder.path}/91003.zip.part').writeAsBytes([99, 98, 97]);
    await File('${folder.path}/91003.zip.source')
        .writeAsString('https://example.com/different.zip');
    final result = await download('91003', url);
    expect(range, isNull);
    expect(await result.readAsBytes(), data);
  });
}

