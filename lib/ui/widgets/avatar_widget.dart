import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A square avatar -- filled with the player's selected [color] when no
/// image is available (or the image fails to load), otherwise showing the
/// image cropped to fill the square. [imageBytes] (a remote player's avatar,
/// received over the network -- see `HostServer`/`GameClient`) takes
/// priority over [imagePath] (a local file, used for the local player's own
/// avatar on the Home screen/edit dialog/table) when both are somehow set.
/// The border is always drawn in [color], even when an image is shown, so
/// the avatar reflects the player's color choice either way. Presentation
/// only (no tap handling) -- callers (the Home screen summary, the edit
/// dialog's picker) wrap this in their own `GestureDetector`/`InkWell` since
/// each needs different tap behavior. Mirrors `CardBackWidget`'s fixed-size,
/// graceful-image-fallback shape.
class AvatarWidget extends StatelessWidget {
  const AvatarWidget({super.key, required this.color, this.imagePath, this.imageBytes, this.size = 200});

  final int color;
  final String? imagePath;
  final Uint8List? imageBytes;
  final double size;

  Widget _fallback() => Container(color: Color(color));

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    final path = imagePath;
    final Widget content;
    if (bytes != null) {
      content = Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => _fallback());
    } else if (path != null) {
      content = Image.file(File(path), fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => _fallback());
    } else {
      content = _fallback();
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(border: Border.all(color: Color(color), width: 4)),
      child: content,
    );
  }
}
