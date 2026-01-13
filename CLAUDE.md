# SuperEditor Fork - CLAUDE.md

Custom fork of SuperEditor for Journal It! app.

**Branch**: `my_stable` | **Upstream**: `superlistapp/super_editor`

---

## Contents

1. [Quick Reference](#quick-reference) - Commands
2. [Key Files to Read](#key-files-to-read) - Start here
3. [Monorepo Packages](#monorepo-packages) - Package overview
4. [Core Architecture](#core-architecture) - Key abstractions & edit flow
5. [Directory Structure](#directory-structure) - File organization
6. [Node Types](#node-types) - Text & block nodes
7. [Attributions](#attributions) - Text styling system
8. [Extension Points](#extension-points) - Custom nodes, reactions, keyboard handlers
9. [Common Requests](#common-requests-60-total) - Edit requests reference
10. [Built-in Reactions](#built-in-reactions) - Auto-conversions
11. [Keyboard Actions](#keyboard-actions) - Key handlers
12. [Additional APIs](#additional-apis) - TextField, Reader, Chat UI
13. [Styling System](#styling-system) - Stylesheet rules
14. [Fork Modifications](#fork-modifications-my_stable-branch) - Custom changes

---

## Quick Reference

```bash
# Run example app
cd super_editor/example && flutter run -d macos

# Tests
flutter test
flutter test --update-goldens

# Analysis
flutter analyze
```

**See also:** `CONTRIBUTING.md` (design principles), `doc/website/` (comprehensive guides)

---

## Key Files to Read

**Core (must read):**
1. `lib/src/core/document.dart` - Document model
2. `lib/src/core/editor.dart` - Command system, EditContext
3. `lib/src/core/document_composer.dart` - Selection state
4. `lib/src/core/edit_context.dart` - SuperEditorContext

**Main widget:**
5. `lib/src/default_editor/super_editor.dart`

**Implementation:**
6. `lib/src/default_editor/default_document_editor.dart` - Request handlers
7. `lib/src/default_editor/default_document_editor_reactions.dart` - Reactions
8. `lib/src/default_editor/common_editor_operations.dart` - High-level API

**Custom node example:**
9. `lib/src/default_editor/tasks.dart` - TaskNode implementation

---

## Monorepo Packages

### Core Packages

| Package | Purpose |
|---------|---------|
| **super_editor** | Main rich text editor widget |
| **attributed_text** | Text attribution system (bold, italic, links) |
| **super_text_layout** | Text layout engine with decoration layers |
| **super_editor_markdown** | Markdown parsing/serialization |
| **super_editor_quill** | Quill Delta format parsing/serialization |
| **super_editor_spellcheck** | Spell checking |
| **super_editor_clipboard** | Enhanced clipboard |
| **super_keyboard** | Virtual keyboard handling |

### Utility Packages

| Package | Purpose |
|---------|---------|
| **golden_runner** | Golden test runner for stable rendering |
| **doc/** | Website documentation sources |
| **website/** | Documentation site |

**Demo Apps** (super_clones/): bear, google_docs, medium, slack, obsidian, quill

---

## Core Architecture

### Key Abstractions

```
Document (immutable)     → Collection of DocumentNodes
MutableDocument          → Editable document with change notifications
DocumentNode             → Content unit (paragraph, image, etc.)
DocumentPosition         → nodeId + nodePosition
DocumentSelection        → base + extent positions (in document_selection.dart)
Editor                   → Command execution engine
DocumentComposer         → Selection & composition state
DocumentLayout           → Visual layout queries
EditContext              → Core service locator for Editables (in core/editor.dart)
SuperEditorContext       → Widget context with document, composer, layout (in core/edit_context.dart)
```

**Note:** `EditContext` is used by reactions/commands. `SuperEditorContext` is used by keyboard handlers and contains the full widget context.

### Edit Flow (Chain of Responsibility)

```
User Action → EditRequest → RequestHandler → EditCommand
    → Document Mutation → EditEvent → EditReaction → More Requests
    → EditListener Notification
```

**Undo/Redo:** Built-in via `Editor.undo()` / `Editor.redo()`. Enable with `isHistoryEnabled: true` in `createDefaultDocumentEditor`.

---

## Directory Structure

```
super_editor/lib/src/
├── core/                      # Core abstractions
│   ├── document.dart          # Document model
│   ├── editor.dart            # Command system
│   ├── document_composer.dart # Selection state
│   ├── document_selection.dart # Selection types
│   ├── document_layout.dart   # Layout contract
│   ├── edit_context.dart      # Service locator
│   └── styles.dart            # Style system
│
├── default_editor/            # Default implementation
│   ├── super_editor.dart      # Main widget
│   ├── default_document_editor.dart      # Request handlers
│   ├── default_document_editor_reactions.dart  # Reactions
│   │
│   ├── Nodes:
│   │   ├── text.dart          # TextNode (base)
│   │   ├── paragraph.dart     # ParagraphNode
│   │   ├── list_items.dart    # ListItemNode
│   │   ├── tasks.dart         # TaskNode (checkbox)
│   │   ├── image.dart         # ImageNode
│   │   ├── horizontal_rule.dart
│   │   └── tables/            # TableBlockNode
│   │
│   ├── attributions.dart      # All attribution types
│   ├── common_editor_operations.dart  # High-level editing API
│   ├── document_gestures_mouse.dart   # Mouse gesture handling
│   ├── document_gestures_touch_android.dart
│   ├── document_gestures_touch_ios.dart
│   ├── layout_single_column/  # Layout system
│   ├── document_hardware_keyboard/  # Keyboard input
│   ├── document_ime/          # IME integration
│   ├── text_tokenizing/       # @mentions, #hashtags, action tags
│   ├── composer/              # Composer reactions
│   ├── ai/                    # AI content features
│   └── tap_handlers/          # Custom tap handlers
│
├── chat/                      # Chat UI scaffolding
│   └── message_page_scaffold.dart  # MessagePageScaffold
│
├── document_operations/       # Selection utilities
│   └── selection_operations.dart
│
├── infrastructure/            # Platform utilities & shared widgets
│   ├── keyboard_panel_scaffold.dart  # KeyboardPanelScaffold
│   ├── content_layers.dart    # ContentLayers rendering system
│   ├── document_gestures.dart # Gesture handling base
│   ├── blinking_caret.dart    # Caret rendering
│   ├── attributed_text_styles.dart   # Style application
│   ├── popovers.dart          # Popover management
│   └── platforms/             # android/, ios/, mac/
│
├── super_textfield/           # SuperTextField widget
│   ├── desktop/
│   ├── ios/
│   ├── android/
│   └── input_method_engine/
│
├── super_reader/              # Read-only document viewer
│
├── undo_redo.dart             # Undo/redo system
└── test/                      # Test utilities
```

---

## Node Types

### Text Nodes (extend TextNode)

| Node | Purpose | Key Properties |
|------|---------|----------------|
| `TextNode` | Base text | `AttributedText` |
| `ParagraphNode` | Paragraphs | `blockType`, `textAlign`, indent |
| `ListItemNode` | Lists | `type` (ordered/unordered), indent |
| `TaskNode` | Checkboxes | `isComplete`, indent |

### Block Nodes (extend BlockNode)

| Node | Purpose |
|------|---------|
| `ImageNode` | Images (URL-based) |
| `HorizontalRuleNode` | Dividers |
| `TableBlockNode` | Tables (in `tables/table_block.dart`) |

---

## Attributions

### Named Attributions (NamedAttribution)
```dart
// Inline styles
boldAttribution, italicsAttribution, underlineAttribution, strikethroughAttribution
codeAttribution

// Block types
header1Attribution ... header6Attribution
paragraphAttribution, blockquoteAttribution

// Errors
spellingErrorAttribution, grammarErrorAttribution
```

### Const ScriptAttribution Instances
```dart
superscriptAttribution  // ScriptAttribution.superscript()
subscriptAttribution    // ScriptAttribution.subscript()
```

### Class-based Attributions

| Attribution | Purpose |
|-------------|---------|
| `LinkAttribution(plainTextUri, [uri])` | Hyperlinks |
| `ColorAttribution(color)` | Text foreground color |
| `BackgroundColorAttribution(color)` | Text background color |
| `FontSizeAttribution(size)` | Inline font size |
| `FontFamilyAttribution(family)` | Inline font family |
| `ScriptAttribution(type)` | Superscript/subscript |
| `CustomUnderlineAttribution([type])` | Custom underline styles |
| `OpacityAttribution(opacity)` | Text opacity |

### Tag Attributions (text_tokenizing/)
| Attribution | Purpose |
|-------------|---------|
| `PatternTagAttribution` | Pattern-matched tags |
| `CommittedStableTagAttribution` | Committed @mentions |
| `stableTagComposingAttribution` | In-progress @mentions (const NamedAttribution) |

---

## Extension Points

### 1. Custom Node Type

```dart
// Step 1: Define node (must implement all abstract methods)
class CustomNode extends DocumentNode {
  CustomNode({required this.id, ...});

  @override final String id;
  @override NodePosition get beginningPosition => ...;
  @override NodePosition get endPosition => ...;
  @override bool containsPosition(Object position) => ...;
  @override NodePosition selectUpstreamPosition(NodePosition p1, NodePosition p2) => ...;
  @override NodePosition selectDownstreamPosition(NodePosition p1, NodePosition p2) => ...;
  @override NodeSelection computeSelection({required NodePosition base, required NodePosition extent}) => ...;
  @override String? copyContent(NodeSelection selection) => ...;
}

// Step 2: View model
class CustomViewModel extends SingleColumnLayoutComponentViewModel { ... }

// Step 3: Component builder
class CustomComponentBuilder implements ComponentBuilder {
  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document doc, DocumentNode node) {
    if (node is! CustomNode) return null;
    return CustomViewModel(...);
  }

  @override
  Widget? createComponent(context, viewModel) {
    if (viewModel is! CustomViewModel) return null;
    return CustomComponent(...);
  }
}

// Step 4: Register
SuperEditor(
  componentBuilders: [CustomComponentBuilder(), ...defaultComponentBuilders],
)
```

### 2. Custom Reaction

```dart
class CustomReaction extends EditReaction {
  /// Called within the same transaction - changes undo together with triggering edit
  @override
  void modifyContent(EditContext context, RequestDispatcher dispatcher, List<EditEvent> changeList) {
    // Use for tightly coupled reactions (e.g., spell-check attributions)
  }

  /// Called as a separate transaction - changes undo independently
  @override
  void react(EditContext context, RequestDispatcher dispatcher, List<EditEvent> changeList) {
    // Use for standalone reactions
    if (shouldReact(changeList)) {
      dispatcher.execute([/* new requests */]);
    }
  }
}

Editor(reactionPipeline: [CustomReaction(), ...defaultEditorReactions])
```

### 3. Custom Keyboard Handler

```dart
ExecutionInstruction customKeyHandler({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey == LogicalKeyboardKey.someKey) {
    // Handle
    return ExecutionInstruction.haltExecution;
  }
  return ExecutionInstruction.continueExecution;
}

SuperEditor(keyboardActions: [customKeyHandler, ...defaultKeyboardActions])
```

**Two action lists:** `defaultKeyboardActions` (hardware), `defaultImeKeyboardActions` (IME/software)

### 4. Custom Style Phase

```dart
class CustomStylePhase extends SingleColumnLayoutStylePhase {
  @override
  SingleColumnLayoutViewModel style(Document doc, SingleColumnLayoutViewModel vm) {
    // Modify component view models directly (no copyWith - construct new VM if needed)
    for (final componentVm in vm.componentViewModels) {
      // Apply custom styling to each component
    }
    return vm;
  }
}

SuperEditor(customStylePhases: [CustomStylePhase()])
```

---

## Common Requests (60+ total)

### Selection
- `ChangeSelectionRequest`, `ClearSelectionRequest`, `PushCaretRequest`
- `ExpandSelectionRequest`, `CollapseSelectionRequest`

### Text Insertion
- `InsertTextRequest`, `InsertAttributedTextRequest`
- `InsertCharacterAtCaretRequest`, `InsertPlainTextAtCaretRequest`
- `InsertNewlineAtCaretRequest`, `InsertSoftNewlineAtCaretRequest`

### Paragraph Operations
- `SplitParagraphRequest`, `CombineParagraphsRequest`
- `ChangeParagraphBlockTypeRequest`, `ChangeParagraphAlignmentRequest`
- `IndentParagraphRequest`, `UnIndentParagraphRequest`

### List Operations
- `ConvertParagraphToListItemRequest`, `ConvertListItemToParagraphRequest`
- `IndentListItemRequest`, `UnIndentListItemRequest`
- `SplitListItemRequest`, `ChangeListItemTypeRequest`

### Task Operations
- `ChangeTaskCompletionRequest`
- `ConvertParagraphToTaskRequest`, `ConvertTaskToParagraphRequest`
- `IndentTaskRequest`, `UnIndentTaskRequest`

### Node Operations
- `InsertNodeAtIndexRequest`, `InsertNodeAfterNodeRequest`, `InsertNodeBeforeNodeRequest`
- `ReplaceNodeRequest`, `MoveNodeRequest`, `DeleteNodeRequest`

### Content Operations
- `DeleteContentRequest`, `DeleteSelectionRequest`, `ClearDocumentRequest`
- `DeleteUpstreamCharacterRequest`, `DeleteDownstreamCharacterRequest`
- `PasteEditorRequest`, `PasteStructuredContentEditorRequest`

### Styling
- `AddTextAttributionsRequest`, `RemoveTextAttributionsRequest`
- `ToggleTextAttributionsRequest`

### Composer
- `ChangeComposingRegionRequest`, `ClearComposingRegionRequest`
- `ChangeInteractionModeRequest`

---

## Built-in Reactions

| Reaction | Trigger | Result |
|----------|---------|--------|
| `HeaderConversionReaction` | `# ` | → Heading |
| `UnorderedListItemConversionReaction` | `* ` or `- ` | → Bullet list |
| `OrderedListItemConversionReaction` | `1. ` or `1) ` | → Numbered list |
| `BlockquoteConversionReaction` | `> ` | → Blockquote |
| `HorizontalRuleConversionReaction` | `--- ` or `—- ` | → HR (needs trailing space) |
| `LinkifyReaction` | URL typed | → Link |
| `ImageUrlConversionReaction` | Image URL | → Image node |
| `DashConversionReaction` | `--` | → Em-dash |
| `UpdateComposerTextStylesReaction` | Selection change | Updates composer styles |
| `UpdateSubTaskIndentAfterTaskDeletionReaction` | Task deleted | Maintains indent |

### Tag Reactions (text_tokenizing/)
- `TagUserReaction` - Handles user mentions
- `AdjustSelectionAroundTagReaction` - Selection handling for tags
- `ActionTagComposingReaction` - Action tag composition
- `PatternTagReaction` - Pattern-matched tags

---

## Keyboard Actions

### Categories (in `document_keyboard_actions.dart`)

**Undo/Redo:** `undoWhenCmdZOrCtrlZIsPressed`, `redoWhenCmdShiftZOrCtrlShiftZIsPressed`

**Clipboard:** `copyWhenCmdCIsPressed`, `cutWhenCmdXIsPressed`, `pasteWhenCmdVIsPressed`

**Formatting:** `cmdBToToggleBold`, `cmdIToToggleItalics`

**Navigation:** `moveUpAndDownWithArrowKeys`, `moveLeftAndRightWithArrowKeys`, `moveToLineStartWithHome`, `moveToLineEndWithEnd`

**Scrolling:** `scrollOnPageUpKeyPress`, `scrollOnPageDownKeyPress`, `scrollOnCtrlOrCmdAndHomeKeyPress`

**Selection:** `selectAllWhenCmdAIsPressed`, `collapseSelectionWhenEscIsPressed`

**Deletion:** `deleteUpstreamContentWithBackspace`, `mergeNodeWithNextWhenDeleteIsPressed`, `deleteWordUpstreamWithAltBackspaceOnMac`

**Text Entry:** `anyCharacterOrDestructiveKeyToDeleteSelection`, `enterToInsertNewTask` (tasks.dart), `enterToInsertBlockNewline` (paragraph.dart)

**Indentation:** `indentListItemWhenBackspaceIsPressed`, `unIndentListItemWhenBackspaceIsPressed`, `tabToIndentListItem`, `shiftTabToUnIndentListItem` (list_items.dart), `indentTaskWhenTabIsPressed`, `unIndentTaskWhenShiftTabIsPressed` (tasks.dart)

**Control:** `blockControlKeys`, `toggleInteractionModeWhenCmdOrCtrlPressed`

---

## Additional APIs

### SuperTextField
Single-line/multi-line text field with platform-specific implementations:
- `SuperTextField` - Main widget
- Platform folders: `desktop/`, `ios/`, `android/`
- IME integration in `input_method_engine/`

### SuperReader
Read-only document viewer:
- `readOnlyDefaultStylesheet`
- `readOnlyDefaultComponentBuilders`
- `ReadOnlyDocumentKeyboardAction`

### Chat UI
`MessagePageScaffold` (in `chat/message_page_scaffold.dart`) - Scaffold for chat-like UIs with bottom sheet message editor.

`KeyboardPanelScaffold` (in `infrastructure/keyboard_panel_scaffold.dart`) - Scaffold for keyboard panel management.

---

## Styling System

### Stylesheet Rules
```dart
StyleRule(
  BlockSelector("header1"),
  (doc, node) => {
    Styles.textStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    Styles.padding: EdgeInsets.only(top: 24),
  }
)
```

### Styling Pipeline
1. Base view models from nodes
2. Stylesheet styling
3. Per-component styling
4. User selection styling
5. Composing region styling
6. Custom style phases

---

## Fork Modifications (`my_stable` branch)

### IME/Keyboard Fixes
- Fix: `OverlayPortalController.show()` called during build
- Add support for pasting from Gboard
- Fix pasting losing the first node
- Fix toolbar doesn't show up for pasting
- Workaround: Samsung keyboard IME position mapping bugs (multiple fixes)
- Workaround: "Couldn't map an IME position to a document position" errors

### Visual/Layout Fixes
- Remove `selectionHighlightBoxVerticalExpansion`
- Fix sliver bugs

### Upstream Merges
- Table support (Markdown tables, table block component)
- Rich text copying support
- Various bug fixes from upstream stable

---

## Platform Notes

- **Actively developed**: macOS, Web, Android, iOS
- **Spotty verification**: Windows, Linux

**Versioning:**
- `main` → Flutter master
- `stable` → Flutter stable
- `my_stable` → Custom stable with cherry-picks and Samsung keyboard workarounds

---

## Design Principles

1. **Aggressive composition** - Small, effective tools
2. **Strong encapsulation** - Clear boundaries
3. **Every feature needs a demo** - Runnable examples
4. **Comprehensive testing** - All features tested

See `CONTRIBUTING.md` for full guidelines.
