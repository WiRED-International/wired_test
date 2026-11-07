import 'package:flutter/material.dart';

class BrowseState extends StatelessWidget {
  const BrowseState.loading({super.key, this.indicatorColor})
      : icon = null,
        title = null,
        detail = null,
        onRetry = null;

  const BrowseState.message({
    super.key,
    required IconData this.icon,
    required String this.title,
    required String this.detail,
    this.onRetry,
  }) : indicatorColor = null;

  final Color? indicatorColor;
  final IconData? icon;
  final String? title;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return Center(
        child: CircularProgressIndicator(color: indicatorColor),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF358347), size: 48),
            const SizedBox(height: 14),
            Text(
              title!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Color(0xFF16466A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF607889)),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
