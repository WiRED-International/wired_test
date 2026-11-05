import 'dart:io';

import 'package:flutter/foundation.dart';

enum ApiBuildMode { debug, profile, release }

class ApiConfig {
  static const developmentUrl = 'http://10.0.2.2:3000';
  static const productionHost = 'widm.wiredhealthresources.net';
  static const productionUrl = 'https://$productionHost/apiv2';

  /// Null means no override; an explicitly empty define must fail validation.
  static String forCurrentBuild() => resolve(
        mode: kReleaseMode
            ? ApiBuildMode.release
            : kProfileMode
                ? ApiBuildMode.profile
                : ApiBuildMode.debug,
        overrideUrl: const bool.hasEnvironment('API_BASE_URL')
            ? const String.fromEnvironment('API_BASE_URL')
            : null,
      );

  static String resolve({required ApiBuildMode mode, String? overrideUrl}) {
    final value = overrideUrl ??
        (mode == ApiBuildMode.debug ? developmentUrl : productionUrl);
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        value != value.trim() ||
        uri == null ||
        !uri.isAbsolute ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme) ||
        !_validHost(uri.host) ||
        RegExp(r'^[^:/]+://[^/?#]*@').hasMatch(value) ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('Invalid API_BASE_URL');
    }
    if (mode != ApiBuildMode.debug &&
        (uri.scheme != 'https' || _developmentHost(uri.host))) {
      throw const FormatException(
          'Profile and release API URLs require HTTPS and a non-development host');
    }
    if (mode == ApiBuildMode.release && uri.host != productionHost) {
      throw const FormatException(
          'Release API URL must use the production host');
    }
    return uri
        .replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''))
        .toString();
  }

  static bool _validHost(String host) {
    host = host.replaceAll(RegExp(r'^\[|\]$'), '');
    if (host.isEmpty) return false;
    if (InternetAddress.tryParse(host) != null) return true;
    if (host.length > 253 || RegExp(r'^[0-9.]+$').hasMatch(host)) return false;
    return host.split('.').every((label) =>
        label.length <= 63 &&
        RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label));
  }

  static bool _developmentHost(String host) {
    host = host.replaceAll(RegExp(r'^\[|\]$'), '');
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '10.0.2.2' ||
        host == '10.0.3.2') {
      return true;
    }
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    final bytes = address.rawAddress;
    final mappedIpv4 = bytes.length == 16 &&
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255;
    return address.isLoopback ||
        bytes.every((byte) => byte == 0) ||
        (mappedIpv4 && _developmentHost(bytes.skip(12).join('.')));
  }
}
