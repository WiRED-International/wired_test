import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'functions.dart'; // uses your existing isTablet(context)

class DownloadSection extends StatelessWidget {
  final bool isLoading;
  final bool isDownloading;
  final double progress;
  final String progressText;
  final double baseSize;
  final String buttonLabel;
  final VoidCallback onPressed;

  const DownloadSection({
    super.key,
    required this.isLoading,
    required this.isDownloading,
    required this.progress,
    required this.progressText,
    required this.baseSize,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0), // adds safe breathing room
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🟢 Button
          GestureDetector(
            onTap: isLoading || isDownloading ? null : onPressed,
            child: Container(
              width: baseSize * (isTablet(context) ? 0.5 : 0.55),
              height: baseSize * (isTablet(context) ? 0.10 : 0.12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0070C0),
                    Color(0xFF00C1FF),
                    Color(0xFF0070C0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(35),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(1, 3),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    isLoading || isDownloading
                        ? const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    )
                        : Text(
                      buttonLabel,
                      style: TextStyle(
                        fontSize: baseSize * 0.071,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 7),
                    SvgPicture.asset(
                      'assets/icons/download_icon.svg',
                      height: baseSize * 0.0675,
                      width: baseSize * 0.0675,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 🟢 Fade-in progress bar — wrapped in Flexible
          if (isDownloading)
            Flexible(
              fit: FlexFit.loose, // ✅ prevents the overflow
              child: Padding(
                padding: const EdgeInsets.only(top: 12.0, bottom: 6.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(10),
                        backgroundColor: Colors.grey.shade300,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF22C55E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progressText,
                      style: TextStyle(
                        fontSize: baseSize * 0.04,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

