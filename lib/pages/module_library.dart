import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ModuleLibrary extends StatefulWidget {
  final String moduleName;

  ModuleLibrary({required this.moduleName});

  @override
  _ModuleLibraryState createState() => _ModuleLibraryState();
}

class _ModuleLibraryState extends State<ModuleLibrary> {
  final directory = getExternalStorageDirectory();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Module Library"),
      ),
      body: Center(
        child: Column(
          children: [
            Text("Module Library"),
            Container(
              height: 400,
              width: 400,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.blue,
                  width: 2,
                ),
              ),
              //child: Text(widget.moduleName),
            ),
          ],
        ),
      ),
    );
  }
}