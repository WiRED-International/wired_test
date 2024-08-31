import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '.././utils/functions.dart';
import 'package:archive/archive_io.dart';
import '../utils/custom_app_bar.dart';
import '../utils/custom_nav_bar.dart';
import 'module_library.dart';
import 'module_info.dart';

class ModuleByAlphabet extends StatefulWidget {
  final String letter;
  final String letterId;

  ModuleByAlphabet({required this.letter, required this.letterId,});

  @override
  _ModuleByAlphabetState createState() => _ModuleByAlphabetState();
}

class Modules {
  String? name;
  String? description;
  //String? topics;
  //String? version;
  String? downloadLink;
  //String? launchFile;
  //String? packageSize;
  //String? letters;
  List<String>? letters;
  //String? credits;
  //String? module_name;
  //String? id;


  Modules({
    this.name,
    this.description,
    //this.topics,
    //this.version,
    this.downloadLink,
    //this.launchFile,
    //this.packageSize,
    this.letters,
    //this.credits,
    //this.module_name,
    //this.id,
  });

  Modules.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      description = json['description'] as String,
      //topics = json['topics'] as String,
      //version = json['version'] as String,
      downloadLink = json['downloadLink'] as String,
      //launchFile = json['launchFile'] as String,
      //packageSize = json['packageSize'] as String,
      //letters = json['letters'] as String;
      letters = (json['letters'] as List<dynamic>?)?.map((e) => e as String).toList();
      //credits = json['credits'] as String,
      //module_name = json['module_name'] as String,
      //id = json['id'] as String;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    //'topics': topics,
    //'version': version,
    'downloadLink': downloadLink,
    //'launchFile': launchFile,
    //'packageSize': packageSize,
    'letters': letters,
    //'credits': credits,
    //'module_name': module_name,
    //'id': id,
  };
}

class _ModuleByAlphabetState extends State<ModuleByAlphabet> {
  late Future<List<Modules>> futureModules;
  late List<Modules> moduleData = [];

  // Get the Module Data
  Future<List<Modules>> getModules() async {
    try {
      final response = await http.get(Uri.parse(
          'https://obrpqbo4eb.execute-api.us-west-2.amazonaws.com/api/modules'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Modules> allModules = data.map<Modules>((e) => Modules.fromJson(e)).toList();

        // Filter modules by the letter
        moduleData = allModules.where((module) => module.letters?.contains(widget.letterId) ?? false).toList();

        // change to lower case and Sort modules by name
        moduleData.sort((a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));

        debugPrint("Module Data: ${moduleData.length}");
        return moduleData;
      } else {
        debugPrint("Failed to load modules");
      }
      return moduleData;
    } catch (e) {
      debugPrint("$e");
    }
    return moduleData;
  }

  // Get Permissions
  Future<bool> checkAndRequestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  // Download the Module
  Future<void> downloadModule(String url, String fileName) async {
    bool hasPermission = await checkAndRequestStoragePermission();
    print("Has Permission: $hasPermission");
    if (true) {
      final directory = await getExternalStorageDirectory(); // Get the External Storage Directory (Android)
      final filePath = '${directory!.path}/$fileName';
      final file = File(filePath);

      try {
        final response = await http.get(Uri.parse(url));
        await file.writeAsBytes(response.bodyBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded $fileName')),
        );
        print('Directory: ${directory.path}');
        print('File Path: $filePath');

        // Unzip the downloaded file
        final bytes = file.readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        for (var file in archive) {
          final filename = file.name;
          final filePath = '${directory.path}/$filename';
          print('Processing file: $filename at path: $filePath');

          if (file.isFile) {
            final data = file.content as List<int>;
            File(filePath)
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          } else {
            Directory(filePath).createSync(recursive: true);
            print('Directory created: $filePath');
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unzipped $fileName')),
        );
        print('Unzipped to: ${directory.path}');

      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading $fileName')),
        );
      }
    } else {
      openAppSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permission denied')),
      );
    }
  }



  @override
  void initState() {
    super.initState();
    futureModules = getModules();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
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
            child: SafeArea(
          child: Center(
            child: Column(
              children: [
                //Imported from utils/custom_app_bar.dart
                CustomAppBar(
                  onBackPressed: () {
                    Navigator.pop(context);
                  },
                ),
                Container(
                  child: Column(
                    children: [
                      const Text(
                        "Search by",
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0070C0),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Alphabet: ",
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0070C0),
                            ),
                          ),
                          Text(
                            widget.letter,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF548235),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Stack(
                  children: [
                    Container(
                    height: 650,
                    width: 400,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                    ),
                    child: FutureBuilder<List<Modules>>(
                      future: futureModules,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return ListView.builder(
                            itemCount: moduleData.length + 1, // Increase the item count by 1 to account for the SizedBox as the last item
                            itemBuilder: (context, index) {
                              if (index == moduleData.length) {
                                // This is the last item (the SizedBox or Container)
                                return const SizedBox(
                                  height: 160,
                                );
                              }
                              final module = moduleData[index];
                              final moduleName = module.name ?? "Unknown Module";
                              final downloadLink = module.downloadLink ?? "No Link available";
                              final moduleDescription = module.description ?? "No Description available";
                              return Column(
                                children: [
                                  InkWell(
                                    onTap: () async {
                                      //print("Downloading ${moduleData[index].downloadLink}");
                                      if (moduleData[index].downloadLink != null) {
                                        // String fileName = "$moduleName.zip";
                                        // await downloadModule(downloadLink, fileName);
                                        Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleInfo(moduleName: moduleName, moduleDescription: moduleDescription, downloadLink: downloadLink)));
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('No download link found for ${moduleData[index].name}')),
                                        );
                                      }
                                    },
                                    child: Center(
                                      child: ListTile(
                                        title: Text(
                                          moduleData[index].name!,
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF0070C0),
                                          ),
                                          textAlign: TextAlign.center,
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
                        } else if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        } else {
                          return const CircularProgressIndicator();
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
            ),
          ),
        ),
      ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomBottomNavBar(
              onHomeTap: () {
                print("Home");
                //Navigator.push(context, MaterialPageRoute(builder: (context) => DownloadConfirm(moduleName: moduleName)));
              },
              onLibraryTap: () {
                print("My Library");
                Navigator.push(context, MaterialPageRoute(builder: (context) => ModuleLibrary()));
              },
              onHelpTap: () {
                print("Help");
                //Navigator.push(context, MaterialPageRoute(builder: (context) => Help()));
              },
            ),
          ),
    ],
      ),
    );
  }
}