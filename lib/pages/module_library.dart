import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_svg/svg.dart';
import 'package:path_provider/path_provider.dart';
import '.././utils/webview_screen.dart';


class ModuleLibrary extends StatefulWidget {

  @override
  _ModuleLibraryState createState() => _ModuleLibraryState();
}

class ModuleFile {
  final FileSystemEntity file;
  final String path;


  ModuleFile({required this.file, required this.path});
}

class _ModuleLibraryState extends State<ModuleLibrary> {
  late Future<List<ModuleFile>> futureModules;

  @override
  void initState() {
    super.initState();
    futureModules = _fetchModules();
  }

  Future<List<ModuleFile>> _fetchModules() async {
    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      // Get all files from the directory
      return directory
          .listSync()
          .whereType<File>()
          .map((file) => ModuleFile(file: file, path: file.path))
          .toList();
    } else {
      return [];
    }
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
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                    ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                            },
                            child: Row(
                              children: [
                                SvgPicture.asset(
                                  "assets/icons/chevron_left.svg",
                                  width: 28,
                                  height: 28,
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
                  const Text(
                    "My Library",
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0070C0),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20,),
                  Container(
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 75,
                            color: Colors.white,
                            child: Center(
                              child: Text(
                                "Modules",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                ),
                              ),
                            )
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 75,
                          color: Colors.black,
                        ),
                        Expanded(
                          child: Container(
                            height: 75,
                            color: Colors.white,
                            child: Center(
                              child: Text(
                                "Resources",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                ),
                              ),
                            )
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Container(
                        height: 550,
                      child: FutureBuilder<List<ModuleFile>>(
                        future: futureModules,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          } else if (snapshot.hasError) {
                            return const Center(child: Text('Error loading modules'));
                          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(child: Text('No modules found'));
                          } else {
                            return ListView.builder(
                              itemCount: snapshot.data!.length,
                              itemBuilder: (context, index) {
                                final moduleFile = snapshot.data![index];
                                return Container(
                                    decoration: const BoxDecoration(
                                        color: Colors.transparent,
                                        border: Border(
                                          top: BorderSide(
                                            color: Colors.black,
                                            width: 1,
                                          ),
                                        )
                                    ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 20, bottom: 20, right: 0, left: 0),
                                    child: ListTile(
                                      title: Text(
                                          moduleFile.file.path.split('/').last,
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                          )
                                      ),
                                      //leading: const Icon(Icons.insert_drive_file),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                              height: 69,
                                              width: 69,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  colors: [
                                                    Color(0xFF87C9F8),
                                                    Color(0xFF70E1F5),
                                                  ],
                                                ),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: GestureDetector(
                                                onTap: () {
                                                  // Play the module
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                        builder: (context) => WebViewScreen(
                                                              urlRequest: URLRequest(
                                                                url: Uri.file(moduleFile.path),
                                                              ),
                                                            )
                                                        ),
                                                  );
                                                  // WebViewScreen();
                                                },
                                                child: const Column(
                                                  children: [
                                                    Icon(
                                                        Icons.play_arrow,
                                                        color: Color(0xFF545454),
                                                        size: 26,
                                                    ),
                                                    Text(
                                                      "Play",
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w500,
                                                        color: Color(0xFF545454),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            ),
                                          ),
                                          const SizedBox(width: 10,),
                                          Flexible(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                                height: 69,
                                                width: 69,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  colors: [
                                                    Color(0xFF70E1F5),
                                                    Color(0xFF86A8E7),
                                                  ],
                                                ),
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: GestureDetector(
                                                onTap: () {
                                                  // Handle file tap here if needed
                                                },
                                                child: const Column(
                                                  children: [
                                                    Icon(
                                                        Icons.delete,
                                                        color: Color(0xFF545454),
                                                        size: 26,
                                                    ),
                                                    Text(
                                                      "Delete",
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w500,
                                                        color: Color(0xFF545454),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            ),
                                          ),
                                        ]
                                      ),
                                    ),
                                  ),
                                );
                              }
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}