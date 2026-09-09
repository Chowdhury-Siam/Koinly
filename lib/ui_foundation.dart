import 'dart:math' as math;
import 'dart:ui' as ui;

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

  void _press() {
    if (_pressed || widget.onTap == null || !mounted) return;
    _pressed = true;
    if (MediaQuery.of(context).disableAnimations) return;
    _scaleController.animateTo(
      widget.scale,
      duration: const Duration(milliseconds: 72),
      curve: Curves.easeOutCubic,
    );
  }

  void _release() {
    if (!_pressed || !mounted) return;
    _pressed = false;
    if (MediaQuery.of(context).disableAnimations) {
      _scaleController.value = 1;
      return;
    }
    _scaleController.animateWith(
      SpringSimulation(AppMotion.pressSpring, _scaleController.value, 1, 0),
    );
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
/// stealing its gesture. This is useful for Material buttons/FABs.
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

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    if (MediaQuery.of(context).disableAnimations) return;
    _scaleController.animateTo(widget.scale, duration: const Duration(milliseconds: 70), curve: Curves.easeOutCubic);
  }

  void _up(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    if (MediaQuery.of(context).disableAnimations) {
      _scaleController.value = 1;
      return;
    }
    _scaleController.animateWith(SpringSimulation(AppMotion.pressSpring, _scaleController.value, 1, 0));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.of(context).disableAnimations) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedBuilder(
        animation: _scaleController,
        child: widget.child,
        builder: (context, child) => Transform.scale(scale: _scaleController.value, child: child),
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

  void _highlight(bool value) {
    if (!mounted || MediaQuery.of(context).disableAnimations) return;
    if (value) {
      _scaleController.animateTo(widget.scale, duration: const Duration(milliseconds: 72), curve: Curves.easeOutCubic);
    } else {
      _scaleController.animateWith(SpringSimulation(AppMotion.surfaceSpring, _scaleController.value, 1, 0));
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
    return AnimatedBuilder(
      animation: _scaleController,
      child: ink,
      builder: (context, child) => Transform.scale(scale: _scaleController.value, child: child),
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
    if (kIsDesktopApp) return const RangeMaintainingScrollPhysics(parent: ClampingScrollPhysics());
    return const KoinlyMobileScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // Keep desktop scrolling native. Intercepting pointer-wheel signals and
    // repeatedly calling animateTo/animateToItem caused queued animations,
    // overshoot, and visible jumps with fast mouse-wheel or touchpad input.
    // Flutter's normal scroll pipeline is smoother and preserves precise
    // trackpad deltas while FixedExtentScrollPhysics still snaps wheel pickers.
    return child;
  }
}

ScrollPhysics optimizedScrollPhysics(BuildContext context) {
  if (kIsDesktopApp) return const RangeMaintainingScrollPhysics(parent: ClampingScrollPhysics());
  return const KoinlyMobileScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

/// Mobile lists keep Android's precise fling behavior while adding a restrained
/// elastic edge response. Desktop remains clamped for mouse/trackpad precision.
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
