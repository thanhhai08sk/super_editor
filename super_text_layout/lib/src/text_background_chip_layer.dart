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
  }) : super(key: key);

  final TextLayout textLayout;
  final List<TextBackgroundChipRange> chips;

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
          boxes: widget.textLayout.getBoxesForSelection(
            TextSelection(baseOffset: chip.range.start, extentOffset: chip.range.end),
            boxHeightStyle: BoxHeightStyle.max,
          ),
        ),
    ];

    return CustomPaint(
      size: Size.infinite,
      painter: _TextBackgroundChipPainter(boxesPerChip),
    );
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
    return !const DeepCollectionEquality().equals(boxesPerChip, oldDelegate.boxesPerChip);
  }
}
