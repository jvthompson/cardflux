import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' hide colorFromHex;

import '../../models/color_palette.dart';
import 'color_swatch_row.dart';

/// The preset [ColorSwatchRow] plus a hex text field and a color-preview
/// button that opens a full [ColorPicker] dialog for an arbitrary RGB value
/// -- the one widget every color prompt in this app uses (Home Screen player
/// color, Counter/Token widget colors, Zones tab starting colors) so preset
/// swatches, hex entry, and a full picker all stay in sync everywhere.
class ColorPickerField extends StatefulWidget {
  const ColorPickerField({super.key, required this.selected, required this.onChanged, this.hexLabel = 'Hex'});

  final int selected;
  final ValueChanged<int> onChanged;

  /// Label for the hex [TextField], e.g. `'Hex'` or `'Starting Color (hex)'`
  /// -- lets call sites keep their own field naming without this widget
  /// rendering a redundant heading above the preset row.
  final String hexLabel;

  @override
  State<ColorPickerField> createState() => _ColorPickerFieldState();
}

class _ColorPickerFieldState extends State<ColorPickerField> {
  late final TextEditingController _hexController = TextEditingController(text: hexFromColor(widget.selected));

  @override
  void didUpdateWidget(covariant ColorPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the field in sync when the color changes from outside typing in
    // it (a preset tap, or the full picker dialog below) -- but never
    // clobber the text the user is mid-typing with its own re-parsed form.
    final newHex = hexFromColor(widget.selected);
    if (oldWidget.selected != widget.selected && _hexController.text != newHex) {
      _hexController.text = newHex;
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Future<void> _openFullPicker() async {
    Color picked = Color(widget.selected);
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(picked), child: const Text('Select')),
        ],
      ),
    );
    if (result == null) return;
    final argb = 0xFF000000 | (result.toARGB32() & 0xFFFFFF);
    widget.onChanged(argb);
    setState(() => _hexController.text = hexFromColor(argb));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ColorSwatchRow(selected: widget.selected, onSelected: widget.onChanged),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hexController,
                decoration: InputDecoration(
                  labelText: widget.hexLabel,
                  prefixText: '#',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => widget.onChanged(colorFromHex(v, widget.selected)),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _openFullPicker,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(widget.selected),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                ),
                child: Icon(
                  Icons.colorize,
                  size: 18,
                  color: Color(widget.selected).computeLuminance() > 0.5 ? Colors.black : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
