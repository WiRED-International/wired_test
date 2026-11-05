import 'package:flutter/material.dart';

import '../../models/cme_credit_totals.dart';

/// Confirmed balances only; quiz attempts never determine earned credits.
class CmeTotalsCard extends StatelessWidget {
  const CmeTotalsCard({super.key, required this.totals});

  final CmeCreditTotals totals;

  @override
  Widget build(BuildContext context) {
    final earned = totals.currentYear.earnedCredits;
    final requirement = totals.annualRequirement;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${totals.currentYear.year ?? "Current year"} Progress'),
            const SizedBox(height: 8),
            Text(earned == null
                ? 'Credits unavailable'
                : '$earned credits earned'),
            Text(requirement == null
                ? 'Annual requirement unavailable'
                : 'Annual requirement: $requirement credits'),
            if (earned != null && requirement != null && requirement > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (earned / requirement).clamp(0.0, 1.0),
                backgroundColor: Colors.white24,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
