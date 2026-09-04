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

class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 110);
  static const Duration medium = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 260);

  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Curve spring = Curves.easeOutCubic;
}

class AppShapes {
  const AppShapes._();

  static BorderRadius extraSmall = BorderRadius.circular(10);
  static BorderRadius small = BorderRadius.circular(14);
  static BorderRadius medium = BorderRadius.circular(18);
  static BorderRadius large = BorderRadius.circular(24);
  static BorderRadius extraLarge = BorderRadius.circular(30);
  static BorderRadius dialog = BorderRadius.circular(28);
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
    if (route.isFirst) return child;
    if (MediaQuery.of(context).disableAnimations) return child;
    final fade = CurvedAnimation(parent: animation, curve: AppMotion.standard, reverseCurve: AppMotion.emphasizedAccelerate);
    final offset = Tween<Offset>(begin: const Offset(.028, 0), end: Offset.zero).animate(fade);
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: offset, child: child),
    );
  }
}

class MotionPressable extends StatefulWidget {
  const MotionPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.scale = .975,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double scale;

  @override
  State<MotionPressable> createState() => _MotionPressableState();
}

class _MotionPressableState extends State<MotionPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? AppShapes.large;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final clippedChild = ClipRRect(borderRadius: radius, child: widget.child);
    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
        onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
        onTap: widget.onTap,
        child: reducedMotion
            ? clippedChild
            : AnimatedScale(
                duration: AppMotion.fast,
                curve: _pressed ? Curves.easeOutCubic : AppMotion.spring,
                scale: _pressed ? widget.scale : 1,
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
    final boost = (0.000816 * math.pow(existingVelocity.abs(), 1.967)).toDouble();
    return existingVelocity.sign * math.min<double>(boost, 40000.0);
  }
}
