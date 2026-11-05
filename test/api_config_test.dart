import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wired_test/config/api_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in ApiBuildMode.values) {
    test('$mode selects its default', () {
      expect(
          ApiConfig.resolve(mode: mode),
          mode == ApiBuildMode.debug
              ? ApiConfig.developmentUrl
              : ApiConfig.productionUrl);
    });
    test('$mode accepts production override and normalizes trailing slashes',
        () {
      expect(
          ApiConfig.resolve(
              mode: mode, overrideUrl: '${ApiConfig.productionUrl}///'),
          ApiConfig.productionUrl);
    });
    for (final invalid in [
      '',
      ' ',
      'not a URL',
      '/api',
      '//example.com/api',
      'ftp://example.com',
      'https://',
      'https://bad_host/api',
      'https://-bad.example/api',
      'http://999.999.999.999',
      'https://user:password@example.com/api',
      'https://@example.com',
      'https://example.com/api?',
      'https://example.com/api#',
      'https://example.com:0',
      'https://example.com:65536'
    ]) {
      test('$mode rejects invalid override $invalid', () {
        expect(() => ApiConfig.resolve(mode: mode, overrideUrl: invalid),
            throwsFormatException);
      });
    }
  }
  for (final url in [
    'http://localhost:3000/',
    'http://192.168.1.20:3000/api/',
    'https://staging.example.com/api/',
    'http://[::1]:3000/'
  ]) {
    test('debug permits testing endpoint $url', () {
      expect(ApiConfig.resolve(mode: ApiBuildMode.debug, overrideUrl: url),
          url.substring(0, url.length - 1));
    });
  }
  test('profile permits HTTPS staging', () {
    expect(
        ApiConfig.resolve(
            mode: ApiBuildMode.profile,
            overrideUrl: 'https://staging.example.com/api/'),
        'https://staging.example.com/api');
  });
  for (final mode in [ApiBuildMode.profile, ApiBuildMode.release]) {
    for (final host in [
      'localhost',
      'test.localhost',
      '127.0.0.1',
      '127.1.2.3',
      '[::1]',
      '[0:0:0:0:0:0:0:1]',
      '[::ffff:127.0.0.1]',
      '[::ffff:10.0.2.2]',
      '0.0.0.0',
      '[::]',
      '10.0.2.2',
      '10.0.3.2'
    ]) {
      test('$mode rejects development host $host even with HTTPS', () {
        expect(
            () => ApiConfig.resolve(mode: mode, overrideUrl: 'https://$host'),
            throwsFormatException);
      });
    }
    test('$mode rejects HTTP even on production host', () {
      expect(
          () => ApiConfig.resolve(
              mode: mode,
              overrideUrl: 'http://${ApiConfig.productionHost}/apiv2'),
          throwsFormatException);
    });
  }
  for (final host in [
    'staging.example.com',
    'widm.wiredhealthresources.net.evil.example',
    '192.168.1.20'
  ]) {
    test('release rejects unapproved host $host', () {
      expect(
          () => ApiConfig.resolve(
              mode: ApiBuildMode.release, overrideUrl: 'https://$host/apiv2'),
          throwsFormatException);
    });
  }
  test('release accepts case-normalized production host', () {
    expect(
        ApiConfig.resolve(
            mode: ApiBuildMode.release,
            overrideUrl: 'https://WIDM.WIREDHEALTHRESOURCES.NET/apiv2/'),
        ApiConfig.productionUrl);
  });
  test('resolved URL overrides bundled dotenv while preserving other values',
      () async {
    final env = DotEnv();
    final selected = ApiConfig.resolve(mode: ApiBuildMode.release);
    await env.load(fileName: '.env', mergeWith: {'API_BASE_URL': selected});
    expect(env.env['API_BASE_URL'], selected);
    // Exercise unrelated values without depending on local .env contents.
    env.loadFromString(
        envString: 'API_BASE_URL=http://10.0.2.2:3000\nOTHER_SETTING=kept',
        mergeWith: {'API_BASE_URL': selected});
    expect(env.env, {'API_BASE_URL': selected, 'OTHER_SETTING': 'kept'});
    expect(await rootBundle.loadString('.env'), isNotEmpty);
  });
}
