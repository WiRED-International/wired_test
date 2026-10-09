import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../providers/auth_guard.dart';
import '../../utils/app_layout.dart';
import '../../utils/custom_app_bar.dart';
import '../../utils/custom_nav_bar.dart';
import '../../utils/functions.dart';
import '../../utils/side_nav_bar.dart';

import '../creditsTracker/credits_tracker.dart';
import '../home_page.dart';
import '../module_library.dart';
import '../menu/menu.dart';

class ClassesPage extends StatefulWidget {
  const ClassesPage({Key? key}) : super(key: key);

  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  final _storage = const FlutterSecureStorage();

  late Future<List<dynamic>> availableClasses;

  @override
  void initState() {
    super.initState();
    availableClasses = fetchAvailableClasses();
  }

  Future<List<dynamic>> fetchAvailableClasses() async {
    final apiBaseUrl =
        dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/api/classes/available';

    final token = await _storage.read(key: 'authToken');

    if (token == null) {
      throw Exception('User is not logged in');
    }

    final response = await http.get(
      Uri.parse('$apiBaseUrl$apiEndpoint'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load available classes: ${response.statusCode}',
      );
    }

    final data =
    jsonDecode(response.body) as Map<String, dynamic>;

    return data['classes'] as List<dynamic>;
  }

  Future<void> enrollInClass(int classId) async {
    final apiBaseUrl =
        dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint = '/api/classes/$classId/enroll';

    final token = await _storage.read(key: 'authToken');

    if (token == null) {
      throw Exception('User is not logged in');
    }

    final response = await http.post(
      Uri.parse('$apiBaseUrl$apiEndpoint'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    final responseData =
    jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 201 &&
        response.statusCode != 200) {
      throw Exception(
        responseData['message'] ??
            'Unable to enroll in this class.',
      );
    }

    if (!mounted) return;

    setState(() {
      availableClasses = fetchAvailableClasses();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          responseData['message'] ?? 'Enrollment successful.',
        ),
      ),
    );
  }

  Future<void> withdrawFromClass(int classId) async {
    final apiBaseUrl =
        dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint =
        '/api/classes/$classId/enrollment';

    final token = await _storage.read(key: 'authToken');

    if (token == null) {
      throw Exception('User is not logged in');
    }

    final response = await http.delete(
      Uri.parse('$apiBaseUrl$apiEndpoint'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    Map<String, dynamic> responseData = {};

    try {
      responseData =
      jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}

    if (response.statusCode != 200) {
      throw Exception(
        responseData['message'] ??
            'Unable to withdraw from this class.',
      );
    }

    if (!mounted) return;

    setState(() {
      availableClasses = fetchAvailableClasses();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          responseData['message'] ??
              'You have successfully withdrawn from this class.',
        ),
      ),
    );
  }

  Future<List<dynamic>> fetchSpecializations(int classId) async {
    final apiBaseUrl =
        dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint =
        '/api/classes/$classId/specializations';

    final token = await _storage.read(key: 'authToken');

    if (token == null) {
      throw Exception('User is not logged in');
    }

    final response = await http.get(
      Uri.parse('$apiBaseUrl$apiEndpoint'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      String message = 'Unable to load specializations.';

      try {
        final responseData =
        jsonDecode(response.body) as Map<String, dynamic>;

        if (responseData['message'] != null) {
          message = responseData['message'].toString();
        }
      } catch (_) {}

      throw Exception(message);
    }

    final data =
    jsonDecode(response.body) as Map<String, dynamic>;

    return data['specializations'] as List<dynamic>;
  }

  Future<void> selectSpecialization(
      int classId,
      int specializationId,
      ) async {
    final apiBaseUrl =
        dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';

    final apiEndpoint =
        '/api/classes/$classId/select-specialization';

    final token = await _storage.read(key: 'authToken');

    if (token == null) {
      throw Exception('User is not logged in');
    }

    final response = await http.post(
      Uri.parse('$apiBaseUrl$apiEndpoint'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'specialization_id': specializationId,
      }),
    );

    Map<String, dynamic> responseData = {};

    try {
      responseData =
      jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}

    if (response.statusCode != 200 &&
        response.statusCode != 201) {
      throw Exception(
        responseData['message'] ??
            'Unable to change specialization.',
      );
    }

    if (!mounted) return;

    setState(() {
      availableClasses = fetchAvailableClasses();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          responseData['message'] ??
              'Specialization updated successfully.',
        ),
      ),
    );
  }

  Future<void> showSpecializationChoices(
      int classId,
      String? currentSpecializationName,
      ) async {
    try {
      final specializations =
        await fetchSpecializations(classId);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Choose Specialization'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: specializations.length,
                separatorBuilder: (context, index) =>
                const Divider(),
                itemBuilder: (context, index) {
                  final specialization =
                    specializations[index]
                  as Map<String, dynamic>;

                  final name =
                      specialization['name']?.toString() ??
                          'Specialization';

                  final isCurrent =
                      name == currentSpecializationName;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(name),
                    trailing: isCurrent
                        ? const Icon(
                      Icons.check,
                      color: Color(0xFF548235),
                    )
                        : null,
                    onTap: isCurrent
                        ? null
                        : () async {
                      final specializationId =
                        specialization['id'] as int;

                      // Close the list of specialization choices first.
                      Navigator.of(dialogContext).pop();

                      final confirmed =
                        await _confirmSpecializationSelection(
                          name,
                          currentSpecializationName,
                        );

                      if (!confirmed) {
                        return;
                      }

                      try {
                        await selectSpecialization(
                          classId,
                          specializationId,
                        );
                      } catch (e) {
                        if (!mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceFirst(
                                'Exception: ',
                                '',
                              ),
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          ),
        ),
      );
    }
  }

  String _formatDate(String dateString) {
    final date = DateTime.tryParse(dateString);

    if (date == null) {
      return dateString;
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<bool> _confirmEnrollment(
      String className,
      String programName,
      String? startDate,
      String? endDate,
      ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enroll in Class?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                className,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              Text(programName),

              if (startDate != null && endDate != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Class Dates: '
                      '${_formatDate(startDate)} – '
                      '${_formatDate(endDate)}',
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Enroll'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<bool> _confirmWithdrawal(
      String className,
      String programName,
      bool isSpecializationClass,
      ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Withdraw from Class?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                className,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              Text(programName),

              const SizedBox(height: 16),

              const Text(
                'Are you sure you want to withdraw from this class?',
              ),

              if (isSpecializationClass) ...[
                const SizedBox(height: 12),
                const Text(
                  'Withdrawing will also remove your specialization selection.',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Withdraw'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<bool> _confirmSpecializationSelection(
      String newSpecializationName,
      String? currentSpecializationName,
      ) async {
    final isChanging = currentSpecializationName != null;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            isChanging
                ? 'Change Specialization?'
                : 'Choose Specialization?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isChanging) ...[
                const Text('Current Specialization'),
                const SizedBox(height: 4),
                Text(
                  currentSpecializationName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('New Specialization'),
                const SizedBox(height: 4),
              ] else ...[
                const Text(
                  'Selecting this specialization will also enroll you in the class.',
                ),
                const SizedBox(height: 16),
              ],

              Text(
                newSpecializationName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(
                isChanging ? 'Change' : 'Choose & Enroll',
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final baseSize = mediaQuery.size.shortestSide;
    final isLandscape =
        mediaQuery.orientation == Orientation.landscape;

    return AppLayout(
      appBar: CustomAppBar(
        onBackPressed: () {
          Navigator.pop(context);
        },
        requireAuth: true,
      ),

      bottomNav: isLandscape
          ? null
          : CustomBottomNavBar(
        onHomeTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const MyHomePage(),
            ),
          );
        },
        onLibraryTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ModuleLibrary(),
            ),
          );
        },
        onTrackerTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AuthGuard(
                child: CreditsTracker(),
              ),
            ),
          );
        },
        onMenuTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Menu(),
            ),
          );
        },
      ),

      child: isLandscape
          ? Row(
        children: [
          CustomSideNavBar(
            onHomeTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                  const MyHomePage(),
                ),
              );
            },
            onLibraryTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ModuleLibrary(),
                ),
              );
            },
            onTrackerTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AuthGuard(
                    child: CreditsTracker(),
                  ),
                ),
              );
            },
            onMenuTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => Menu(),
                ),
              );
            },
          ),

          Expanded(
            child: _buildPageContent(
              context,
              screenWidth,
              screenHeight,
              baseSize,
            ),
          ),
        ],
      )
          : _buildPageContent(
        context,
        screenWidth,
        screenHeight,
        baseSize,
      ),
    );
  }

  Widget _buildPageContent(
      BuildContext context,
      double screenWidth,
      double screenHeight,
      double baseSize,
      ) {
    final isTabletDevice = isTablet(context);

    return Column(
      children: [
        SizedBox(
          height: baseSize *
              (isTabletDevice ? 0.03 : 0.03),
        ),

        Text(
          'Classes',
          style: TextStyle(
            fontSize: baseSize *
                (isTabletDevice ? 0.08 : 0.08),
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0070C0),
          ),
          textAlign: TextAlign.center,
        ),

        SizedBox(
          height: baseSize *
              (isTabletDevice ? 0.015 : 0.015),
        ),

        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: baseSize * 0.05,
          ),
          child: Text(
            'Classes available through your organization',
            style: TextStyle(
              fontSize: baseSize *
                  (isTabletDevice ? 0.035 : 0.04),
              fontWeight: FontWeight.w400,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        SizedBox(
          height: baseSize *
              (isTabletDevice ? 0.04 : 0.04),
        ),

        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: availableClasses,
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(baseSize * 0.05),
                    child: Text(
                      'Unable to load classes.\n${snapshot.error}',
                      style: TextStyle(
                        fontSize: baseSize *
                            (isTabletDevice ? 0.032 : 0.038),
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final classes = snapshot.data ?? [];

              if (classes.isEmpty) {
                return Center(
                  child: Text(
                    'No classes are currently available.',
                    style: TextStyle(
                      fontSize: baseSize *
                          (isTabletDevice ? 0.035 : 0.04),
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  baseSize * 0.04,
                  baseSize * 0.02,
                  baseSize * 0.04,
                  baseSize * 0.20,
                ),
                itemCount: classes.length,
                itemBuilder: (context, index) {
                  final classItem =
                  classes[index] as Map<String, dynamic>;

                  final program =
                  classItem['program'] as Map<String, dynamic>?;

                  final location =
                  classItem['location'] as Map<String, dynamic>?;

                  final bool isEnrolled =
                      classItem['is_enrolled'] == true;

                  final specializationSelection =
                  classItem['specialization_selection']
                  as Map<String, dynamic>?;

                  final selectedSpecialization =
                  specializationSelection?['specialization']
                  as Map<String, dynamic>?;

                  final trainingType =
                  program?['training_type']?.toString();

                  final bool isSpecializationClass =
                      trainingType == 'specialization';

                  return Card(
                    margin: EdgeInsets.only(
                      bottom: baseSize * 0.035,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(baseSize * 0.04),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            program?['name']?.toString() ??
                                'Program',
                            style: TextStyle(
                              fontSize: baseSize *
                                  (isTabletDevice
                                      ? 0.038
                                      : 0.043),
                              fontWeight: FontWeight.w600,
                              color:
                              const Color(0xFF0070C0),
                            ),
                          ),

                          SizedBox(height: baseSize * 0.012),

                          Text(
                            classItem['name']?.toString() ??
                                'Class',
                            style: TextStyle(
                              fontSize: baseSize *
                                  (isTabletDevice
                                      ? 0.034
                                      : 0.04),
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          if (location != null) ...[
                            SizedBox(
                              height: baseSize * 0.018,
                            ),
                            Text(
                              'Location: ${location['name']}',
                              style: TextStyle(
                                fontSize: baseSize *
                                    (isTabletDevice
                                        ? 0.03
                                        : 0.035),
                              ),
                            ),
                          ],

                          if (classItem['start_date'] != null &&
                              classItem['end_date'] != null) ...[
                            SizedBox(height: baseSize * 0.012),

                            Text(
                              'Class Dates: '
                                  '${_formatDate(classItem['start_date'].toString())} – '
                                  '${_formatDate(classItem['end_date'].toString())}',
                              style: TextStyle(
                                fontSize: baseSize *
                                    (isTabletDevice ? 0.03 : 0.035),
                              ),
                            ),
                          ],

                          if (classItem['enrollment_deadline'] != null) ...[
                            SizedBox(height: baseSize * 0.012),

                            Text(
                              'Enroll By: '
                                  '${_formatDate(classItem['enrollment_deadline'].toString())}',
                              style: TextStyle(
                                fontSize: baseSize *
                                    (isTabletDevice ? 0.03 : 0.035),
                              ),
                            ),
                          ],

                          if (isSpecializationClass &&
                              selectedSpecialization != null) ...[
                            SizedBox(height: baseSize * 0.018),

                            Text(
                              'Specialization: ${selectedSpecialization['name']}',
                              style: TextStyle(
                                fontSize: baseSize *
                                    (isTabletDevice ? 0.03 : 0.035),
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),

                            SizedBox(height: baseSize * 0.018),

                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: () {
                                  final classId = classItem['id'] as int;

                                  showSpecializationChoices(
                                    classId,
                                    selectedSpecialization['name']?.toString(),
                                  );
                                },
                                child: const Text('Change Specialization'),
                              ),
                            ),
                          ],

                          SizedBox(height: baseSize * 0.018),

                          if (isEnrolled)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Enrolled',
                                      style: TextStyle(
                                        fontSize: baseSize *
                                            (isTabletDevice ? 0.03 : 0.035),
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF548235),
                                      ),
                                    ),

                                    if (
                                    classItem['enrollment_deadline'] == null ||
                                        classItem['enrollment_deadline']
                                            .toString()
                                            .compareTo(
                                          DateTime.now()
                                              .toIso8601String()
                                              .split('T')[0],
                                        ) >=
                                            0
                                    )
                                      OutlinedButton(
                                        onPressed: () async {
                                          final classId =
                                          classItem['id'] as int;

                                          final className =
                                              classItem['name']?.toString() ??
                                                  'Class';

                                          final programName =
                                              program?['name']?.toString() ??
                                                  'Program';

                                          final confirmed =
                                          await _confirmWithdrawal(
                                            className,
                                            programName,
                                            isSpecializationClass,
                                          );

                                          if (!confirmed) {
                                            return;
                                          }

                                          try {
                                            await withdrawFromClass(classId);
                                          } catch (e) {
                                            if (!mounted) return;

                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  e.toString().replaceFirst(
                                                    'Exception: ',
                                                    '',
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: const Text('Withdraw'),
                                      ),
                                  ],
                                ),

                                if (isSpecializationClass &&
                                    selectedSpecialization == null) ...[
                                  SizedBox(height: baseSize * 0.018),

                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        final classId =
                                        classItem['id'] as int;

                                        showSpecializationChoices(
                                          classId,
                                          null,
                                        );
                                      },
                                      child: const Text('Choose Specialization'),
                                    ),
                                  ),
                                ],
                              ],
                            )
                          else if (!isSpecializationClass)
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final classId = classItem['id'] as int;

                                  final className =
                                      classItem['name']?.toString() ?? 'Class';

                                  final programName =
                                      program?['name']?.toString() ?? 'Program';

                                  final startDate =
                                  classItem['start_date']?.toString();

                                  final endDate =
                                  classItem['end_date']?.toString();

                                  final confirmed = await _confirmEnrollment(
                                    className,
                                    programName,
                                    startDate,
                                    endDate,
                                  );

                                  if (!confirmed) {
                                    return;
                                  }

                                  try {
                                    await enrollInClass(classId);
                                  } catch (e) {
                                    if (!mounted) return;

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          e.toString().replaceFirst(
                                            'Exception: ',
                                            '',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Enroll'),
                              ),
                            )
                          else
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: () {
                                  final classId = classItem['id'] as int;

                                  showSpecializationChoices(
                                    classId,
                                    null,
                                  );
                                },
                                child: const Text('Choose Specialization'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}