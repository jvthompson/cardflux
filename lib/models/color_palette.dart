/// Preset ARGB swatches offered by every color prompt in this app -- board
/// widget colors (see `boardWidgetColorPalette` re-export in
/// `ui/widgets/counter_widget.dart`) and player colors (see
/// `PlayerInfo.color`, `HomeScreen`'s color picker, and
/// `HostServer`'s color-clash resolution). A small fixed palette rather than
/// a full color picker, since this app has no color-picker dependency and a
/// cosmetic color choice doesn't need an arbitrary RGB value. Lives under
/// `models/` (rather than `ui/widgets/`) so the networking layer
/// (`HostServer`) can reference it for clash resolution without importing UI
/// code.
const List<int> boardWidgetColorPalette = [
  0xFF455A64, // blueGrey (default background)
  0xFFFFFFFF, // white (default text)
  0xFF000000, // black
  0xFFD32F2F, // red
  0xFFF57C00, // orange
  0xFFFBC02D, // yellow
  0xFF388E3C, // green
  0xFF1976D2, // blue
  0xFF7B1FA2, // purple
  0xFF5D4037, // brown
  0xFF9E9E9E, // grey
  0xFFEC407A, // pink
];
