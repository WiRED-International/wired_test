import 'package:flutter/material.dart';

class DialogUtils {
  static Future<bool> showExitExamDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit Exam?'),
        content: const Text('Your progress will be saved so you can continue later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}