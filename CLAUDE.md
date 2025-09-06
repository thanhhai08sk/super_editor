# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Super Editor is a Flutter monorepo containing a configurable, extensible text editor and document renderer. The project includes multiple packages and demo applications showcasing rich text editing capabilities.

## Monorepo Structure

This is a monorepo with multiple Flutter packages:

- `super_editor/` - Main text editor package
- `attributed_text/` - Text attribution system
- `super_text_layout/` - Text layout engine  
- `super_editor_markdown/` - Markdown support
- `super_editor_spellcheck/` - Spell checking features
- `super_editor_quill/` - Quill-like editor implementation
- `super_keyboard/` - Virtual keyboard handling
- `super_clones/` - Example apps cloning popular editors (Bear, Google Docs, Medium, etc.)

## Key Development Commands

### Testing
- `flutter test` - Run unit tests for the current package
- `flutter test test/specific_test.dart` - Run a specific test file
- `flutter test --name "test description"` - Run tests matching a name pattern

### Code Quality
- `flutter analyze` - Static analysis of Dart code
- `flutter pub deps --json` - Check dependency tree

### Running Examples
- `cd super_editor/example && flutter run -d macos` - Run main example app
- `cd super_editor/example_chat && flutter run` - Run chat demo
- `cd super_clones/bear && flutter run` - Run Bear clone demo

## Architecture

### Core Architecture Components

1. **Document Layer** (`src/core/`):
   - `Document` - Immutable document model with nodes
   - `MutableDocument` - Editable document implementation
   - `DocumentNode` - Base class for content nodes (paragraphs, images, etc.)
   - `Editor` - Pure Dart class for applying document changes
   - `DocumentComposer` - Manages user selection and cursor

2. **Default Editor** (`src/default_editor/`):
   - `SuperEditor` - Main Flutter widget
   - Component builders for rendering different node types
   - Platform-specific gesture handling (iOS, Android, Desktop)
   - IME integration and keyboard input handling

3. **Infrastructure** (`src/infrastructure/`):
   - Platform abstractions and utilities
   - Flutter-specific helpers and extensions
   - Gesture handling and selection management

### Key Concepts

- **Document Nodes**: Content is structured as nodes (ParagraphNode, ImageNode, ListItemNode, etc.)
- **Attributed Text**: Text with styling attributes (bold, italic, links, etc.)  
- **Component Builders**: Render document nodes to Flutter widgets
- **Selection Management**: Handles text selection across nodes
- **Command Pattern**: Document changes applied via commands for undo/redo

## Development Guidelines

### Project Principles (from CONTRIBUTING.md)
- Aggressive composition with small, effective tools
- Strong encapsulation boundaries
- Every feature needs a runnable demo
- Comprehensive testing is mandatory

### Code Organization Rules
- `core/` package contains fundamental abstractions only
- `infrastructure/` for reusable utilities not specific to text editing
- Avoid meaningless names like "manager", "helper", "utility"
- "controller" must refer specifically to Flutter controllers

### Testing Requirements
- Use lowest level test tools possible (unit tests preferred)
- Widget tests for user interactions  
- Golden tests for visual requirements
- Test all edge cases and avoid redundant testing
- Every PR must include effective tests

## Branch Strategy
- `main` branch for Flutter master compatibility
- `stable` branch for Flutter stable compatibility 
- Always check Flutter channel compatibility when working with dependencies

## Common Tasks

### Adding a New Document Node Type
1. Create node class extending `DocumentNode` 
2. Add component builder for rendering
3. Update document operations to handle the new type
4. Add comprehensive tests

### Modifying Text Editing Behavior  
1. Check existing keyboard handlers in `document_hardware_keyboard/`
2. Add or modify commands in editor reactions
3. Update gesture handlers if needed
4. Test across all supported platforms

### Working with Dependencies
When using dependencies from other monorepo packages, use path overrides in pubspec.yaml:
```yaml
dependency_overrides:
  attributed_text:
    path: ../attributed_text
```