import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class FeatherCodeComponentBuilder implements ComponentBuilder {
  const FeatherCodeComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! ParagraphNode) {
      return null;
    }
    if (node.getMetadataValue('blockType') != codeAttribution) {
      return null;
    }

    final textDirection = getParagraphDirection(node.text.text);

    TextAlign textAlign = (textDirection == TextDirection.ltr) ? TextAlign.left : TextAlign.right;
    final textAlignName = node.getMetadataValue('textAlign');
    switch (textAlignName) {
      case 'left':
        textAlign = TextAlign.left;
        break;
      case 'center':
        textAlign = TextAlign.center;
        break;
      case 'right':
        textAlign = TextAlign.right;
        break;
      case 'justify':
        textAlign = TextAlign.justify;
        break;
    }

    return CodeBlockComponentViewModel(
      nodeId: node.id,
      text: node.text,
      textStyleBuilder: noStyleBuilder,
      backgroundColor: const Color(0x00000000),
      borderRadius: BorderRadius.zero,
      textDirection: textDirection,
      textAlignment: textAlign,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! CodeBlockComponentViewModel) {
      return null;
    }

    return CodeBlockComponent(
      textKey: componentContext.componentKey,
      text: componentViewModel.text,
      textAlign: componentViewModel.textAlignment,
      styleBuilder: componentViewModel.textStyleBuilder,
      backgroundColor: componentViewModel.backgroundColor,
      borderRadius: componentViewModel.borderRadius,
      textSelection: componentViewModel.selection,
      selectionColor: componentViewModel.selectionColor,
      highlightWhenEmpty: componentViewModel.highlightWhenEmpty,
      composingRegion: componentViewModel.composingRegion,
      showComposingUnderline: componentViewModel.showComposingUnderline,
    );
  }
}

class CodeBlockComponentViewModel extends SingleColumnLayoutComponentViewModel with TextComponentViewModel {
  CodeBlockComponentViewModel({
    required super.nodeId,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    required this.text,
    required this.textStyleBuilder,
    this.textDirection = TextDirection.ltr,
    this.textAlignment = TextAlign.left,
    required this.backgroundColor,
    required this.borderRadius,
    this.selection,
    required this.selectionColor,
    this.highlightWhenEmpty = false,
    this.composingRegion,
    this.showComposingUnderline = false,
  });

  @override
  AttributedText text;
  @override
  AttributionStyleBuilder textStyleBuilder;
  @override
  TextDirection textDirection;
  @override
  TextAlign textAlignment;
  @override
  TextSelection? selection;
  @override
  Color selectionColor;
  @override
  bool highlightWhenEmpty;
  @override
  TextRange? composingRegion;
  @override
  bool showComposingUnderline;

  Color backgroundColor;
  BorderRadius borderRadius;

  @override
  void applyStyles(Map<String, dynamic> styles) {
    super.applyStyles(styles);
    backgroundColor = styles[Styles.backgroundColor] ?? Colors.transparent;
    borderRadius = styles[Styles.borderRadius] ?? BorderRadius.zero;
  }

  @override
  CodeBlockComponentViewModel copy() {
    return CodeBlockComponentViewModel(
      nodeId: nodeId,
      maxWidth: maxWidth,
      padding: padding,
      text: text,
      textStyleBuilder: textStyleBuilder,
      textDirection: textDirection,
      textAlignment: textAlignment,
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
      selection: selection,
      selectionColor: selectionColor,
      highlightWhenEmpty: highlightWhenEmpty,
      composingRegion: composingRegion,
      showComposingUnderline: showComposingUnderline,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is BlockquoteComponentViewModel &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          text == other.text &&
          textDirection == other.textDirection &&
          textAlignment == other.textAlignment &&
          backgroundColor == other.backgroundColor &&
          borderRadius == other.borderRadius &&
          selection == other.selection &&
          selectionColor == other.selectionColor &&
          highlightWhenEmpty == other.highlightWhenEmpty &&
          composingRegion == other.composingRegion &&
          showComposingUnderline == other.showComposingUnderline;

  @override
  int get hashCode =>
      super.hashCode ^
      nodeId.hashCode ^
      text.hashCode ^
      textDirection.hashCode ^
      textAlignment.hashCode ^
      backgroundColor.hashCode ^
      borderRadius.hashCode ^
      selection.hashCode ^
      selectionColor.hashCode ^
      highlightWhenEmpty.hashCode ^
      composingRegion.hashCode ^
      showComposingUnderline.hashCode;
}

class CodeBlockComponent extends StatelessWidget {
  const CodeBlockComponent({
    super.key,
    required this.textKey,
    required this.text,
    this.textAlign = TextAlign.left,
    required this.styleBuilder,
    this.textSelection,
    this.selectionColor = Colors.lightBlueAccent,
    required this.backgroundColor,
    required this.borderRadius,
    this.highlightWhenEmpty = false,
    this.composingRegion,
    this.showComposingUnderline = false,
    this.showDebugPaint = false,
  });

  final GlobalKey textKey;
  final AttributedText text;
  final TextAlign textAlign;
  final AttributionStyleBuilder styleBuilder;
  final TextSelection? textSelection;
  final Color selectionColor;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final bool highlightWhenEmpty;
  final TextRange? composingRegion;
  final bool showComposingUnderline;
  final bool showDebugPaint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: const Color(0xFF222222),
        ),
        child: TextComponent(
          key: textKey,
          text: text,
          textAlign: textAlign,
          textStyleBuilder: styleBuilder,
          textSelection: textSelection,
          selectionColor: selectionColor,
          highlightWhenEmpty: highlightWhenEmpty,
          composingRegion: composingRegion,
          showComposingUnderline: showComposingUnderline,
          showDebugPaint: showDebugPaint,
        ),
      ),
    );
  }
}
