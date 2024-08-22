import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';


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

class ModuleInfo extends StatelessWidget {

  ModuleInfo({required this.moduleName, required this.moduleDescription});

  late Future<Modules> futureModule;
  late List<Modules> moduleData = [];
  final String moduleName;
  final String moduleDescription;


  // Get the Module Data
  // Future<List<Modules>> getModules() async {
  //   try {
  //     final response = await http.get(Uri.parse(
  //         'https://obrpqbo4eb.execute-api.us-west-2.amazonaws.com/api/modules'));
  //     if (response.statusCode == 200) {
  //       final data = jsonDecode(response.body);
  //       List<Modules> allModules = data.map<Modules>((e) => Modules.fromJson(e)).toList();
  //
  //       // Filter modules by the letter
  //       moduleData = allModules.where((module) => module.letters?.contains(letterId) ?? false).toList();
  //
  //       // change to lower case and Sort modules by name
  //       moduleData.sort((a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));
  //
  //       debugPrint("Module Data: ${moduleData.length}");
  //       return moduleData;
  //     } else {
  //       debugPrint("Failed to load modules");
  //     }
  //     return moduleData;
  //   } catch (e) {
  //     debugPrint("$e");
  //   }
  //   return moduleData;
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   //title: Text("title"),
      //   backgroundColor: Color(0xFFFFF0DC),
      //   elevation: 0,
      //
      // ),
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
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                      ),
                      child: Row(
                        //mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                            },
                            child: Row(
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/chevron_left.svg',
                                  height: 28,
                                  width: 28,
                                ),
                                const Text(
                                  "Back",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30,),
                    Text(
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0070C0),
                      ),
                      moduleName,

                    ),
                    const SizedBox(height: 20,),
                    Stack(
                      children: [
                        Container(
                          height: 600,
                          width: 400,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 50),
                              child: Column(
                                children: [
                                  Text(
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                    moduleDescription,
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
                          child: IgnorePointer(
                            child: Container(
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: [0.0, 1.0],
                                    colors: [
                                      // Colors.transparent,
                                      // Color(0xFFFFF0DC),
                                      //Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0),
                                      Color(0xFFFDD6A7).withOpacity(0.0),
                                      Color(0xFFFDD6A7),
                                    ],
                                  ),
                                )
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: GestureDetector(
                        onTap: () {
                          print("Download");
                        },
                        child: Container(
                          height: 60,
                          width: 228,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0070C0), Color(0xFF00C1FF), Color(0xFF0070C0),], // Your gradient colors
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                spreadRadius: 1,
                                blurRadius: 5,
                                offset: const Offset(1, 3), // changes position of shadow
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(left: 10),
                                  child: Text(
                                    "Download",
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10,),
                                SvgPicture.asset(
                                'assets/icons/download_icon.svg',
                                height: 42,
                                width: 42,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
              child: Container(
                color: Colors.transparent,
                height: 70,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    GestureDetector(
                      onTap: () => print("Home"),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home, size: 36, color: Colors.black),
                          Text("Home", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500))
                        ],
                      ),
                    ),
                    GestureDetector(
                        onTap: () => print("My Library"),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.library_books, size: 36, color: Colors.black),
                            Text("My Library", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500))
                          ],
                        ),
                      ),
                    GestureDetector(
                      onTap: () => print("Help"),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info, size: 36, color: Colors.black),
                          Text("Help", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500))
                        ],
                      ),
                    ),
                  ],
              )
            ),
          ),
        ]
      ),
    );
  }
}