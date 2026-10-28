class DownloadableProgram {
  final int id;
  final String name;
  final String? trainingType;

  const DownloadableProgram({
    required this.id,
    required this.name,
    this.trainingType,
  });

  factory DownloadableProgram.fromJson(Map<String, dynamic> json) {
    return DownloadableProgram(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      trainingType: json['training_type']?.toString(),
    );
  }
}

class DownloadableModule {
  final int? id;
  final String moduleId;
  final String name;
  final String? description;
  final String? version;
  final String? downloadLink;
  final String? packageSize;
  final String? creditType;
  final List<DownloadableProgram> programs;
  final List<String> keywords;
  final List<String> categories;
  final List<String> subcategories;
  final List<String> specializations;

  const DownloadableModule({
    this.id,
    required this.moduleId,
    required this.name,
    this.description,
    this.version,
    this.downloadLink,
    this.packageSize,
    this.creditType,
    required this.programs,
    this.keywords = const [],
    this.categories = const [],
    this.subcategories = const [],
    this.specializations = const [],
  });

  bool belongsToTrainingType(String trainingType) {
    return programs.any(
      (program) => program.trainingType == trainingType,
    );
  }

  bool belongsToSpecialization(String specializationName) {
    final target = specializationName.trim().toLowerCase();

    return specializations.any(
      (name) => name.trim().toLowerCase() == target,
    );
  }

  bool get isDownloadable =>
      moduleId.isNotEmpty &&
      downloadLink != null &&
      downloadLink!.trim().isNotEmpty;

  /// Matches a phrase against the module's searchable catalog metadata.
  bool matchesSearch(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return false;
    final fields = <String>[
      name,
      description ?? '',
      ...keywords,
      ...categories,
      ...subcategories,
      ...specializations,
      ...programs.map((program) => program.name),
    ];
    return fields.any((field) => field.toLowerCase().contains(needle));
  }

  static List<String> _names(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => item['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  factory DownloadableModule.fromJson(Map<String, dynamic> json) {
    final subcategoryItems = json['subCategories'];
    final subcategories = subcategoryItems is List
        ? subcategoryItems.whereType<Map>().toList()
        : <Map>[];

    return DownloadableModule(
      id: int.tryParse(json['id']?.toString() ?? ''),
      moduleId: json['module_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      version: json['version']?.toString(),
      downloadLink: json['downloadLink']?.toString(),
      packageSize: json['packageSize']?.toString(),
      creditType: json['credit_type']?.toString(),
      programs: (json['programs'] as List<dynamic>? ?? [])
          .map((item) => DownloadableProgram.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      keywords: _names(json['keywords']),
      subcategories: _names(subcategoryItems),
      categories: subcategories
          .map((item) => item['category'])
          .whereType<Map>()
          .map((category) => category['name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList(),
      specializations: _names(json['specializations']),
    );
  }
}
