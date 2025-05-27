import 'package:flutter/material.dart';

class EmailSuccessScreen extends StatelessWidget {
  final String email;

  const EmailSuccessScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Success")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 72),
              SizedBox(height: 20),
              Text(
                "Email successfully sent to:",
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                email,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 30),
              ElevatedButton.icon(
                icon: Icon(Icons.home),
                label: Text("Return to Home"),
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
