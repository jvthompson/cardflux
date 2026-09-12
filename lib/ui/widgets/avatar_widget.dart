import 'dart:io';

import 'package:flutter/material.dart';

/// A square avatar for the local player -- filled with their selected
/// [color] when no image is set (or the image fails to load), otherwise
/// showing the image at [imagePath] cropped to fill the square. The border
/// is always drawn in [color], even when an image is shown, so the avatar
/// reflects the player's color choice either way. Presentation only (no tap
/// handling) -- callers (the Home screen summary, the edit dialog's picker)
/// wrap this in their own `GestureDetector`/`InkWell` since each needs
/// different tap behavior. Mirrors `CardBackWidget`'s fixed-size,
/// graceful-image-fallback shape.
class AvatarWidget extends StatelessWidget {
  const AvatarWidget({super.key, required this.color, this.imagePath, this.size = 200});

  final int color;
  final String? imagePath;
  final double size;

  Widget _fallback() => Container(color: Color(color));

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(border: Border.all(color: Color(color), width: 4)),
      child: path == null
          ? _fallback()
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _fallback(),
            ),
    );
  }
}
