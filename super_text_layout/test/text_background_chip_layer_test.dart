import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_text_layout/super_text_layout.dart';

const _text = 'Call Inbox item to process';
const _style = TextBackgroundChipStyle(
  color: Color(0xFF00FF00),
  horizontalPadding: 3,
  verticalPadding: 0,
  radius: Radius.circular(5),
);

void main() {
  testWidgets('a chip that wraps leaves out the space at the line end when given the text', (tester) async {
    late TextLayout layout;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            child: SuperText(
              richText: const TextSpan(text: _text, style: TextStyle(fontSize: 20)),
              layerBeneathBuilder: (context, textLayout) {
                layout = textLayout;
                return TextBackgroundChipLayer(
                  textLayout: textLayout,
                  text: _text,
                  chips: const [TextBackgroundChipRange(range: TextRange(start: 5, end: _text.length), style: _style)],
                );
              },
            ),
          ),
        ),
      ),
    );

    List<TextBox> boxes(int start, int end) => layout.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
          boxHeightStyle: BoxHeightStyle.max,
        );
    final inbox = boxes(5, 10).first;
    final lineEndSpace = boxes(18, 19).single;
    final process = boxes(19, _text.length).single;
    expect(lineEndSpace.top, inbox.top, reason: 'the width must break the line after "to"');
    expect(process.top, greaterThan(inbox.top));
    RRect chip(double left, double right, TextBox line) => RRect.fromRectAndRadius(
          Rect.fromLTRB(left - 3, line.top, right + 3, line.bottom),
          const Radius.circular(5),
        );

    final layer = tester.renderObject<RenderBox>(
      find.descendant(of: find.byType(TextBackgroundChipLayer), matching: find.byType(CustomPaint)),
    );
    expect(
      layer,
      paints
        ..rrect(rrect: chip(inbox.left, lineEndSpace.left, inbox), color: _style.color)
        ..rrect(rrect: chip(process.left, process.right, process), color: _style.color),
    );
  });
}
