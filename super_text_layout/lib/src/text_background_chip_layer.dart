import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

import 'text_layout.dart';

/// A [SuperText] layer that paints filled rounded-rectangle "chip" backgrounds
/// behind the text within given ranges.
///
/// Use this as a [layerBeneathBuilder] child to render background highlights
/// (e.g. inline code chips) beneath text without affecting glyph metrics.
class TextBackgroundChipLayer extends StatefulWidget {
  const TextBackgroundChipLayer({
    Key? key,
    required this.textLayout,
    required this.chips,
    this.text,
  }) : super(key: key);

  final TextLayout textLayout;
  final List<TextBackgroundChipRange> chips;

  /// The laid-out text, placeholders included. When given, a chip that wraps
  /// leaves out the space at the line end, which the layout otherwise returns
  /// as part of the last word's boxes.
  final String? text;

  @override
  State<TextBackgroundChipLayer> createState() => _TextBackgroundChipLayerState();
}

// No TickerProviderStateMixin — this widget has no animations intentionally.
class _TextBackgroundChipLayerState extends State<TextBackgroundChipLayer> {
  @override
  Widget build(BuildContext context) {
    if (widget.chips.isEmpty) {
      return const SizedBox();
    }

    final boxesPerChip = [
      for (final chip in widget.chips)
        (
          style: chip.style,
          boxes: _chipBoxes(chip.range),
        ),
    ];

    return CustomPaint(
      size: Size.infinite,
      painter: _TextBackgroundChipPainter(boxesPerChip),
    );
  }

  List<TextBox> _boxes(int start, int end) => widget.textLayout.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
        boxHeightStyle: BoxHeightStyle.max,
      );

  /// One box per line the range covers, built from its words.
  List<TextBox> _chipBoxes(TextRange range) {
    final text = widget.text;
    if (text == null || range.end > text.length) {
      return _boxes(range.start, range.end);
    }
    final lines = <double, TextBox>{};
    for (final word in RegExp(r'\S+').allMatches(range.textInside(text))) {
      final end = range.start + word.end;
      final spaceAfter = RegExp(r'\s+').matchAsPrefix(text, end);
      final spaceBoxes = spaceAfter == null ? const <TextBox>[] : _boxes(end, spaceAfter.end);
      for (final box in _boxes(range.start + word.start, end)) {
        if (spaceBoxes.any((space) => space.left == box.left && space.top == box.top)) continue;
        lines.update(
          box.top.roundToDouble(),
          (line) => TextBox.fromLTRBD(
            min(line.left, box.left),
            min(line.top, box.top),
            max(line.right, box.right),
            max(line.bottom, box.bottom),
            line.direction,
          ),
          ifAbsent: () => box,
        );
      }
    }
    return lines.values.toList();
  }
}

/// A range of text that should be painted with a background chip style.
class TextBackgroundChipRange {
  const TextBackgroundChipRange({
    required this.range,
    required this.style,
  });

  final TextRange range;
  final TextBackgroundChipStyle style;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextBackgroundChipRange &&
          runtimeType == other.runtimeType &&
          range == other.range &&
          style == other.style;

  @override
  int get hashCode => range.hashCode ^ style.hashCode;
}

/// Visual style for a background chip drawn behind a text range.
class TextBackgroundChipStyle {
  const TextBackgroundChipStyle({
    required this.color,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.radius,
  });

  final Color color;
  final double horizontalPadding;
  final double verticalPadding;
  final Radius radius;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextBackgroundChipStyle &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          horizontalPadding == other.horizontalPadding &&
          verticalPadding == other.verticalPadding &&
          radius == other.radius;

  @override
  int get hashCode =>
      color.hashCode ^ horizontalPadding.hashCode ^ verticalPadding.hashCode ^ radius.hashCode;
}

class _TextBackgroundChipPainter extends CustomPainter {
  const _TextBackgroundChipPainter(this.boxesPerChip);

  final List<({TextBackgroundChipStyle style, List<TextBox> boxes})> boxesPerChip;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in boxesPerChip) {
      final style = entry.style;
      // Hoist a single Paint outside the per-box loop to avoid allocations.
      final paint = Paint()..color = style.color;
      for (final box in entry.boxes) {
        final rect = Rect.fromLTRB(
          box.left - style.horizontalPadding,
          box.top - style.verticalPadding,
          box.right + style.horizontalPadding,
          box.bottom + style.verticalPadding,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(rect, style.radius), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TextBackgroundChipPainter oldDelegate) {
    if (boxesPerChip.length != oldDelegate.boxesPerChip.length) return true;
    const listEq = ListEquality<TextBox>();
    for (var i = 0; i < boxesPerChip.length; i++) {
      final a = boxesPerChip[i];
      final b = oldDelegate.boxesPerChip[i];
      if (a.style != b.style) return true;
      // Dart record == compares fields positionally, but the `boxes` field is
      // a List whose == is identity. Recompare deeply with ListEquality.
      if (!listEq.equals(a.boxes, b.boxes)) return true;
    }
    return false;
  }
}
