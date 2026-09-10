import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';

class AppBreakpoints {
  const AppBreakpoints._();

  static const double compact = 360;
  static const double medium = 600;
  static const double expanded = 900;
  static const double large = 1180;

  static bool isSmall(BuildContext context) => MediaQuery.sizeOf(context).width < compact;
  static bool isMedium(BuildContext context) => MediaQuery.sizeOf(context).width >= medium;
  static bool isExpanded(BuildContext context) => MediaQuery.sizeOf(context).width >= expanded;
  static bool isLarge(BuildContext context) => MediaQuery.sizeOf(context).width >= large;
}

class AppMotion {
  const AppMotion._();

  // Short enough to keep finance workflows fast, but long enough for motion to
  // be perceived instead of feeling like an abrupt state swap.
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 190);
  static const Duration slow = Duration(milliseconds: 300);

  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  // Used by implicit animations where a full physics simulation is not
  // possible. The overshoot is deliberately small so Koinly still feels like
  // a finance app rather than a playful game UI.
  static const Curve spring = Cubic(0.18, 0.90, 0.28, 1.12);

  // Underdamped just enough to give press/release interactions a soft settle.
  static const SpringDescription pressSpring = SpringDescription(
    mass: 0.72,
    stiffness: 520,
    damping: 30,
  );

  static const SpringDescription surfaceSpring = SpringDescription(
    mass: 0.82,
    stiffness: 390,
    damping: 27,
  );

  static const SpringDescription edgeSpring = SpringDescription(
    mass: 0.78,
    stiffness: 430,
    damping: 30,
  );

  static Future<void> selectionHaptic(BuildContext context) async {
    if (MediaQuery.of(context).disableAnimations) return;
    await HapticFeedback.selectionClick();
  }

  static Future<void> actionHaptic(BuildContext context) async {
    if (MediaQuery.of(context).disableAnimations) return;
    await HapticFeedback.lightImpact();
  }
}

class AppShapes {
  const AppShapes._();

  static BorderRadius extraSmall = BorderRadius.circular(12);
  static BorderRadius small = BorderRadius.circular(16);
  static BorderRadius medium = BorderRadius.circular(20);
  static BorderRadius large = BorderRadius.circular(24);
  static BorderRadius extraLarge = BorderRadius.circular(30);
  static BorderRadius dialog = BorderRadius.circular(32);
  static BorderRadius full = BorderRadius.circular(999);

  static RoundedRectangleBorder squircle(double radius) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
}

class KoinlyPageTransitionsBuilder extends PageTransitionsBuilder {
  const KoinlyPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst || MediaQuery.of(context).disableAnimations) return child;

    final primary = CurvedAnimation(
      parent: animation,
      curve: AppMotion.emphasized,
      reverseCurve: AppMotion.emphasizedAccelerate,
    );
    final fade = Tween<double>(begin: 0, end: 1).animate(primary);
    final slide = Tween<Offset>(
      begin: const Offset(.026, .008),
      end: Offset.zero,
    ).animate(primary);
    final scale = Tween<double>(begin: .988, end: 1).animate(primary);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(scale: scale, child: child),
      ),
    );
  }
}

/// A spring-backed press surface for custom controls that own their tap.
class MotionPressable extends StatefulWidget {
  const MotionPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.scale = .972,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double scale;
  final bool haptic;

  @override
  State<MotionPressable> createState() => _MotionPressableState();
}

class _MotionPressableState extends State<MotionPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  bool _pressed = false;
  bool _hovered = false;

  double get _restScale => kIsDesktopApp && _hovered ? 1.008 : 1.0;
  double get _pressedScale => kIsDesktopApp ? math.min(widget.scale, .962) : widget.scale;

  void _animateTo(double target, {Duration duration = const Duration(milliseconds: 72)}) {
    if (!mounted || MediaQuery.of(context).disableAnimations) return;
    _scaleController.animateTo(target, duration: duration, curve: Curves.easeOutCubic);
  }

  void _springToRest() {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _scaleController.value = 1;
      return;
    }
    _scaleController.animateWith(
      SpringSimulation(AppMotion.pressSpring, _scaleController.value, _restScale, 0),
    );
  }

  void _press() {
    if (_pressed || widget.onTap == null || !mounted) return;
    _pressed = true;
    _animateTo(_pressedScale, duration: const Duration(milliseconds: 66));
  }

  void _release() {
    if (!_pressed || !mounted) return;
    _pressed = false;
    _springToRest();
  }

  void _hover(bool value) {
    if (!kIsDesktopApp || _hovered == value || !mounted) return;
    _hovered = value;
    if (_pressed) return;
    if (value) {
      _animateTo(_restScale, duration: const Duration(milliseconds: 105));
    } else {
      _springToRest();
    }
  }

  void _tap() {
    if (widget.haptic) AppMotion.selectionHaptic(context);
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? AppShapes.large;
    final clippedChild = ClipRRect(borderRadius: radius, child: widget.child);
    if (widget.onTap == null) return clippedChild;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(),
        onTapCancel: _release,
        onTapUp: (_) => _release(),
        onTap: _tap,
        child: MediaQuery.of(context).disableAnimations
            ? clippedChild
            : AnimatedBuilder(
                animation: _scaleController,
                child: clippedChild,
                builder: (context, child) => Transform.scale(
                  scale: _scaleController.value,
                  alignment: Alignment.center,
                  child: child,
                ),
              ),
      ),
    );
  }
}

/// Adds elastic press feedback around an already-interactive child without
/// stealing its gesture. This is useful for Material buttons/FABs. On desktop
/// the same spring is driven by mouse press/release and a very small hover lift
/// so the interaction remains visible even when a mouse click is brief.
class MotionTouchFeedback extends StatefulWidget {
  const MotionTouchFeedback({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = .972,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<MotionTouchFeedback> createState() => _MotionTouchFeedbackState();
}

class _MotionTouchFeedbackState extends State<MotionTouchFeedback> with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController = AnimationController.unbounded(vsync: this, value: 1);
  int? _pointer;
  bool _hovered = false;

  double get _restScale => kIsDesktopApp && _hovered ? 1.008 : 1.0;
  double get _pressedScale => kIsDesktopApp ? math.min(widget.scale, .962) : widget.scale;

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    if (MediaQuery.of(context).disableAnimations) return;
    _scaleController.animateTo(
      _pressedScale,
      duration: const Duration(milliseconds: 64),
      curve: Curves.easeOutCubic,
    );
  }

  void _up(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _springToRest();
  }

  void _hover(bool value) {
    if (!kIsDesktopApp || _hovered == value || !mounted) return;
    _hovered = value;
    if (_pointer != null || MediaQuery.of(context).disableAnimations) return;
    if (value) {
      _scaleController.animateTo(
        _restScale,
        duration: const Duration(milliseconds: 105),
        curve: Curves.easeOutCubic,
      );
    } else {
      _springToRest();
    }
  }

  void _springToRest() {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _scaleController.value = 1;
      return;
    }
    _scaleController.animateWith(
      SpringSimulation(AppMotion.pressSpring, _scaleController.value, _restScale, 0),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.of(context).disableAnimations) return widget.child;
    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedBuilder(
          animation: _scaleController,
          child: widget.child,
          builder: (context, child) => Transform.scale(
            scale: _scaleController.value,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// InkWell with the same ripple semantics plus a spring-backed scale response.
/// Kept intentionally small so it can replace ordinary tappable card/list
/// surfaces without changing their layout or hit targets.
class MotionInkWell extends StatefulWidget {
  const MotionInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.scale = .982,
    this.enableFeedback = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final double scale;
  final bool enableFeedback;

  @override
  State<MotionInkWell> createState() => _MotionInkWellState();
}

class _MotionInkWellState extends State<MotionInkWell> with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController = AnimationController.unbounded(vsync: this, value: 1);
  int? _pointer;
  bool _hovered = false;

  double get _restScale => kIsDesktopApp && _hovered ? 1.006 : 1.0;
  double get _pressedScale => kIsDesktopApp ? math.min(widget.scale, .968) : widget.scale;

  void _press() {
    if (!mounted || MediaQuery.of(context).disableAnimations) return;
    _scaleController.animateTo(
      _pressedScale,
      duration: const Duration(milliseconds: 66),
      curve: Curves.easeOutCubic,
    );
  }

  void _release() {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _scaleController.value = 1;
      return;
    }
    _scaleController.animateWith(
      SpringSimulation(AppMotion.surfaceSpring, _scaleController.value, _restScale, 0),
    );
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _press();
  }

  void _pointerUp(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _release();
  }

  void _highlight(bool value) {
    // InkWell still drives keyboard activation (Enter/Space). Pointer presses
    // are handled by Listener so mouse input gets the exact same spring path.
    if (_pointer != null) return;
    if (value) {
      _press();
    } else {
      _release();
    }
  }

  void _hover(bool value) {
    if (!kIsDesktopApp || _hovered == value || !mounted) return;
    _hovered = value;
    if (_pointer != null || MediaQuery.of(context).disableAnimations) return;
    if (value) {
      _scaleController.animateTo(
        _restScale,
        duration: const Duration(milliseconds: 105),
        curve: Curves.easeOutCubic,
      );
    } else {
      _release();
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = InkWell(
      borderRadius: widget.borderRadius,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      enableFeedback: widget.enableFeedback,
      onHighlightChanged: _highlight,
      child: widget.child,
    );
    if (widget.onTap == null && widget.onLongPress == null) return ink;
    if (MediaQuery.of(context).disableAnimations) return ink;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _pointerDown,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: AnimatedBuilder(
          animation: _scaleController,
          child: ink,
          builder: (context, child) => Transform.scale(
            scale: _scaleController.value,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

class KoinlyScrollBehavior extends MaterialScrollBehavior {
  const KoinlyScrollBehavior();

  @override
  Set<ui.PointerDeviceKind> get dragDevices => const {
        ui.PointerDeviceKind.touch,
        ui.PointerDeviceKind.mouse,
        ui.PointerDeviceKind.trackpad,
        ui.PointerDeviceKind.stylus,
        ui.PointerDeviceKind.unknown,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (kIsDesktopApp) return const KoinlyDesktopScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    return const KoinlyMobileScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // Keep the actual desktop scroll offset fully native. A lightweight visual
    // edge spring is layered on top so mouse-wheel input also feels elastic at
    // the top/bottom without queuing animateTo calls or altering wheel deltas.
    if (kIsDesktopApp) return _DesktopElasticScrollFeedback(child: child);
    return child;
  }
}

class _DesktopElasticScrollFeedback extends StatefulWidget {
  const _DesktopElasticScrollFeedback({required this.child});

  final Widget child;

  @override
  State<_DesktopElasticScrollFeedback> createState() => _DesktopElasticScrollFeedbackState();
}

class _DesktopElasticScrollFeedbackState extends State<_DesktopElasticScrollFeedback> with SingleTickerProviderStateMixin {
  late final AnimationController _offsetController = AnimationController.unbounded(vsync: this, value: 0);
  Axis _axis = Axis.vertical;
  double _pixels = 0;
  double _minExtent = 0;
  double _maxExtent = 0;
  bool _hasMetrics = false;

  void _captureMetrics(ScrollMetrics metrics) {
    _axis = axisDirectionToAxis(metrics.axisDirection);
    _pixels = metrics.pixels;
    _minExtent = metrics.minScrollExtent;
    _maxExtent = metrics.maxScrollExtent;
    _hasMetrics = true;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0) _captureMetrics(notification.metrics);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0) _captureMetrics(notification.metrics);
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!_hasMetrics || event is! PointerScrollEvent || MediaQuery.of(context).disableAnimations) return;
    final delta = _axis == Axis.vertical ? event.scrollDelta.dy : event.scrollDelta.dx;
    if (delta == 0) return;

    const tolerance = .75;
    final atStart = _pixels <= _minExtent + tolerance;
    final atEnd = _pixels >= _maxExtent - tolerance;
    final pushesPastStart = atStart && delta < 0;
    final pushesPastEnd = atEnd && delta > 0;
    if (!pushesPastStart && !pushesPastEnd) return;

    final direction = pushesPastStart ? 1.0 : -1.0;
    final impulse = (delta.abs() / 70.0).clamp(.20, 1.0) * 7.0 * direction;
    final next = (_offsetController.value + impulse).clamp(-10.0, 10.0).toDouble();
    _offsetController.value = next;
    _offsetController.animateWith(SpringSimulation(AppMotion.edgeSpring, next, 0, 0));
  }

  @override
  void dispose() {
    _offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _onPointerSignal,
          child: AnimatedBuilder(
            animation: _offsetController,
            child: widget.child,
            builder: (context, child) {
              final offset = _axis == Axis.vertical
                  ? Offset(0, _offsetController.value)
                  : Offset(_offsetController.value, 0);
              return Transform.translate(offset: offset, child: child);
            },
          ),
        ),
      ),
    );
  }
}

ScrollPhysics optimizedScrollPhysics(BuildContext context) {
  if (kIsDesktopApp) return const KoinlyDesktopScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  return const KoinlyMobileScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

/// Desktop keeps Flutter's native mouse-wheel/trackpad pipeline, but uses
/// bouncing boundary physics so reaching the top/bottom has the same restrained
/// elastic response as touch. No pointer-wheel animation queue is introduced.
class KoinlyDesktopScrollPhysics extends BouncingScrollPhysics {
  const KoinlyDesktopScrollPhysics({super.parent});

  @override
  KoinlyDesktopScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return KoinlyDesktopScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 2.0;

  @override
  double get minFlingVelocity => 20;

  @override
  double carriedMomentum(double existingVelocity) {
    final boost = (0.00045 * math.pow(existingVelocity.abs(), 1.88)).toDouble();
    return existingVelocity.sign * math.min<double>(boost, 22000.0);
  }
}

/// Mobile lists keep Android's precise fling behavior while adding a restrained
/// elastic edge response.
class KoinlyMobileScrollPhysics extends BouncingScrollPhysics {
  const KoinlyMobileScrollPhysics({super.parent});

  @override
  KoinlyMobileScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return KoinlyMobileScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 3.5;

  @override
  double get minFlingVelocity => 30;

  @override
  double carriedMomentum(double existingVelocity) {
    final boost = (0.000816 * math.pow(existingVelocity.abs(), 1.967)).toDouble();
    return existingVelocity.sign * math.min<double>(boost, 40000.0);
  }
}
