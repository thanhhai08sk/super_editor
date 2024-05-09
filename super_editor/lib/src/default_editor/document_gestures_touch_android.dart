import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:overlord/follow_the_leader.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/super_editor.dart';
import 'package:super_editor/src/default_editor/text_tools.dart';
import 'package:super_editor/src/document_operations/selection_operations.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/content_layers.dart';
import 'package:super_editor/src/infrastructure/flutter/build_context.dart';
import 'package:super_editor/src/infrastructure/flutter/flutter_scheduler.dart';
import 'package:super_editor/src/infrastructure/multi_tap_gesture.dart';
import 'package:super_editor/src/infrastructure/platforms/android/android_document_controls.dart';
import 'package:super_editor/src/infrastructure/platforms/android/long_press_selection.dart';
import 'package:super_editor/src/infrastructure/platforms/android/magnifier.dart';
import 'package:super_editor/src/infrastructure/platforms/android/selection_handles.dart';
import 'package:super_editor/src/infrastructure/platforms/mobile_documents.dart';
import 'package:super_editor/src/infrastructure/signal_notifier.dart';
import 'package:super_editor/src/infrastructure/touch_controls.dart';

import '../infrastructure/document_gestures.dart';
import '../infrastructure/document_gestures_interaction_overrides.dart';
import 'selection_upstream_downstream.dart';

/// An [InheritedWidget] that provides shared access to a [SuperEditorAndroidControlsController],
/// which coordinates the state of Android controls like the caret, handles, magnifier, etc.
///
/// This widget and its associated controller exist so that [SuperEditor] has maximum freedom
/// in terms of where to implement Android gestures vs carets vs the magnifier vs the toolbar.
/// Each of these responsibilities have some unique differences, which make them difficult or
/// impossible to implement within a single widget. By sharing a controller, a group of independent
/// widgets can work together to cover those various responsibilities.
///
/// Centralizing a controller in an [InheritedWidget] also allows [SuperEditor] to share that
/// control with application code outside of [SuperEditor], by placing a [SuperEditorAndroidControlsScope]
/// above the [SuperEditor] in the widget tree. For this reason, [SuperEditor] should access
/// the [SuperEditorAndroidControlsScope] through [rootOf].
class SuperEditorAndroidControlsScope extends InheritedWidget {
  /// Finds the highest [SuperEditorAndroidControlsScope] in the widget tree, above the given
  /// [context], and returns its associated [SuperEditorAndroidControlsController].
  static SuperEditorAndroidControlsController rootOf(BuildContext context) {
    final data = maybeRootOf(context);

    if (data == null) {
      throw Exception(
          "Tried to depend upon the root SuperEditorAndroidControlsScope but no such ancestor widget exists.");
    }

    return data;
  }

  static SuperEditorAndroidControlsController? maybeRootOf(BuildContext context) {
    InheritedElement? root;

    context.visitAncestorElements((element) {
      if (element is! InheritedElement || element.widget is! SuperEditorAndroidControlsScope) {
        // Keep visiting.
        return true;
      }

      root = element;

      // Keep visiting, to ensure we get the root scope.
      return true;
    });

    if (root == null) {
      return null;
    }

    // Create build dependency on the Android controls context.
    context.dependOnInheritedElement(root!);

    // Return the current Android controls data.
    return (root!.widget as SuperEditorAndroidControlsScope).controller;
  }

  /// Finds the nearest [SuperEditorAndroidControlsScope] in the widget tree, above the given
  /// [context], and returns its associated [SuperEditorAndroidControlsController].
  static SuperEditorAndroidControlsController nearestOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperEditorAndroidControlsScope>()!.controller;

  static SuperEditorAndroidControlsController? maybeNearestOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperEditorAndroidControlsScope>()?.controller;

  const SuperEditorAndroidControlsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SuperEditorAndroidControlsController controller;

  @override
  bool updateShouldNotify(SuperEditorAndroidControlsScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// A controller, which coordinates the state of various Android editor controls, including
/// the caret, handles, magnifier, and toolbar.
class SuperEditorAndroidControlsController {
  SuperEditorAndroidControlsController({
    this.controlsColor,
    LeaderLink? collapsedHandleFocalPoint,
    this.collapsedHandleBuilder,
    LeaderLink? upstreamHandleFocalPoint,
    LeaderLink? downstreamHandleFocalPoint,
    this.expandedHandlesBuilder,
    this.magnifierBuilder,
    this.toolbarBuilder,
    this.createOverlayControlsClipper,
  })  : collapsedHandleFocalPoint = collapsedHandleFocalPoint ?? LeaderLink(),
        upstreamHandleFocalPoint = upstreamHandleFocalPoint ?? LeaderLink(),
        downstreamHandleFocalPoint = downstreamHandleFocalPoint ?? LeaderLink();

  void dispose() {
    cancelCollapsedHandleAutoHideCountdown();
    _shouldCaretBlink.dispose();
    _shouldShowMagnifier.dispose();
    _shouldShowToolbar.dispose();
    caretJumpToOpaqueSignal.dispose();
  }

  /// Whether the caret should blink right now.
  ValueListenable<bool> get shouldCaretBlink => _shouldCaretBlink;
  final _shouldCaretBlink = ValueNotifier<bool>(true);

  /// Tells the caret to blink by setting [shouldCaretBlink] to `true`.
  void blinkCaret() {
    _shouldCaretBlink.value = true;
  }

  /// Tells the caret to stop blinking by setting [shouldCaretBlink] to `false`.
  void doNotBlinkCaret() {
    _shouldCaretBlink.value = false;
  }

  /// Signal that's notified when the caret should return to fully opaque, such as
  /// when the user moves the caret.
  final caretJumpToOpaqueSignal = SignalNotifier();

  /// Immediately make the caret fully opaque.
  void jumpCaretToOpaque() {
    caretJumpToOpaqueSignal.notifyListeners();
  }

  /// Color of the caret and text selection drag handles on Android.
  ///
  /// The default handle builders honor this color. If custom handle builders are
  /// provided, its up to those handle builders to honor this color, or not.
  final Color? controlsColor;

  /// The focal point for the collapsed drag handle.
  ///
  /// The collapsed handle builder should place the handle near this focal point.
  final LeaderLink collapsedHandleFocalPoint;

  /// Whether the collapsed drag handle should be displayed right now.
  ///
  /// This value is enforced to be opposite of [shouldShowExpandedHandles].
  ValueListenable<bool> get shouldShowCollapsedHandle => _shouldShowCollapsedHandle;
  final _shouldShowCollapsedHandle = ValueNotifier<bool>(false);

  Timer? _collapsedHandleAutoHideCountdown;

  /// Shows the collapsed drag handle by setting [shouldShowCollapsedHandle] to `true`, and also
  /// hides the expanded handle by setting [shouldShowExpandedHandles] to `false`.
  void showCollapsedHandle() {
    cancelCollapsedHandleAutoHideCountdown();

    _shouldShowCollapsedHandle.value = true;
    _shouldShowExpandedHandles.value = false;
  }

  /// Starts a short countdown, after which the collapsed handle will be
  /// hidden (the caret will remain visible).
  void startCollapsedHandleAutoHideCountdown() {
    _collapsedHandleAutoHideCountdown?.cancel();

    _collapsedHandleAutoHideCountdown = Timer(const Duration(seconds: 5), () {
      hideCollapsedHandle();
    });
  }

  /// Cancels any on-going timer started by [startCollapsedHandleAutoHideCountdown].
  void cancelCollapsedHandleAutoHideCountdown() {
    _collapsedHandleAutoHideCountdown?.cancel();
    _collapsedHandleAutoHideCountdown = null;
  }

  /// Hides the collapsed drag handle by setting [shouldShowCollapsedHandle] to `false`.
  void hideCollapsedHandle() {
    cancelCollapsedHandleAutoHideCountdown();

    _shouldShowCollapsedHandle.value = false;
  }

  /// Toggles [shouldShowCollapsedHandle], and if necessary, hides the expanded handles.
  void toggleCollapsedHandle() {
    if (shouldShowCollapsedHandle.value) {
      hideCollapsedHandle();
    } else {
      showCollapsedHandle();
    }
  }

  /// (Optional) Builder to create the visual representation of all drag handles: collapsed,
  /// upstream, downstream.
  ///
  /// If [collapsedHandleBuilder] is `null`, a default Android handle is displayed.
  final DocumentCollapsedHandleBuilder? collapsedHandleBuilder;

  /// The focal point for the upstream drag handle, when the selection is expanded.
  ///
  /// The upstream handle builder should place its handle near this focal point.
  final LeaderLink upstreamHandleFocalPoint;

  /// The focal point for the downstream drag handle, when the selection is expanded.
  ///
  /// The downstream handle builder should place its handle near this focal point.
  final LeaderLink downstreamHandleFocalPoint;

  /// Whether the expanded drag handles should be displayed right now.
  ///
  /// This value is enforced to be opposite of [shouldShowCollapsedHandle].
  ValueListenable<bool> get shouldShowExpandedHandles => _shouldShowExpandedHandles;
  final _shouldShowExpandedHandles = ValueNotifier<bool>(false);

  /// Shows the expanded drag handles by setting [shouldShowExpandedHandles] to `true`, and also
  /// hides the collapsed handle by setting [shouldShowCollapsedHandle] to `false`.
  void showExpandedHandles() {
    _shouldShowExpandedHandles.value = true;
    _shouldShowCollapsedHandle.value = false;
  }

  /// Hides the expanded drag handles by setting [shouldShowExpandedHandles] to `false`.
  void hideExpandedHandles() => _shouldShowExpandedHandles.value = false;

  /// Toggles [shouldShowExpandedHandles], and if necessary, hides the collapsed handle.
  void toggleExpandedHandles() {
    if (shouldShowExpandedHandles.value) {
      hideCollapsedHandle();
    } else {
      showCollapsedHandle();
    }
  }

  /// (Optional) Builder to create the visual representation of the expanded drag handles.
  ///
  /// If [expandedHandlesBuilder] is `null`, default Android handles are displayed.
  final DocumentExpandedHandlesBuilder? expandedHandlesBuilder;

  /// Whether the Android magnifier should be displayed right now.
  ValueListenable<bool> get shouldShowMagnifier => _shouldShowMagnifier;
  final _shouldShowMagnifier = ValueNotifier<bool>(false);

  /// Shows the magnifier by setting [shouldShowMagnifier] to `true`.
  void showMagnifier() => _shouldShowMagnifier.value = true;

  /// Hides the magnifier by setting [shouldShowMagnifier] to `false`.
  void hideMagnifier() => _shouldShowMagnifier.value = false;

  /// Toggles [shouldShowMagnifier].
  void toggleMagnifier() => _shouldShowMagnifier.value = !_shouldShowMagnifier.value;

  /// Link to a location where a magnifier should be focused.
  ///
  /// The magnifier builder should place the magnifier near this focal point.
  final magnifierFocalPoint = LeaderLink();

  /// (Optional) Builder to create the visual representation of the magnifier.
  ///
  /// If [magnifierBuilder] is `null`, a default Android magnifier is displayed.
  final DocumentMagnifierBuilder? magnifierBuilder;

  /// Whether the Android floating toolbar should be displayed right now.
  ValueListenable<bool> get shouldShowToolbar => _shouldShowToolbar;
  final _shouldShowToolbar = ValueNotifier<bool>(false);

  /// Shows the toolbar by setting [shouldShowToolbar] to `true`.
  void showToolbar() => _shouldShowToolbar.value = true;

  /// Hides the toolbar by setting [shouldShowToolbar] to `false`.
  void hideToolbar() => _shouldShowToolbar.value = false;

  /// Toggles [shouldShowToolbar].
  void toggleToolbar() => _shouldShowToolbar.value = !_shouldShowToolbar.value;

  /// Link to a location where a toolbar should be focused.
  ///
  /// This link probably points to a rectangle, such as a bounding rectangle
  /// around the user's selection. Therefore, the toolbar builder shouldn't
  /// assume that this focal point is a single pixel.
  final toolbarFocalPoint = LeaderLink();

  /// (Optional) Builder to create the visual representation of the floating
  /// toolbar.
  ///
  /// If [toolbarBuilder] is `null`, a default Android toolbar is displayed.
  final DocumentFloatingToolbarBuilder? toolbarBuilder;

  /// Creates a clipper that restricts where the toolbar and magnifier can
  /// appear in the overlay.
  ///
  /// If no clipper factory method is provided, then the overlay controls
  /// will be allowed to appear anywhere in the overlay in which they sit
  /// (probably the entire screen).
  final CustomClipper<Rect> Function(BuildContext overlayContext)? createOverlayControlsClipper;
}

/// A [SuperEditorDocumentLayerBuilder] that builds an [AndroidToolbarFocalPointDocumentLayer], which
/// positions a [Leader] widget around the document selection, as a focal point for an Android
/// floating toolbar.
class SuperEditorAndroidToolbarFocalPointDocumentLayerBuilder implements SuperEditorLayerBuilder {
  const SuperEditorAndroidToolbarFocalPointDocumentLayerBuilder({
    // ignore: unused_element
    this.showDebugLeaderBounds = false,
  });

  /// Whether to paint colorful bounds around the leader widget.
  final bool showDebugLeaderBounds;

  @override
  ContentLayerWidget build(BuildContext context, SuperEditorContext editorContext) {
    if (defaultTargetPlatform != TargetPlatform.android ||
        SuperEditorAndroidControlsScope.maybeNearestOf(context) == null) {
      // There's no controls scope. This probably means SuperEditor is configured with
      // a non-Android gesture mode. Build nothing.
      return const ContentLayerProxyWidget(child: SizedBox());
    }

    return AndroidToolbarFocalPointDocumentLayer(
      document: editorContext.document,
      selection: editorContext.composer.selectionNotifier,
      toolbarFocalPointLink: SuperEditorAndroidControlsScope.rootOf(context).toolbarFocalPoint,
      showDebugLeaderBounds: showDebugLeaderBounds,
    );
  }
}

/// A [SuperEditorLayerBuilder], which builds an [AndroidHandlesDocumentLayer],
/// which displays Android-style caret and handles.
class SuperEditorAndroidHandlesDocumentLayerBuilder implements SuperEditorLayerBuilder {
  const SuperEditorAndroidHandlesDocumentLayerBuilder({
    this.caretColor,
  });

  /// The (optional) color of the caret (not the drag handle), by default the color
  /// defers to the root [SuperEditorAndroidControlsScope], or the app theme if the
  /// controls controller has no preference for the color.
  final Color? caretColor;

  @override
  ContentLayerWidget build(BuildContext context, SuperEditorContext editContext) {
    if (defaultTargetPlatform != TargetPlatform.android ||
        SuperEditorAndroidControlsScope.maybeNearestOf(context) == null) {
      // There's no controls scope. This probably means SuperEditor is configured with
      // a non-Android gesture mode. Build nothing.
      return const ContentLayerProxyWidget(child: SizedBox());
    }

    return AndroidHandlesDocumentLayer(
      document: editContext.document,
      documentLayout: editContext.documentLayout,
      selection: editContext.composer.selectionNotifier,
      changeSelection: (newSelection, changeType, reason) {
        editContext.editor.execute([
          ChangeSelectionRequest(newSelection, changeType, reason),
          const ClearComposingRegionRequest(),
        ]);
      },
      caretColor: caretColor,
    );
  }
}

/// Document gesture interactor that's designed for Android touch input, e.g.,
/// drag to scroll, and handles to control selection.
class AndroidDocumentTouchInteractor extends StatefulWidget {
  const AndroidDocumentTouchInteractor({
    Key? key,
    required this.focusNode,
    required this.editor,
    required this.document,
    required this.getDocumentLayout,
    required this.selection,
    required this.scrollController,
    this.contentTapHandler,
    this.dragAutoScrollBoundary = const AxisOffset.symmetric(54),
    required this.dragHandleAutoScroller,
    this.showDebugPaint = false,
    this.child,
  }) : super(key: key);

  final FocusNode focusNode;

  final Editor editor;
  final Document document;
  final DocumentLayout Function() getDocumentLayout;
  final ValueListenable<DocumentSelection?> selection;

  /// Optional handler that responds to taps on content, e.g., opening
  /// a link when the user taps on text with a link attribution.
  final ContentTapDelegate? contentTapHandler;

  final ScrollController scrollController;

  /// The closest that the user's selection drag gesture can get to the
  /// document boundary before auto-scrolling.
  ///
  /// The default value is `54.0` pixels for both the leading and trailing
  /// edges.
  final AxisOffset dragAutoScrollBoundary;

  final ValueNotifier<DragHandleAutoScroller?> dragHandleAutoScroller;

  final bool showDebugPaint;

  final Widget? child;

  @override
  State createState() => _AndroidDocumentTouchInteractorState();
}

class _AndroidDocumentTouchInteractorState extends State<AndroidDocumentTouchInteractor>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  SuperEditorAndroidControlsController? _controlsController;

  bool _isScrolling = false;

  // The ScrollPosition attached to the _ancestorScrollable, if there's an ancestor
  // Scrollable.
  ScrollPosition? _ancestorScrollPosition;
  // The actual ScrollPosition that's used for the document layout, either
  // the Scrollable installed by this interactor, or an ancestor Scrollable.
  ScrollPosition? _activeScrollPosition;

  Offset? _globalTapDownOffset;
  Offset? _globalStartDragOffset;
  Offset? _dragStartInDoc;
  Offset? _startDragPositionOffset;
  double? _dragStartScrollOffset;
  Offset? _globalDragOffset;

  /// Holds the drag gesture that scrolls the document.
  Drag? _scrollingDrag;

  final _magnifierGlobalOffset = ValueNotifier<Offset?>(null);

  Timer? _tapDownLongPressTimer;
  bool get _isLongPressInProgress => _longPressStrategy != null;
  AndroidDocumentLongPressSelectionStrategy? _longPressStrategy;

  bool _isCaretDragInProgress = false;

  @override
  void initState() {
    super.initState();

    widget.dragHandleAutoScroller.value = DragHandleAutoScroller(
      vsync: this,
      dragAutoScrollBoundary: widget.dragAutoScrollBoundary,
      getScrollPosition: () => scrollPosition,
      getViewportBox: () => viewportBox,
    );

    _configureScrollController();

    widget.document.addListener(_onDocumentChange);
    widget.selection.addListener(_onSelectionChange);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _controlsController = SuperEditorAndroidControlsScope.rootOf(context);

    _ancestorScrollPosition = context.findAncestorScrollableWithVerticalScroll?.position;

    // On the next frame, check if our active scroll position changed to a
    // different instance. If it did, move our listener to the new one.
    //
    // This is posted to the next frame because the first time this method
    // runs, we haven't attached to our own ScrollController yet, so
    // this.scrollPosition might be null.
    onNextFrame((_) => _updateScrollPositionListener());
  }

  @override
  void didUpdateWidget(AndroidDocumentTouchInteractor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.document != oldWidget.document) {
      oldWidget.document.removeListener(_onDocumentChange);
      widget.document.addListener(_onDocumentChange);
    }

    if (widget.selection != oldWidget.selection) {
      oldWidget.selection.removeListener(_onSelectionChange);
      widget.selection.addListener(_onSelectionChange);
    }

    if (widget.scrollController != oldWidget.scrollController) {
      _teardownScrollController();
      _configureScrollController();
    }
  }

  @override
  void didChangeMetrics() {
    // The available screen dimensions may have changed, e.g., due to keyboard
    // appearance/disappearance. Reflow the layout. Use a post-frame callback
    // to give the rest of the UI a chance to reflow, first.
    onNextFrame((_) {
      _ensureSelectionExtentIsVisible();

      setState(() {
        // reflow document layout
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    widget.document.removeListener(_onDocumentChange);
    widget.selection.removeListener(_onSelectionChange);

    _teardownScrollController();

    widget.dragHandleAutoScroller.value!.dispose();
    widget.dragHandleAutoScroller.value = null;

    super.dispose();
  }

  /// Returns the layout for the current document, which answers questions
  /// about the locations and sizes of visual components within the layout.
  DocumentLayout get _docLayout => widget.getDocumentLayout();

  /// Returns the `ScrollPosition` that controls the scroll offset of
  /// this widget.
  ///
  /// If this widget has an ancestor `Scrollable`, then the returned
  /// `ScrollPosition` belongs to that ancestor `Scrollable`, and this
  /// widget doesn't include a `ScrollView`.
  ///
  /// If this widget doesn't have an ancestor `Scrollable`, then this
  /// widget includes a `ScrollView` and the `ScrollView`'s position
  /// is returned.
  ScrollPosition get scrollPosition => _ancestorScrollPosition ?? widget.scrollController.position;

  /// Returns the `RenderBox` for the scrolling viewport.
  ///
  /// If this widget has an ancestor `Scrollable`, then the returned
  /// `RenderBox` belongs to that ancestor `Scrollable`.
  ///
  /// If this widget doesn't have an ancestor `Scrollable`, then this
  /// widget includes a `ScrollView` and this `State`'s render object
  /// is the viewport `RenderBox`.
  RenderBox get viewportBox =>
      (context.findAncestorScrollableWithVerticalScroll?.context.findRenderObject() ?? context.findRenderObject())
          as RenderBox;

  Offset _getDocumentOffsetFromGlobalOffset(Offset globalOffset) {
    return _docLayout.getDocumentOffsetFromAncestorOffset(globalOffset);
  }

  Offset _documentOffsetToViewportOffset(Offset documentOffset) {
    final globalOffset = _docLayout.getGlobalOffsetFromDocumentOffset(documentOffset);
    return viewportBox.globalToLocal(globalOffset);
  }

  /// Maps the given [interactorOffset] within the interactor's coordinate space
  /// to the same screen position in the viewport's coordinate space.
  ///
  /// When this interactor includes it's own `ScrollView`, the [interactorOffset]
  /// is the same as the viewport offset.
  ///
  /// When this interactor defers to an ancestor `Scrollable`, then the
  /// [interactorOffset] is transformed into the ancestor coordinate space.
  Offset _interactorOffsetInViewport(Offset interactorOffset) {
    // Viewport might be our box, or an ancestor box if we're inside someone
    // else's Scrollable.
    final interactorBox = context.findRenderObject() as RenderBox;
    return viewportBox.globalToLocal(
      interactorBox.localToGlobal(interactorOffset),
    );
  }

  void _configureScrollController() {
    onNextFrame((_) => scrollPosition.isScrollingNotifier.addListener(_onScrollActivityChange));
  }

  void _teardownScrollController() {
    widget.scrollController.removeListener(_onScrollActivityChange);

    if (widget.scrollController.hasClients) {
      scrollPosition.isScrollingNotifier.removeListener(_onScrollActivityChange);
    }
  }

  void _onScrollActivityChange() {
    final isScrolling = scrollPosition.isScrollingNotifier.value;

    if (isScrolling) {
      _isScrolling = true;

      // The user started to scroll.
      // Cancel the timer to stop trying to detect a long press.
      _tapDownLongPressTimer?.cancel();
      _tapDownLongPressTimer = null;
    } else {
      onNextFrame((_) {
        // Set our scrolling flag to false on the next frame, so that our tap handlers
        // have an opportunity to see that the scrollable was scrolling when the user
        // tapped down.
        //
        // See the "on tap down" handler for more info about why this flag is important.
        _isScrolling = false;
      });
    }
  }

  void _ensureSelectionExtentIsVisible() {
    editorGesturesLog.fine("Ensuring selection extent is visible");
    final selection = widget.selection.value;
    if (selection == null) {
      // There's no selection. We don't need to take any action.
      return;
    }

    // Calculate the y-value of the selection extent side of the selected content so that we
    // can ensure they're visible.
    final selectionRectInDocumentLayout =
        widget.getDocumentLayout().getRectForSelection(selection.base, selection.extent)!;
    final extentOffsetInViewport = widget.document.getAffinityForSelection(selection) == TextAffinity.downstream
        ? _documentOffsetToViewportOffset(selectionRectInDocumentLayout.bottomCenter)
        : _documentOffsetToViewportOffset(selectionRectInDocumentLayout.topCenter);

    widget.dragHandleAutoScroller.value!.ensureOffsetIsVisible(extentOffsetInViewport);
  }

  void _onDocumentChange(_) {
    onNextFrame((_) {
      _ensureSelectionExtentIsVisible();
    });
  }

  void _onSelectionChange() {
    if (widget.selection.value == null) {
      _controlsController!
        ..hideCollapsedHandle()
        ..hideExpandedHandles()
        ..hideMagnifier()
        ..hideToolbar();
    }
  }

  void _updateScrollPositionListener() {
    final newScrollPosition = scrollPosition;
    if (newScrollPosition != _activeScrollPosition) {
      _activeScrollPosition = newScrollPosition;
    }
  }

  bool _wasScrollingOnTapDown = false;
  void _onTapDown(TapDownDetails details) {
    // When the user scrolls and releases, the scrolling continues with momentum.
    // If the user then taps down again, the momentum stops. When this happens, we
    // still receive tap callbacks. But we don't want to take any further action,
    // like moving the caret, when the user taps to stop scroll momentum. We have
    // to carefully watch the scrolling activity to recognize when this happens.
    // We can't check whether we're scrolling in "on tap up" because by then the
    // scrolling has already stopped. So we log whether we're scrolling "on tap down"
    // and then check this flag in "on tap up".
    _wasScrollingOnTapDown = _isScrolling;

    final position = scrollPosition;
    if (position is ScrollPositionWithSingleContext) {
      position.goIdle();
    }

    _globalTapDownOffset = details.globalPosition;
    _tapDownLongPressTimer?.cancel();
    if (!disableLongPressSelectionForSuperlist) {
      _tapDownLongPressTimer = Timer(kLongPressTimeout, _onLongPressDown);
    }
  }

  // Runs when a tap down has lasted long enough to signify a long-press.
  void _onLongPressDown() {
    _longPressStrategy = AndroidDocumentLongPressSelectionStrategy(
      document: widget.document,
      documentLayout: _docLayout,
      select: _updateLongPressSelection,
    );

    final didLongPressSelectionStart = _longPressStrategy!.onLongPressStart(
      tapDownDocumentOffset: _getDocumentOffsetFromGlobalOffset(_globalTapDownOffset!),
    );
    if (!didLongPressSelectionStart) {
      _longPressStrategy = null;
      return;
    }

    // A long-press selection is in progress. Initially show the toolbar, but nothing else.
    _controlsController!
      ..hideCollapsedHandle()
      ..hideExpandedHandles()
      ..hideMagnifier()
      ..showToolbar();

    widget.focusNode.requestFocus();
  }

  void _onTapUp(TapUpDetails details) {
    // Stop waiting for a long-press to start.
    _tapDownLongPressTimer?.cancel();

    // Cancel any on-going long-press.
    if (_isLongPressInProgress) {
      _longPressStrategy = null;
      _magnifierGlobalOffset.value = null;
      _showAndHideEditingControlsAfterTapSelection(didTapOnExistingSelection: false);
      return;
    }

    if (_wasScrollingOnTapDown) {
      // The scrollable was scrolling when the user touched down. We expect that the
      // touch down stopped the scrolling momentum. We don't want to take any further
      // action on this touch event. The user will tap again to change the selection.
      return;
    }

    editorGesturesLog.info("Tap down on document");
    final docOffset = _getDocumentOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");

    if (widget.contentTapHandler != null && docPosition != null) {
      final result = widget.contentTapHandler!.onTap(docPosition);
      if (result == TapHandlingInstruction.halt) {
        // The custom tap handler doesn't want us to react at all
        // to the tap.
        return;
      }
    }

    bool didTapOnExistingSelection = false;
    if (docPosition != null) {
      final selection = widget.selection.value;
      didTapOnExistingSelection = selection != null &&
          selection.isCollapsed &&
          selection.extent.nodeId == docPosition.nodeId &&
          selection.extent.nodePosition.isEquivalentTo(docPosition.nodePosition);

      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        // The user tapped a non-selectable component.
        // Place the document selection at the nearest selectable node
        // to the tapped component.
        moveSelectionToNearestSelectableNode(
          editor: widget.editor,
          document: widget.document,
          documentLayoutResolver: widget.getDocumentLayout,
          currentSelection: widget.selection.value,
          startingNode: widget.document.getNodeById(docPosition.nodeId)!,
        );
      } else {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    } else {
      _clearSelection();
    }

    _showAndHideEditingControlsAfterTapSelection(didTapOnExistingSelection: didTapOnExistingSelection);

    widget.focusNode.requestFocus();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    editorGesturesLog.info("Double tap down on document");
    final docOffset = _getDocumentOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");

    if (docPosition != null && widget.contentTapHandler != null) {
      final result = widget.contentTapHandler!.onDoubleTap(docPosition);
      if (result == TapHandlingInstruction.halt) {
        // The custom tap handler doesn't want us to react at all
        // to the tap.
        return;
      }
    }

    if (docPosition != null) {
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        // The user tapped a non-selectable component, so we can't select a word.
        // The editor will remain focused and selection will remain in the nearest
        // selectable component, as set in _onTapUp.
        return;
      }

      bool didSelectContent = _selectWordAt(
        docPosition: docPosition,
        docLayout: _docLayout,
      );

      if (!didSelectContent) {
        didSelectContent = _selectBlockAt(docPosition);
      }

      if (!didSelectContent) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    } else {
      _clearSelection();
    }

    _showAndHideEditingControlsAfterTapSelection(didTapOnExistingSelection: false);

    widget.focusNode.requestFocus();
  }

  bool _selectBlockAt(DocumentPosition position) {
    if (position.nodePosition is! UpstreamDownstreamNodePosition) {
      return false;
    }

    widget.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection(
          base: DocumentPosition(
            nodeId: position.nodeId,
            nodePosition: const UpstreamDownstreamNodePosition.upstream(),
          ),
          extent: DocumentPosition(
            nodeId: position.nodeId,
            nodePosition: const UpstreamDownstreamNodePosition.downstream(),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);

    return true;
  }

  void _onTripleTapDown(TapDownDetails details) {
    editorGesturesLog.info("Triple tap down on document");
    final docOffset = _getDocumentOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");

    if (docPosition != null && widget.contentTapHandler != null) {
      final result = widget.contentTapHandler!.onTripleTap(docPosition);
      if (result == TapHandlingInstruction.halt) {
        // The custom tap handler doesn't want us to react at all
        // to the tap.
        return;
      }
    }

    if (docPosition != null) {
      // The user tapped a non-selectable component, so we can't select a paragraph.
      // The editor will remain focused and selection will remain in the nearest
      // selectable component, as set in _onTapUp.
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        return;
      }

      final didSelectParagraph = _selectParagraphAt(
        docPosition: docPosition,
        docLayout: _docLayout,
      );
      if (!didSelectParagraph) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    } else {
      _clearSelection();
    }

    _showAndHideEditingControlsAfterTapSelection(didTapOnExistingSelection: false);

    widget.focusNode.requestFocus();
  }

  void _showAndHideEditingControlsAfterTapSelection({
    required bool didTapOnExistingSelection,
  }) {
    if (widget.selection.value == null) {
      // There's no selection. Hide all controls.
      _controlsController!
        ..hideCollapsedHandle()
        ..hideExpandedHandles()
        ..hideMagnifier()
        ..hideToolbar()
        ..doNotBlinkCaret();
    } else if (!widget.selection.value!.isCollapsed) {
      _controlsController!
        ..hideCollapsedHandle()
        ..showExpandedHandles()
        ..showToolbar()
        ..hideMagnifier()
        ..doNotBlinkCaret();
    } else {
      // The selection is collapsed.
      _controlsController!
        ..showCollapsedHandle()
        // The collapsed handle should disappear after some inactivity. Start the
        // countdown (or restart an in-progress countdown).
        ..startCollapsedHandleAutoHideCountdown()
        ..hideExpandedHandles()
        ..hideMagnifier()
        ..blinkCaret();

      if (didTapOnExistingSelection) {
        // Toggle the toolbar display when the user taps on the collapsed caret,
        // or on top of an existing selection.
        _controlsController!.toggleToolbar();
      } else {
        // The user tapped somewhere else in the document. Hide the toolbar.
        _controlsController!.hideToolbar();
      }
    }
  }

  void _onPanStart(DragStartDetails details) {
    // Stop waiting for a long-press to start, if a long press isn't already in-progress.
    _tapDownLongPressTimer?.cancel();

    _globalStartDragOffset = details.globalPosition;
    _dragStartInDoc = _getDocumentOffsetFromGlobalOffset(details.globalPosition);

    // We need to record the scroll offset at the beginning of
    // a drag for the case that this interactor is embedded
    // within an ancestor Scrollable. We need to use this value
    // to calculate a scroll delta on every scroll frame to
    // account for the fact that this interactor is moving within
    // the ancestor scrollable, despite the fact that the user's
    // finger/mouse position hasn't changed.
    _dragStartScrollOffset = scrollPosition.pixels;
    _startDragPositionOffset = _dragStartInDoc!;

    if (_isLongPressInProgress) {
      _onLongPressPanStart(details);
      return;
    }

    if (widget.selection.value?.isCollapsed == true) {
      final caretPosition = widget.selection.value!.extent;
      final tapDocumentOffset = widget.getDocumentLayout().getDocumentOffsetFromAncestorOffset(_globalTapDownOffset!);
      final tapPosition = widget.getDocumentLayout().getDocumentPositionAtOffset(tapDocumentOffset);
      if(tapPosition == null){
        return;
      }
      final isTapOverCaret = caretPosition.isEquivalentTo(tapPosition);

      if (isTapOverCaret) {
        _onCaretDragPanStart(details);
        return;
      }
    }

    _scrollingDrag = scrollPosition.drag(details, () {
      // Allows receiving touches while scrolling due to scroll momentum.
      // This is needed to allow the user to stop scrolling by tapping down.
      scrollPosition.context.setIgnorePointer(false);
    });
  }

  void _onLongPressPanStart(DragStartDetails details) {
    _longPressStrategy!.onLongPressDragStart(details);

    // Tell the overlay where to put the magnifier.
    _magnifierGlobalOffset.value = details.globalPosition;

    widget.dragHandleAutoScroller.value!.startAutoScrollHandleMonitoring();

    _controlsController!
      ..hideToolbar()
      ..showMagnifier();
  }

  void _onCaretDragPanStart(DragStartDetails details) {
    _isCaretDragInProgress = true;

    // Tell the overlay where to put the magnifier.
    _magnifierGlobalOffset.value = details.globalPosition;

    widget.dragHandleAutoScroller.value!.startAutoScrollHandleMonitoring();

    _controlsController!
      ..doNotBlinkCaret()
      ..hideToolbar()
      ..showMagnifier();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _globalDragOffset = details.globalPosition;

    if (_isLongPressInProgress) {
      _onLongPressPanUpdate(details);
      return;
    }

    if (_isCaretDragInProgress) {
      _onCaretDragPanUpdate(details);
      return;
    }

    if (_scrollingDrag != null && _isScrolling) {
      // The user is trying to scroll the document. Change the scroll offset.
      _scrollingDrag!.update(details);
    }
  }

  void _onLongPressPanUpdate(DragUpdateDetails details) {
    final fingerDragDelta = _globalDragOffset! - _globalStartDragOffset!;
    final scrollDelta = _dragStartScrollOffset! - scrollPosition.pixels;
    final fingerDocumentOffset = _docLayout.getDocumentOffsetFromAncestorOffset(details.globalPosition);
    final fingerDocumentPosition = _docLayout.getDocumentPositionNearestToOffset(
      _startDragPositionOffset! + fingerDragDelta - Offset(0, scrollDelta),
    );
    _longPressStrategy!.onLongPressDragUpdate(fingerDocumentOffset, fingerDocumentPosition);
  }

  void _onCaretDragPanUpdate(DragUpdateDetails details) {
    final fingerDragDelta = _globalDragOffset! - _globalStartDragOffset!;
    final scrollDelta = _dragStartScrollOffset! - scrollPosition.pixels;
    final fingerDocumentPosition = _docLayout.getDocumentPositionNearestToOffset(
      _startDragPositionOffset! + fingerDragDelta - Offset(0, scrollDelta),
    )!;
    _selectPosition(fingerDocumentPosition);
  }

  void _updateLongPressSelection(DocumentSelection newSelection) {
    if (newSelection != widget.selection.value) {
      _select(newSelection);
      HapticFeedback.lightImpact();
    }

    // Note: this needs to happen even when the selection doesn't change, in case
    // some controls, like a magnifier, need to follower the user's finger.
    _updateOverlayControlsOnLongPressDrag();
  }

  void _updateOverlayControlsOnLongPressDrag() {
    final extentDocumentOffset = _docLayout.getRectForPosition(widget.selection.value!.extent)!.center;
    final extentGlobalOffset = _docLayout.getAncestorOffsetFromDocumentOffset(extentDocumentOffset);
    final extentInteractorOffset = (context.findRenderObject() as RenderBox).globalToLocal(extentGlobalOffset);
    final extentViewportOffset = _interactorOffsetInViewport(extentInteractorOffset);
    widget.dragHandleAutoScroller.value!.updateAutoScrollHandleMonitoring(dragEndInViewport: extentViewportOffset);

    _magnifierGlobalOffset.value = extentGlobalOffset;
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isLongPressInProgress) {
      _onLongPressEnd();
      return;
    }

    if (_isCaretDragInProgress) {
      _onCaretDragEnd();
      return;
    }

    if (_scrollingDrag != null) {
      // The user was performing a drag gesture to scroll the document.
      // End the scroll activity and let the document scrolling with momentum.
      _scrollingDrag!.end(details);
    }
  }

  void _onPanCancel() {
    if (_isLongPressInProgress) {
      _onLongPressEnd();
      return;
    }

    if (_isCaretDragInProgress) {
      _onCaretDragEnd();
      return;
    }

    if (_scrollingDrag != null) {
      // The user was performing a drag gesture to scroll the document.
      // End the drag gesture.
      _scrollingDrag!.cancel();
    }
  }

  void _onLongPressEnd() {
    _longPressStrategy!.onLongPressEnd();

    // Cancel any on-going long-press.
    _longPressStrategy = null;
    _magnifierGlobalOffset.value = null;

    widget.dragHandleAutoScroller.value!.stopAutoScrollHandleMonitoring();

    _controlsController!.hideMagnifier();
    if (!widget.selection.value!.isCollapsed) {
      _controlsController!
        ..showExpandedHandles()
        ..showToolbar();
    }
  }

  void _onCaretDragEnd() {
    _isCaretDragInProgress = false;

    _magnifierGlobalOffset.value = null;

    widget.dragHandleAutoScroller.value!.stopAutoScrollHandleMonitoring();

    _controlsController!
      ..blinkCaret()
      ..hideMagnifier();
    if (!widget.selection.value!.isCollapsed) {
      _controlsController!
        ..showExpandedHandles()
        ..showToolbar();
    }
  }

  bool _selectWordAt({
    required DocumentPosition docPosition,
    required DocumentLayout docLayout,
  }) {
    final newSelection = getWordSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      widget.editor.execute([
        ChangeSelectionRequest(
          newSelection,
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
      return true;
    } else {
      return false;
    }
  }

  bool _selectParagraphAt({
    required DocumentPosition docPosition,
    required DocumentLayout docLayout,
  }) {
    final newSelection = getParagraphSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      widget.editor.execute([
        ChangeSelectionRequest(
          newSelection,
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
      return true;
    } else {
      return false;
    }
  }

  void _selectPosition(DocumentPosition position) {
    editorGesturesLog.fine("Setting document selection to $position");
    widget.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: position,
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);
  }

  void _select(DocumentSelection newSelection) {
    widget.editor.execute([
      ChangeSelectionRequest(
        newSelection,
        SelectionChangeType.expandSelection,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);
  }

  void _clearSelection() {
    editorGesturesLog.fine("Clearing document selection");
    widget.editor.execute([
      const ClearSelectionRequest(),
      const ClearComposingRegionRequest(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final gestureSettings = MediaQuery.maybeOf(context)?.gestureSettings;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        TapSequenceGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapSequenceGestureRecognizer>(
          () => TapSequenceGestureRecognizer(),
          (TapSequenceGestureRecognizer recognizer) {
            recognizer
              ..onTapDown = _onTapDown
              ..onTapUp = _onTapUp
              ..onDoubleTapDown = _onDoubleTapDown
              ..onTripleTapDown = _onTripleTapDown
              ..gestureSettings = gestureSettings;
          },
        ),
        VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer(),
          (VerticalDragGestureRecognizer recognizer) {
            recognizer
              ..dragStartBehavior = DragStartBehavior.down
              ..onStart = _onPanStart
              ..onUpdate = _onPanUpdate
              ..onEnd = _onPanEnd
              ..onCancel = _onPanCancel
              ..gestureSettings = gestureSettings;
          },
        ),
      },
      child: widget.child,
    );
  }
}

/// Adds and removes an Android-style editor controls overlay, as dictated by an ancestor
/// [SuperEditorAndroidControlsScope].
class SuperEditorAndroidControlsOverlayManager extends StatefulWidget {
  const SuperEditorAndroidControlsOverlayManager({
    super.key,
    this.tapRegionGroupId,
    required this.document,
    required this.getDocumentLayout,
    required this.selection,
    required this.setSelection,
    required this.scrollChangeSignal,
    required this.dragHandleAutoScroller,
    this.defaultToolbarBuilder,
    this.showDebugPaint = false,
    this.child,
  });

  /// {@macro super_editor_tap_region_group_id}
  final String? tapRegionGroupId;

  final Document document;
  final DocumentLayoutResolver getDocumentLayout;
  final ValueListenable<DocumentSelection?> selection;
  final void Function(DocumentSelection?) setSelection;

  final SignalNotifier scrollChangeSignal;

  final ValueListenable<DragHandleAutoScroller?> dragHandleAutoScroller;

  final DocumentFloatingToolbarBuilder? defaultToolbarBuilder;

  /// Paints some extra visual ornamentation to help with
  /// debugging, when `true`.
  final bool showDebugPaint;

  final Widget? child;

  @override
  State<SuperEditorAndroidControlsOverlayManager> createState() => SuperEditorAndroidControlsOverlayManagerState();
}

@visibleForTesting
class SuperEditorAndroidControlsOverlayManagerState extends State<SuperEditorAndroidControlsOverlayManager> {
  final _overlayController = OverlayPortalController();

  SuperEditorAndroidControlsController? _controlsController;
  late FollowerAligner _toolbarAligner;

  // The selection bound that the user is dragging, e.g., base or extent.
  //
  // The drag selection bound varies independently from the drag handle type.
  SelectionBound? _dragHandleSelectionBound;

  // The type of handle that the user started dragging, e.g., upstream or downstream.
  //
  // The drag handle type varies independently from the drag selection bound.
  HandleType? _dragHandleType;

  final _dragHandleSelectionGlobalFocalPoint = ValueNotifier<Offset?>(null);
  final _magnifierFocalPoint = ValueNotifier<Offset?>(null);

  @override
  void initState() {
    super.initState();
    _overlayController.show();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _controlsController = SuperEditorAndroidControlsScope.rootOf(context);
    // TODO: Replace Cupertino aligner with a generic aligner because this code runs on Android.
    _toolbarAligner = CupertinoPopoverToolbarAligner();
  }

  @override
  void didUpdateWidget(SuperEditorAndroidControlsOverlayManager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.scrollChangeSignal != oldWidget.scrollChangeSignal) {
      oldWidget.scrollChangeSignal.removeListener(_onDocumentScroll);
      if (_dragHandleType != null) {
        // The user is currently dragging a handle. Listen for scroll changes.
        widget.scrollChangeSignal.addListener(_onDocumentScroll);
      }
    }
  }

  @override
  void dispose() {
    // In case we're disposed in the middle of auto-scrolling, stop auto-scrolling and
    // stop listening for document scroll changes.
    widget.dragHandleAutoScroller.value?.stopAutoScrollHandleMonitoring();
    widget.scrollChangeSignal.removeListener(_onDocumentScroll);

    super.dispose();
  }

  @visibleForTesting
  bool get wantsToDisplayToolbar => _controlsController!.shouldShowToolbar.value;

  @visibleForTesting
  bool get wantsToDisplayMagnifier => _controlsController!.shouldShowMagnifier.value;

  void _toggleToolbarOnCollapsedHandleTap() {
    _controlsController!.toggleToolbar();
  }

  void _onHandlePanStart(DragStartDetails details, HandleType handleType) {
    final selection = widget.selection.value;
    if (selection == null) {
      throw Exception("Tried to drag a collapsed Android handle when there's no selection.");
    }
    if (handleType == HandleType.collapsed && !selection.isCollapsed) {
      throw Exception("Tried to drag a collapsed Android handle but the selection is expanded.");
    }
    if (handleType != HandleType.collapsed && selection.isCollapsed) {
      throw Exception("Tried to drag an expanded Android handle but the selection is collapsed.");
    }

    final isSelectionDownstream = widget.selection.value!.hasDownstreamAffinity(widget.document);
    _dragHandleType = handleType;
    late final DocumentPosition selectionBoundPosition;
    if (isSelectionDownstream) {
      _dragHandleSelectionBound = handleType == HandleType.upstream ? SelectionBound.base : SelectionBound.extent;
      selectionBoundPosition = handleType == HandleType.upstream ? selection.base : selection.extent;
    } else {
      _dragHandleSelectionBound = handleType == HandleType.upstream ? SelectionBound.extent : SelectionBound.base;
      selectionBoundPosition = handleType == HandleType.upstream ? selection.extent : selection.base;
    }

    // Find the global offset for the center of the caret as the selection focal point.
    final documentLayout = widget.getDocumentLayout();
    // FIXME: this logic makes sense for selecting characters, but what about images? Does it make sense to set the focal point at the center of the image?
    final centerOfContentAtOffset = documentLayout.getAncestorOffsetFromDocumentOffset(
      documentLayout.getRectForPosition(selectionBoundPosition)!.center,
    );
    _dragHandleSelectionGlobalFocalPoint.value = centerOfContentAtOffset;
    _magnifierFocalPoint.value = centerOfContentAtOffset;

    // Update the controls for handle dragging.
    _controlsController!
      ..cancelCollapsedHandleAutoHideCountdown()
      ..doNotBlinkCaret()
      ..showMagnifier()
      ..hideToolbar();

    // Start auto-scrolling based on the drag-handle offset.
    widget.dragHandleAutoScroller.value?.startAutoScrollHandleMonitoring();

    // Listen for scroll changes so that we can update the selection when the user's
    // finger is standing still, but the document is moving beneath it during auto scrolling.
    widget.scrollChangeSignal.addListener(_onDocumentScroll);
  }

  void _onHandlePanUpdate(DragUpdateDetails details) {
    if (_dragHandleSelectionGlobalFocalPoint.value == null) {
      throw Exception(
          "Tried to pan an Android drag handle but the focal point is null. The focal point is set when the drag begins. This shouldn't be possible.");
    }

    // Move the selection focal point by the given delta.
    _dragHandleSelectionGlobalFocalPoint.value = _dragHandleSelectionGlobalFocalPoint.value! + details.delta;

    // Update the selection and magnifier based on the latest drag handle offset.
    _moveSelectionAndMagnifierToDragHandleOffset(dragDx: details.delta.dx);
  }

  void _onHandlePanEnd(DragEndDetails details, HandleType handleType) {
    _onHandleDragEnd(handleType);
  }

  void _onHandlePanCancel(HandleType handleType) {
    _onHandleDragEnd(handleType);
  }

  void _onHandleDragEnd(HandleType handleType) {
    _dragHandleSelectionBound = null;
    _dragHandleType = null;
    _dragHandleSelectionGlobalFocalPoint.value = null;
    _magnifierFocalPoint.value = null;

    // Start blinking the caret again, and hide the magnifier.
    _controlsController!
      ..blinkCaret()
      ..hideMagnifier();

    if (widget.selection.value?.isCollapsed == true &&
        const [HandleType.upstream, HandleType.downstream].contains(handleType)) {
      // The user dragged an expanded handle until the selection collapsed and then released the handle.
      // While the user was dragging, the expanded handles were displayed.
      // Show the collapsed.
      _controlsController!
        ..hideExpandedHandles()
        ..showCollapsedHandle();
    }

    // Stop auto-scrolling based on the drag-handle offset.
    widget.dragHandleAutoScroller.value?.stopAutoScrollHandleMonitoring();
    widget.scrollChangeSignal.removeListener(_onDocumentScroll);

    if (widget.selection.value?.isCollapsed == false) {
      // The selection is expanded, show the toolbar.
      _controlsController!.showToolbar();
    } else {
      // The selection is collapsed, start the auto-hide countdown for the handle.
      _controlsController!.startCollapsedHandleAutoHideCountdown();
    }
  }

  void _onDocumentScroll() {
    if (_dragHandleType == null) {
      // The user isn't dragging anything. We don't care that the document moved. Return.
      return;
    }

    // Update the selection based on the handle's offset in the document, now that the
    // document has scrolled.
    _moveSelectionAndMagnifierToDragHandleOffset();
  }

  void _moveSelectionAndMagnifierToDragHandleOffset({
    double dragDx = 0,
  }) {
    // Move the selection to the document position that's nearest the focal point.
    final documentLayout = widget.getDocumentLayout();
    final nearestPosition = documentLayout.getDocumentPositionNearestToOffset(
      documentLayout.getDocumentOffsetFromAncestorOffset(_dragHandleSelectionGlobalFocalPoint.value!),
    )!;

    // Move the magnifier focal point to match the drag x-offset, but always remain focused on the vertical
    // center of the line.
    final centerOfContentAtNearestPosition = documentLayout.getAncestorOffsetFromDocumentOffset(
      documentLayout.getRectForPosition(nearestPosition)!.center,
    );
    _magnifierFocalPoint.value = Offset(
      _magnifierFocalPoint.value!.dx + dragDx,
      centerOfContentAtNearestPosition.dy,
    );

    switch (_dragHandleType!) {
      case HandleType.collapsed:
        widget.setSelection(DocumentSelection.collapsed(
          position: nearestPosition,
        ));
      case HandleType.upstream:
      case HandleType.downstream:
        switch (_dragHandleSelectionBound!) {
          case SelectionBound.base:
            widget.setSelection(DocumentSelection(
              base: nearestPosition,
              extent: widget.selection.value!.extent,
            ));
          case SelectionBound.extent:
            widget.setSelection(DocumentSelection(
              base: widget.selection.value!.base,
              extent: nearestPosition,
            ));
        }
    }

    // Update the auto-scroll focal point so that the viewport scrolls if we're
    // close to the boundary.
    widget.dragHandleAutoScroller.value?.updateAutoScrollHandleMonitoring(
      dragEndInViewport: centerOfContentAtNearestPosition,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlay,
      child: widget.child ?? const SizedBox(),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return TapRegion(
      groupId: widget.tapRegionGroupId,
      child: Stack(
        children: [
          _buildMagnifierFocalPoint(),
          if (widget.showDebugPaint) //
            _buildDebugSelectionFocalPoint(),
          _buildMagnifier(),
          // Handles and toolbar are built after the magnifier so that they don't appear in the magnifier.
          _buildCollapsedHandle(),
          ..._buildExpandedHandles(),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildCollapsedHandle() {
    return ValueListenableBuilder(
      valueListenable: _controlsController!.shouldShowCollapsedHandle,
      builder: (context, shouldShow, child) {
        final selection = widget.selection.value;
        if (selection == null || !selection.isCollapsed) {
          // When the user double taps we first place a collapsed selection
          // and then an expanded selection.
          // Return a SizedBox to avoid flashing the collapsed drag handle.
          return const SizedBox();
        }

        // Note: If we pass this widget as the `child` property, it causes repeated starts and stops
        // of the pan gesture. By building it here, pan events work as expected.
        return Follower.withOffset(
          link: _controlsController!.collapsedHandleFocalPoint,
          leaderAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          child: AnimatedOpacity(
            // When the controller doesn't want the handle to be visible, hide it.
            opacity: shouldShow ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              // Don't let the handle respond to touch events when the handle shouldn't
              // be visible. This is needed because we don't remove the handle from the
              // tree, we just make it invisible. In theory, invisible widgets aren't
              // supposed to be hit-testable, but in tests I found that without this
              // explicit IgnorePointer, gestures were still being captured by this handle.
              ignoring: !shouldShow,
              child: GestureDetector(
                onTapDown: (_) {
                  // Register tap down to win gesture arena ASAP.
                },
                onTap: _toggleToolbarOnCollapsedHandleTap,
                onPanStart: (details) => _onHandlePanStart(details, HandleType.collapsed),
                onPanUpdate: _onHandlePanUpdate,
                onPanEnd: (details) => _onHandlePanEnd(details, HandleType.collapsed),
                onPanCancel: () => _onHandlePanCancel(HandleType.collapsed),
                dragStartBehavior: DragStartBehavior.down,
                child: AndroidSelectionHandle(
                  key: DocumentKeys.androidCaretHandle,
                  handleType: HandleType.collapsed,
                  color: _controlsController!.controlsColor ?? Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildExpandedHandles() {
    return [
      ValueListenableBuilder(
        valueListenable: _controlsController!.shouldShowExpandedHandles,
        builder: (context, shouldShow, child) {
          if (!shouldShow) {
            return const SizedBox();
          }

          return Follower.withOffset(
            link: _controlsController!.upstreamHandleFocalPoint,
            leaderAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topRight,
            child: GestureDetector(
              onTapDown: (_) {
                // Register tap down to win gesture arena ASAP.
              },
              onPanStart: (details) => _onHandlePanStart(details, HandleType.upstream),
              onPanUpdate: _onHandlePanUpdate,
              onPanEnd: (details) => _onHandlePanEnd(details, HandleType.upstream),
              onPanCancel: () => _onHandlePanCancel(HandleType.upstream),
              dragStartBehavior: DragStartBehavior.down,
              child: AndroidSelectionHandle(
                key: DocumentKeys.upstreamHandle,
                handleType: HandleType.upstream,
                color: _controlsController!.controlsColor ?? Theme.of(context).primaryColor,
              ),
            ),
          );
        },
      ),
      ValueListenableBuilder(
        valueListenable: _controlsController!.shouldShowExpandedHandles,
        builder: (context, shouldShow, child) {
          if (!shouldShow) {
            return const SizedBox();
          }

          return Follower.withOffset(
            link: _controlsController!.downstreamHandleFocalPoint,
            leaderAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topLeft,
            child: GestureDetector(
              onTapDown: (_) {
                // Register tap down to win gesture arena ASAP.
              },
              onPanStart: (details) => _onHandlePanStart(details, HandleType.downstream),
              onPanUpdate: _onHandlePanUpdate,
              onPanEnd: (details) => _onHandlePanEnd(details, HandleType.downstream),
              onPanCancel: () => _onHandlePanCancel(HandleType.downstream),
              dragStartBehavior: DragStartBehavior.down,
              child: AndroidSelectionHandle(
                key: DocumentKeys.downstreamHandle,
                handleType: HandleType.downstream,
                color: _controlsController!.controlsColor ?? Theme.of(context).primaryColor,
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildToolbar() {
    return ValueListenableBuilder(
      valueListenable: _controlsController!.shouldShowToolbar,
      builder: (context, shouldShow, child) {
        return shouldShow ? child! : const SizedBox();
      },
      child: Follower.withAligner(
        link: _controlsController!.toolbarFocalPoint,
        aligner: _toolbarAligner,
        boundary: ScreenFollowerBoundary(
          screenSize: MediaQuery.sizeOf(context),
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        child: _toolbarBuilder(context, DocumentKeys.mobileToolbar, _controlsController!.toolbarFocalPoint),
      ),
    );
  }

  DocumentFloatingToolbarBuilder get _toolbarBuilder {
    return _controlsController!.toolbarBuilder ?? //
        widget.defaultToolbarBuilder ??
        (_, __, ___) => const SizedBox();
  }

  Widget _buildMagnifierFocalPoint() {
    return ValueListenableBuilder(
      valueListenable: _magnifierFocalPoint,
      builder: (context, focalPoint, child) {
        if (focalPoint == null) {
          return const SizedBox();
        }

        return Positioned(
          left: focalPoint.dx,
          top: focalPoint.dy,
          width: 1,
          height: 1,
          child: Leader(
            link: _controlsController!.magnifierFocalPoint,
          ),
        );
      },
    );
  }

  Widget _buildMagnifier() {
    return ValueListenableBuilder(
      valueListenable: _controlsController!.shouldShowMagnifier,
      builder: (context, shouldShow, child) {
        return shouldShow ? child! : const SizedBox();
      },
      child: _controlsController!.magnifierBuilder != null //
          ? _controlsController!.magnifierBuilder!(
              context,
              DocumentKeys.magnifier,
              _controlsController!.magnifierFocalPoint,
            )
          : _buildDefaultMagnifier(
              context,
              DocumentKeys.magnifier,
              _controlsController!.magnifierFocalPoint,
            ),
    );
  }

  Widget _buildDefaultMagnifier(BuildContext context, Key magnifierKey, LeaderLink focalPoint) {
    return Follower.withOffset(
      link: _controlsController!.magnifierFocalPoint,
      offset: const Offset(0, -150),
      leaderAnchor: Alignment.center,
      followerAnchor: Alignment.topLeft,
      // Theoretically, we should be able to use a leaderAnchor and followerAnchor of "center"
      // and avoid the following FractionalTranslation. However, when centering the follower,
      // we don't get the expect focal point within the magnified area. It's off-center. I'm not
      // sure why that happens, but using a followerAnchor of "topLeft" and then pulling back
      // by 50% solve the problem.
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: AndroidMagnifyingGlass(
          key: magnifierKey,
          magnificationScale: 1.5,
          // In theory, the offsetFromFocalPoint should either be `-150` to match the actual
          // offset, or it should be `-150 / magnificationLevel`. Neither of those align the
          // focal point correctly. The following offset was found empirically to give the
          // desired results, no matter how high the magnification.
          offsetFromFocalPoint: const Offset(0, -58),
        ),
      ),
    );
  }

  Widget _buildDebugSelectionFocalPoint() {
    return ValueListenableBuilder(
      valueListenable: _dragHandleSelectionGlobalFocalPoint,
      builder: (context, focalPoint, child) {
        if (focalPoint == null) {
          return const SizedBox();
        }

        return Positioned(
          left: focalPoint.dx,
          top: focalPoint.dy,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -0.5),
            child: Container(
              width: 5,
              height: 5,
              color: Colors.red,
            ),
          ),
        );
      },
    );
  }
}

enum SelectionHandleType {
  collapsed,
  upstream,
  downstream,
}

enum SelectionBound {
  base,
  extent,
}
