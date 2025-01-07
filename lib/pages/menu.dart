import 'package:flutter/material.dart';
import 'package:wired_test/pages/home_page.dart';
import 'package:wired_test/pages/policy.dart';


class Menu extends StatefulWidget {
  @override
  _MenuState createState() => _MenuState();
}

class _MenuState extends State<Menu> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Wired Test'),
      ),
      body: ListView(
        children: <Widget>[
          ListTile(
            title: Text('Home'),
            onTap: () {
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(builder: (context) => Home()),
              // );
            },
          ),
          ListTile(
            title: Text('Login'),
            onTap: () {
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(builder: (context) => Login()),
              // );
            },
          ),
          ListTile(
            title: Text('Privacy Policy'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Policy()),
              );
            },
          ),
        ],
      ),
    );
  }
}