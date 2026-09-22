import 'package:flutter/material.dart';

/// Shown on [HomeScreen] when [UpdateChecker] finds a newer published build.
/// Mirrors the existing orange "message" banner in `home_screen.dart` (same
/// shape, same slot in the layout) but in blue, so the two read as visually
/// distinct: orange for "something went wrong", blue for "good news".
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.latestTag, required this.onTap});

  final String latestTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue),
        ),
        child: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Update available: $latestTag — tap to install', style: const TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }
}
