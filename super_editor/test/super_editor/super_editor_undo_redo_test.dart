import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';
import 'package:super_editor_markdown/super_editor_markdown.dart';

import 'supereditor_test_tools.dart';

void main() {
  group("Super Editor > undo redo >", () {
    group("text insertion >", () {
      testWidgets("insert a word", (tester) async {
        final document = deserializeMarkdownToDocument("Hello  world");
        final composer = MutableDocumentComposer();
        final editor = createDefaultDocumentEditor(document: document, composer: composer);
        final paragraphId = document.nodes.first.id;

        editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: paragraphId,
                nodePosition: const TextNodePosition(offset: 6),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          )
        ]);

        editor.execute([
          InsertTextRequest(
            documentPosition: DocumentPosition(
              nodeId: paragraphId,
              nodePosition: const TextNodePosition(offset: 6),
            ),
            textToInsert: "another",
            attributions: {},
          ),
        ]);

        expect(serializeDocumentToMarkdown(document), "Hello another world");
        expect(
          composer.selection,
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: paragraphId,
              nodePosition: const TextNodePosition(offset: 13),
            ),
          ),
        );

        // Undo the event.
        editor.undo();

        expect(serializeDocumentToMarkdown(document), "Hello  world");
        expect(
          composer.selection,
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: paragraphId,
              nodePosition: const TextNodePosition(offset: 6),
            ),
          ),
        );

        // Redo the event.
        editor.redo();

        expect(serializeDocumentToMarkdown(document), "Hello another world");
        expect(
          composer.selection,
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: paragraphId,
              nodePosition: const TextNodePosition(offset: 13),
            ),
          ),
        );
      });

      testWidgetsOnMac("type by character", (tester) async {
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .pump();

        await tester.placeCaretInParagraph("1", 0);

        // Type characters.
        await tester.typeImeText("Hello");

        expect(SuperEditorInspector.findTextInComponent("1").text, "Hello");
        expect(
          SuperEditorInspector.findDocumentSelection(),
          const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: "1",
              nodePosition: TextNodePosition(offset: 5),
            ),
          ),
        );

        // --- Undo character insertions ---
        await tester.pressCmdZ(tester);
        _expectDocumentWithCaret("Hell", "1", 4);

        await tester.pressCmdZ(tester);
        _expectDocumentWithCaret("Hel", "1", 3);

        await tester.pressCmdZ(tester);
        _expectDocumentWithCaret("He", "1", 2);

        await tester.pressCmdZ(tester);
        _expectDocumentWithCaret("H", "1", 1);

        await tester.pressCmdZ(tester);
        _expectDocumentWithCaret("", "1", 0);

        //----- Redo Changes ----
        await tester.pressCmdShiftZ(tester);
        _expectDocumentWithCaret("H", "1", 1);

        await tester.pressCmdShiftZ(tester);
        _expectDocumentWithCaret("He", "1", 2);

        await tester.pressCmdShiftZ(tester);
        _expectDocumentWithCaret("Hel", "1", 3);

        await tester.pressCmdShiftZ(tester);
        _expectDocumentWithCaret("Hell", "1", 4);

        await tester.pressCmdShiftZ(tester);
        _expectDocumentWithCaret("Hello", "1", 5);
      });
    });

    group("content conversions >", () {
      testWidgetsOnMac("paragraph to header", (tester) async {
        final editContext = await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .pump();

        await tester.placeCaretInParagraph("1", 0);

        // Type text that causes a conversion to a header node.
        await tester.typeImeText("# ");

        // Ensure that the paragraph is now a header.
        final document = editContext.document;
        var paragraph = document.nodes.first as ParagraphNode;
        expect(paragraph.metadata['blockType'], header1Attribution);
        expect(SuperEditorInspector.findTextInComponent(document.nodes.first.id).text, "");

        await tester.pressCmdZ(tester);
        await tester.pump();

        // Ensure that the header attribution is gone.
        paragraph = document.nodes.first as ParagraphNode;
        expect(paragraph.metadata['blockType'], paragraphAttribution);
        expect(SuperEditorInspector.findTextInComponent(document.nodes.first.id).text, "# ");
      });

      testWidgetsOnMac("dashes to em dash", (tester) async {
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .pump();

        await tester.placeCaretInParagraph("1", 0);

        // Type text that causes a conversion to an "em" dash.
        await tester.typeImeText("--");

        // Ensure that the double dashes are now an "em" dash.
        expect(SuperEditorInspector.findTextInComponent("1").text, "—");

        await tester.pressCmdZ(tester);
        await tester.pump();

        // Ensure that the em dash was reverted to the regular dashes.
        expect(SuperEditorInspector.findTextInComponent("1").text, "--");

        // Continue typing.
        await tester.typeImeText(" ");

        // Ensure that the dashes weren't reconverted into an em dash.
        expect(SuperEditorInspector.findTextInComponent("1").text, "-- ");
      });

      testWidgetsOnMac("paragraph to list item", (tester) async {
        final editContext = await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .pump();

        await tester.placeCaretInParagraph("1", 0);

        // Type text that causes a conversion to a list item node.
        await tester.typeImeText("1. ");

        // Ensure that the paragraph is now a list item.
        final document = editContext.document;
        var node = document.nodes.first as TextNode;
        expect(node, isA<ListItemNode>());
        expect(SuperEditorInspector.findTextInComponent(document.nodes.first.id).text, "");

        await tester.pressCmdZ(tester);
        await tester.pump();

        // Ensure that the node is back to a paragraph.
        node = document.nodes.first as TextNode;
        expect(node, isA<ParagraphNode>());
        expect(SuperEditorInspector.findTextInComponent(document.nodes.first.id).text, "1. ");
      });

      testWidgetsOnMac("url to a link", (tester) async {
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .pump();

        await tester.placeCaretInParagraph("1", 0);

        // Type text that causes a conversion to a link.
        await tester.typeImeText("google.com ");

        // Ensure that the URL is now linkified.
        expect(
          SuperEditorInspector.findTextInComponent("1").getAttributionSpansByFilter((a) => a is LinkAttribution),
          {
            const AttributionSpan(
              attribution: LinkAttribution("https://google.com"),
              start: 0,
              end: 9,
            ),
          },
        );

        await tester.pressCmdZ(tester);
        await tester.pump();

        // Ensure that the URL is no longer linkified.
        expect(
          SuperEditorInspector.findTextInComponent("1").getAttributionSpansByFilter((a) => a is LinkAttribution),
          const <AttributionSpan>{},
        );
      });

      testWidgetsOnMac("paragraph to horizontal rule", (tester) async {
        final editContext = await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .pump();

        await tester.placeCaretInParagraph("1", 0);

        await tester.typeImeText("--- ");
        expect(editContext.document.nodes.first, isA<HorizontalRuleNode>());

        await tester.pressCmdZ(tester);
        await tester.pump();

        expect(editContext.document.nodes.first, isA<ParagraphNode>());
        expect(SuperEditorInspector.findTextInComponent(editContext.document.nodes.first.id).text, "—- ");
      });
    });

    testWidgetsOnMac("pasted content", (tester) async {
      final editContext = await tester //
          .createDocument()
          .withSingleEmptyParagraph()
          .pump();

      await tester.placeCaretInParagraph("1", 0);

      // Paste multiple nodes of content.
      tester.simulateClipboard();
      await tester.setSimulatedClipboardContent('''
This is paragraph 1
This is paragraph 2
This is paragraph 3''');
      await tester.pressCmdV();

      // Ensure the pasted content was applied as expected.
      final document = editContext.document;
      expect(document.nodes.length, 3);
      expect(SuperEditorInspector.findTextInComponent(document.nodes[0].id).text, "This is paragraph 1");
      expect(SuperEditorInspector.findTextInComponent(document.nodes[1].id).text, "This is paragraph 2");
      expect(SuperEditorInspector.findTextInComponent(document.nodes[2].id).text, "This is paragraph 3");

      // Undo the paste.
      await tester.pressCmdZ(tester);
      await tester.pump();

      // Ensure we're back to a single empty paragraph.
      expect(document.nodes.length, 1);
      expect(SuperEditorInspector.findTextInComponent(document.nodes[0].id).text, "");

      // Redo the paste
      // TODO: remove WidgetTester as required argument to this robot method
      await tester.pressCmdShiftZ(tester);
      await tester.pump();

      // Ensure the pasted content was applied as expected.
      expect(document.nodes.length, 3);
      expect(SuperEditorInspector.findTextInComponent(document.nodes[0].id).text, "This is paragraph 1");
      expect(SuperEditorInspector.findTextInComponent(document.nodes[1].id).text, "This is paragraph 2");
      expect(SuperEditorInspector.findTextInComponent(document.nodes[2].id).text, "This is paragraph 3");
    });

    group("transaction grouping >", () {
      group("text merging >", () {
        testWidgetsOnMac("merges rapidly inserted text", (tester) async {
          await tester //
              .createDocument()
              .withSingleEmptyParagraph()
              .withHistoryGroupingPolicy(const MergeRapidTextInputPolicy())
              .pump();

          await tester.placeCaretInParagraph("1", 0);

          // Type characters quickly.
          await tester.typeImeText("Hello");

          // Ensure our typed text exists.
          expect(SuperEditorInspector.findTextInComponent("1").text, "Hello");

          // Undo the typing.
          await tester.pressCmdZ(tester);
          await tester.pump();

          // Ensure that the whole word was undone.
          expect(SuperEditorInspector.findTextInComponent("1").text, "");
        });

        testWidgetsOnMac("separates text typed later", (tester) async {
          await tester //
              .createDocument()
              .withSingleEmptyParagraph()
              .withHistoryGroupingPolicy(const MergeRapidTextInputPolicy())
              .pump();

          await tester.placeCaretInParagraph("1", 0);

          await withClock(Clock(() => DateTime(2024, 05, 26, 12, 0, 0, 0)), () async {
            // Type characters quickly.
            await tester.typeImeText("Hel");
          });
          await withClock(Clock(() => DateTime(2024, 05, 26, 12, 0, 0, 150)), () async {
            // Type characters quickly.
            await tester.typeImeText("lo ");
          });

          // Wait a bit.
          await tester.pump(const Duration(seconds: 3));

          await withClock(Clock(() => DateTime(2024, 05, 26, 12, 0, 3, 0)), () async {
            // Type characters quickly.
            await tester.typeImeText("World!");
          });

          // Ensure our typed text exists.
          expect(SuperEditorInspector.findTextInComponent("1").text, "Hello World!");

          // Undo the typing.
          await tester.pressCmdZ(tester);
          await tester.pump();

          // Ensure that the text typed later was removed, but the text typed earlier
          // remains.
          expect(SuperEditorInspector.findTextInComponent("1").text, "Hello ");
        });
      });

      group("selection and composing >", () {
        testWidgetsOnMac("merges transactions with only selection and composing changes", (tester) async {
          final testContext = await tester //
              .createDocument()
              .withLongDoc()
              .withHistoryGroupingPolicy(defaultMergePolicy)
              .pump();

          await tester.placeCaretInParagraph("1", 0);

          // Ensure we start with one history transaction for placing the caret.
          final editor = testContext.editor;
          expect(editor.history.length, 1);

          // Move the selection around a few times.
          await tester.placeCaretInParagraph("2", 5);

          await tester.placeCaretInParagraph("3", 3);

          await tester.placeCaretInParagraph("4", 0);

          // Ensure that all selection changes were merged into the initial transaction.
          expect(editor.history.length, 1);
        });

        testWidgetsOnMac("does not merge transactions when non-selection changes are present", (tester) async {
          final testContext = await tester //
              .createDocument()
              .withLongDoc()
              .withHistoryGroupingPolicy(defaultMergePolicy)
              .pump();

          await tester.placeCaretInParagraph("1", 0);

          // Ensure we start with one history transaction for placing the caret.
          final editor = testContext.editor;
          expect(editor.history.length, 1);

          // Type a few characters.
          await tester.typeImeText("Hello ");

          // Move caret to start of paragraph.
          await tester.placeCaretInParagraph("1", 0);

          // Type a few more characters.
          await tester.typeImeText("World ");

          // Ensure we have 4 transactions: selection, typing+selection, typing.
          expect(editor.history.length, 3);
        });
      });
    });
  });
}

void _expectDocumentWithCaret(String documentContent, String caretNodeId, int caretOffset) {
  expect(serializeDocumentToMarkdown(SuperEditorInspector.findDocument()!), documentContent);
  expect(
    SuperEditorInspector.findDocumentSelection(),
    DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: caretNodeId,
        nodePosition: TextNodePosition(offset: caretOffset),
      ),
    ),
  );
}
