import 'package:flutter/material.dart';

class ModuleBrowseCard extends StatelessWidget {
  final String title;
  final String? redirectFrom;
  final VoidCallback onTap;

  const ModuleBrowseCard({
    super.key,
    required this.title,
    this.redirectFrom,
    required this.onTap,
  });

  static const _blue = Color(0xFF16466A);
  static const _green = Color(0xFF358347);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFD7E4EA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.menu_book_outlined, color: _green),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (redirectFrom != null) ...[
                      Text(
                        '$redirectFrom · See also',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _green,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      title,
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF0876D6)),
            ],
          ),
        ),
      ),
    );
  }
}
