import 'package:flutter/material.dart';

import 'by_alphabet.dart';

class Search extends StatefulWidget {
  @override
  _SearchState createState() => _SearchState();
}

class _SearchState extends State<Search> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiRED International'),
      ),
      body: Center(
        child: Column(
          children: [
            const Hero(
              tag: 'search',
              child: Text(
                  'Search',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                print('Alphabet button pressed');
                Navigator.push(context, MaterialPageRoute(builder: (context) => ByAlphabet()));
              },
              child: const Text(
                'By Alphabet',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                print('Topic button pressed');
                //Navigator.push(context, MaterialPageRoute(builder: (context) => Search()));
              },
              child: const Text(
                'By Topic',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}