import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/downloadable_module.dart';

/// Retrieves available modules and their program associations
/// from the WiRED modules API.
class ModuleCatalogService {
  Future<List<DownloadableModule>> fetchModules() async {
    final apiBaseUrl =
        dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final uri = Uri.parse(
      '${apiBaseUrl.replaceAll(RegExp(r"/+$"), "")}/modules',
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
      },
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Unable to retrieve modules. '
            'Server returned ${response.statusCode}.',
      );
    }

    final data = jsonDecode(response.body);

    if (data is! List) {
      throw FormatException(
        'Invalid module catalog response.',
      );
    }

    final modules = data
        .map(
          (item) => DownloadableModule.fromJson(
        Map<String, dynamic>.from(item as Map),
      ),
    )
        .where((module) => module.isDownloadable)
        .toList();

    modules.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return modules;
  }
}
