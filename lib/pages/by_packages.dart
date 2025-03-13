import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:wired_test/pages/package_info.dart';
import '../providers/auth_guard.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import '../utils/functions.dart';
import '../utils/side_nav_bar.dart';
import 'cme/cme_tracker.dart';
import 'home_page.dart';
import 'menu/guestMenu.dart';
import 'menu/menu.dart';
import 'module_library.dart';

class ByPackages extends StatefulWidget {
  @override
  _ByPackagesState createState() => _ByPackagesState();
}

class Package {
  int? id;
  String? name;
  String? description;
  String? downloadLink;


  Package({
    this.id,
    this.name,
    this.description,
    this.downloadLink,

  });

  Package.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int?,
        name = json['name'] as String?,
        description = json['description'] as String?,
        downloadLink = json['downloadLink'] as String;


  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'downloadLink': downloadLink,

  };

  // // Override == operator to compare Package objects by their package field
  // @override
  // bool operator ==(Object other) {
  //   if (identical(this, other)) return true;
  //
  //   return other is Package && other.package == package;
  // }
  //
  // // Override hashCode to ensure it is consistent with the == operator
  // @override
  // int get hashCode => package?.hashCode ?? 0;
}

class _ByPackagesState extends State<ByPackages> {
  late Future<List<Package>> futurePackages;

  Future<List<Package>> fetchPackages() async {
    final remoteServer = dotenv.env['REMOTE_SERVER']!;
    final localServer = dotenv.env['LOCAL_SERVER']!;
    final apiEndpoint = '/packages';

    try {
      final response = await http.get(Uri.parse('$remoteServer$apiEndpoint'));

      debugPrint("Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check what data is being decoded
        debugPrint("Fetched Data: $data");

        // Ensure that the data is a List
        if (data is List) {
          print("Data is a List");
          List<Package> packages = data.map<Package>((e) =>
              Package.fromJson(e)).toList();

          // // Filter out packages with null or empty names
          // packages = packages.where((p) => p.package != null &&
          //     p.package!.isNotEmpty).toList();

          // Sort the list by package name
          packages.sort((a, b) =>
              a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));

          // Remove duplicates by converting to a Set and back to a List
          packages = packages.toSet().toList();

          debugPrint("Parsed Packages Length: ${packages.length}");
          return packages;
        } else {
          debugPrint("Data is not a list");
        }
      } else {
        debugPrint(
            "Failed to load packages, status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching packages: $e");
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    futurePackages = fetchPackages();
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFF0DC),
                    Color(0xFFF9EBD9),
                    Color(0xFFFFC888),
                  ],
                ),
              ),
            ),
            Column(
              children: [
                // Custom AppBar
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                  requireAuth: false,
                ),
                // Expanded layout for the main content
                Expanded(
                  child: Row(
                    children: [
                      if (isLandscape)
                        CustomSideNavBar(
                          onHomeTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const MyHomePage()),
                            );
                          },
                          onLibraryTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ModuleLibrary()),
                            );
                          },
                          onTrackerTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AuthGuard(
                                  child: CMETracker(),
                                ),
                              ),
                            );
                          },
                          onMenuTap: () async {
                            bool isLoggedIn = await checkIfUserIsLoggedIn();
                            print("Navigating to menu. Logged in: $isLoggedIn");
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                              ),
                            );
                          },
                        ),

                      // Main content area (expanded to fill remaining space)
                      Expanded(
                        child: Center(
                          child: isLandscape
                              ? _buildLandscapeLayout(screenWidth, screenHeight)
                              : _buildPortraitLayout(screenWidth, screenHeight),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!isLandscape)
                  CustomBottomNavBar(
                    onHomeTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const MyHomePage()),
                      );
                    },
                    onLibraryTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ModuleLibrary()),
                      );
                    },
                    onTrackerTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AuthGuard(
                            child: CMETracker(),
                          ),
                        ),
                      );
                    },
                    onMenuTap: () async {
                      bool isLoggedIn = await checkIfUserIsLoggedIn();
                      print("Navigating to menu. Logged in: $isLoggedIn");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => isLoggedIn ? Menu() : GuestMenu(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(screenWidth, screenHeight) {
    return Column(
      children: [
        SizedBox(height: 10),
        Container(
          child: Column(
            children: [
              Text(
                "Search by Package",
                style: TextStyle(
                  fontSize: screenWidth * 0.085,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // List of packages container
        Stack(
          children: [
            Container(
              height: screenHeight * 0.65,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.transparent,
              ),
              child: FutureBuilder<List<Package>>(
                future: futurePackages,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  } else if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text('No packages available');
                  } else {
                    final packages = snapshot.data!;
                    debugPrint("Number of Packages: ${packages.length}");
                    return ListView.builder(
                      itemCount: packages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == packages.length) {
                          return const SizedBox(
                            height: 160,
                          );
                        }
                        final package = packages[index];
                        final packageId = package.id ?? 0;
                        final packageName = package.name ?? "Unknown Module";
                        final packageDescription = package.description ?? "Unknown Package";
                        final downloadLink = package.downloadLink ?? "Unknown Package";
                        return Column(
                          children: [
                            InkWell(
                              onTap: () async {
                                //print("Downloading ${moduleData[index].downloadLink}");
                                if (packageName.isNotEmpty && package.id != null) {
                                  Navigator.push(context, MaterialPageRoute(
                                      builder: (context) => PackageInfo(
                                        packageId: packageId,
                                        packageName: packageName,
                                        packageDescription: packageDescription,
                                        downloadLink: downloadLink,
                                      )));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(
                                        'No package found for ${packages[index]
                                            .name}')),
                                  );
                                }
                              },
                              child: Center(
                                child: ListTile(
                                  title: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 10, bottom: 10),
                                    child: Text(
                                      packageName,
                                      style: TextStyle(
                                        fontSize: screenWidth * 0.074,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF0070C0),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const Divider(
                              color: Colors.grey,
                              height: 1,
                            ),
                          ],
                        );
                      },
                    );
                  }
                },
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 1.0],
                        colors: [
                          // Colors.transparent,
                          // Color(0xFFFFF0DC),
                          //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                          Color(0xFFFED09A).withOpacity(0.0),
                          Color(0xFFFED09A),
                        ],
                      ),
                    )
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(screenWidth, screenHeight) {
    var baseSize = MediaQuery.of(context).size.shortestSide;
    return Column(
      children: [
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.03 : 0.03),
        ),
        Container(
          child: Column(
            children: [
              Text(
                "Search by Package",
                style: TextStyle(
                  fontSize: baseSize * (isTablet(context) ? 0.07 : 0.07),
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF548235),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: baseSize * (isTablet(context) ? 0.015 : 0.015),
        ),
        // List of packages container
        Stack(
          children: [
            Container(
              height: baseSize * (isTablet(context) ? 0.68 : 0.68),
              width: baseSize * (isTablet(context) ? 1.25 : 1.0),
              decoration: BoxDecoration(
                color: Colors.transparent,
              ),
              child: FutureBuilder<List<Package>>(
                future: futurePackages,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  } else if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text('No packages available');
                  } else {
                    final packages = snapshot.data!;
                    debugPrint("Number of Packages: ${packages.length}");
                    return ListView.builder(
                      itemCount: packages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == packages.length) {
                          return const SizedBox(
                            height: 160,
                          );
                        }
                        final package = packages[index];
                        final packageId = package.id ?? 0;
                        final packageName = package.name ?? "Unknown Module";
                        final packageDescription = package.description ?? "Unknown Package";
                        final downloadLink = package.downloadLink ?? "Unknown Package";
                        return Column(
                          children: [
                            InkWell(
                              onTap: () async {
                                //print("Downloading ${moduleData[index].downloadLink}");
                                if (packageName.isNotEmpty && package.id != null) {
                                  Navigator.push(context, MaterialPageRoute(
                                      builder: (context) => PackageInfo(
                                        packageId: packageId,
                                        packageName: packageName,
                                        packageDescription: packageDescription,
                                        downloadLink: downloadLink,)));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(
                                        'No package found for ${packages[index]
                                            .name}')),
                                  );
                                }
                              },
                              child: Center(
                                child: ListTile(
                                  title: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 10, bottom: 10),
                                    child: Text(
                                      packageName,
                                      style: TextStyle(
                                        fontSize: baseSize * (isTablet(context) ? 0.0667 : 0.0667),
                                        fontFamilyFallback: [
                                          'NotoSans',
                                          'NotoSerif',
                                          'Roboto',
                                          'sans-serif'
                                        ],
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF0070C0),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              height: 1,
                              width: 500,
                              color: Colors.grey,
                            ),
                          ],
                        );
                      },
                    );
                  }
                },
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 1.0],
                        colors: [
                          // Colors.transparent,
                          // Color(0xFFFFF0DC),
                          //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                          Color(0xFFFED09A).withOpacity(0.0),
                          Color(0xFFFED09A),
                        ],
                      ),
                    )
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}