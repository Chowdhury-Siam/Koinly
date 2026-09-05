import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

/// Premium motion tokens — tuned for a confident, cinematic feel without ever
/// feeling sluggish. All durations are deliberately short on mobile so the UI
/// still snaps when the user is in a hurry.
class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration splash = Duration(milliseconds: 1100);

  // Material 3 emphasized curves — preserved for compatibility.
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  // Premium springs — used by hero animations, dock tap, popup transitions.
  static const Curve spring = Cubic(0.34, 1.56, 0.64, 1.0); // back-overshoot
  static const Curve springSoft = Curves.easeOutCubic;
  static const Curve springSnap = Cubic(0.16, 1.0, 0.3, 1.0); // "out expo" feel
  static const Curve ripple = Cubic(0.4, 0.0, 0.2, 1.0);
}

class AppShapes {
  const AppShapes._();

  static BorderRadius extraSmall = BorderRadius.circular(14);
  static BorderRadius small = BorderRadius.circular(18);
  static BorderRadius medium = BorderRadius.circular(22);
  static BorderRadius large = BorderRadius.circular(28);
  static BorderRadius extraLarge = BorderRadius.circular(34);
  static BorderRadius dialog = BorderRadius.circular(36);
  static BorderRadius full = BorderRadius.circular(999);

  static RoundedRectangleBorder squircle(double radius) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
}

/// Page transition — subtle scale + fade + slide-up. Feels like iOS push
/// without the platform lock-in.
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
    if (route.isFirst) return child;
    if (MediaQuery.of(context).disableAnimations) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.emphasized,
      reverseCurve: AppMotion.emphasizedAccelerate,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

/// Tap → scale-down with a spring back. Now with a haptic ping on tap.
class MotionPressable extends StatefulWidget {
  const MotionPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.scale = .97,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double scale;
  final bool haptic;

  @override
  State<MotionPressable> createState() => _MotionPressableState();
}

class _MotionPressableState extends State<MotionPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
      reverseDuration: const Duration(milliseconds: 280),
    );
    _scale = Tween<double>(begin: 1.0, end: widget.scale).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.springSoft),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (!mounted) return;
    if (value) {
      _controller.forward();
      if (widget.haptic) HapticFeedback.selectionClick();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? AppShapes.large;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final clippedChild = ClipRRect(borderRadius: radius, child: widget.child);
    return MouseRegion(
      cursor:
          widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
        onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
        onTap: widget.onTap,
        child: reducedMotion
            ? clippedChild
            : AnimatedBuilder(
                animation: _scale,
                builder: (context, child) =>
                    Transform.scale(scale: _scale.value, child: child),
                child: clippedChild,
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
    if (kIsDesktopApp) {
      return const RangeMaintainingScrollPhysics(parent: ClampingScrollPhysics());
    }
    return const KoinlyMobileScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

ScrollPhysics optimizedScrollPhysics(BuildContext context) {
  if (kIsDesktopApp) {
    return const RangeMaintainingScrollPhysics(parent: ClampingScrollPhysics());
  }
  return const KoinlyMobileScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

class KoinlyMobileScrollPhysics extends ClampingScrollPhysics {
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
    final boost =
        (0.000816 * math.pow(existingVelocity.abs(), 1.967)).toDouble();
    return existingVelocity.sign * math.min<double>(boost, 40000.0);
  }
}

// -----------------------------------------------------------------------------
// Premium reusable helpers used by the redesigned widgets below.
// -----------------------------------------------------------------------------

/// Linear brand gradient (coral → tangerine → amber). Direction is configurable.
LinearGradient kKoinlyBrandGradientLg({
  Alignment begin = Alignment.topLeft,
  Alignment end = Alignment.bottomRight,
  List<double>? stops,
}) {
  return LinearGradient(
    begin: begin,
    end: end,
    colors: kKoinlyBrandGradient,
    stops: stops,
  );
}

/// Soft brand-tinted glow used behind hero cards & the splash logo.
List<BoxShadow> kKoinlyBrandGlow({
  double opacity = 0.35,
  double blurRadius = 36,
  Offset offset = const Offset(0, 18),
}) {
  return [
    BoxShadow(
      color: kSleekAccent.withOpacity(opacity),
      blurRadius: blurRadius,
      offset: offset,
    ),
    BoxShadow(
      color: kSleekAccent3.withOpacity(opacity * 0.55),
      blurRadius: blurRadius * 1.2,
      offset: Offset(offset.dx * 0.6, offset.dy * 0.6),
    ),
  ];
}
