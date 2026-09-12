import 'dart:typed_data';
import 'dart:ui' as ui;

/// Cap for an avatar's larger dimension after [resizeAvatarBytes]. This
/// app's largest avatar use is 200x200 (Home screen/edit dialog); 256 keeps
/// meaningful sharpness on a HiDPI display's 200x200 box while re-encoding
/// small enough to fit into `hello`/`lobbyRosterUpdate` network payloads
/// without noticeably delaying the lobby.
const int avatarMaxDimension = 256;

/// Decodes [sourceBytes] (jpg/png/webp/etc -- `dart:ui`'s codec sniffs the
/// format itself), downscales so the larger dimension is at most
/// [avatarMaxDimension] (never upscales a smaller source), and re-encodes as
/// PNG. Pure `dart:ui`, no image-processing package dependency.
Future<Uint8List> resizeAvatarBytes(Uint8List sourceBytes) async {
  final codec = await ui.instantiateImageCodec(sourceBytes);
  final frame = await codec.getNextFrame();
  final original = frame.image;
  final largerDimension = original.width > original.height ? original.width : original.height;
  final scale = avatarMaxDimension / largerDimension;
  if (scale >= 1.0) {
    final data = await original.toByteData(format: ui.ImageByteFormat.png);
    original.dispose();
    return data!.buffer.asUint8List();
  }
  final targetWidth = (original.width * scale).round();
  final targetHeight = (original.height * scale).round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    original,
    ui.Rect.fromLTWH(0, 0, original.width.toDouble(), original.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final resized = await recorder.endRecording().toImage(targetWidth, targetHeight);
  final data = await resized.toByteData(format: ui.ImageByteFormat.png);
  original.dispose();
  resized.dispose();
  return data!.buffer.asUint8List();
}
