import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'module_by_alphabet.dart';

class ByAlphabet extends StatefulWidget {
  @override
  _ByAlphabetState createState() => _ByAlphabetState();
}

class Album {
  final String description;
  final String id;
  final String name;

  Album({
    required this.description,
    required this.id,
    required this.name
  });

  Album.fromJson(Map<String, dynamic> json)
      : description = json['description'] as String,
        id = json['id'] as String,
        name = json['name'] as String;

    Map<String, dynamic> toJson() => {
      'description': description,
      'id': id,
      'name': name,
    };
}

class _ByAlphabetState extends State<ByAlphabet> {
  late Future<List<Album>> futureAlbums;
  late List<Album> albums = [];

  Future<List<Album>> fetchAlbums() async {
    try {
      final response = await http.get(Uri.parse(
          'https://obrpqbo4eb.execute-api.us-west-2.amazonaws.com/api/letters'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        albums = data.map<Album>((e) => Album.fromJson(e)).toList();
        albums.sort((a, b) => a.name.compareTo(b.name));
        debugPrint("Album Data: ${albums.length}");
        return albums;
      } else {
        debugPrint("Failed to load albums");
      }
      return albums;
    } catch (e) {
      debugPrint("$e");
  }
  return albums;
}

  @override
  void initState() {
    super.initState();
    futureAlbums = fetchAlbums();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("By Alphabet"),
      ),
      body: Center(
        child: Column(
          children: [
            Text("Search by"),
            Text("Alphabet"),
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
              child: FutureBuilder<List<Album>>(
                future: futureAlbums,
                builder: (context, snapshot) {
                  print("THis is the snapshot ${snapshot.data}");
                  if (snapshot.hasData) {
                    //albums = snapshot.data!.map((album) => album.name).toList();
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 3,
                      ),
                      itemCount: albums.length,
                      itemBuilder: (context, index) {
                        return InkWell(
                          onTap: () {
                            print("Album index ${albums[index].name} was tapped");
                            print("Album index ${albums[index].id} was tapped");
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ModuleByAlphabet(letter: albums[index].name, letterId: albums[index].id)),
                            );
                          },
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              albums[index].name,
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ),
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
          ],
        ),
      ),
    );
  }
}