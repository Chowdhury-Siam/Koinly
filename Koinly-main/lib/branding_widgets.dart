import 'package:flutter/material.dart';

import 'app_config.dart';
import 'ui_foundation.dart';

/// Static Koinly app icon — renders the bundled `app_icon.png` with rounded
/// corners and a soft brand-colored glow.
class KoinlyAppIcon extends StatelessWidget {
  const KoinlyAppIcon({super.key, this.size = 88, this.borderRadius});

  final double size;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? size * .28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: kSleekAccent.withOpacity(.22),
            blurRadius: size * .24,
            offset: Offset(0, size * .10),
          ),
          BoxShadow(
            color: kSleekAccent3.withOpacity(.16),
            blurRadius: size * .32,
            offset: Offset(0, size * .04),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/icons/app_icon.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => _KoinlyLogoGlyph(
            size: size,
            borderRadius: radius,
          ),
        ),
      ),
    );
  }
}

/// Animated Koinly logo used by the splash & onboarding. Builds the iconic "K"
/// monogram from three gradient-filled rounded bars that animate in with a
/// spring overshoot, plus a soft glow halo that pulses.
class KoinlyAnimatedLogo extends StatefulWidget {
  const KoinlyAnimatedLogo({
    super.key,
    this.size = 120,
    this.enableGlow = true,
    this.autoPlay = true,
  });

  final double size;
  final bool enableGlow;
  final bool autoPlay;

  @override
  State<KoinlyAnimatedLogo> createState() => _KoinlyAnimatedLogoState();
}

class _KoinlyAnimatedLogoState extends State<KoinlyAnimatedLogo>
    with TickerProviderStateMixin {
  late final AnimationController _barController;
  late final AnimationController _glowController;
  late final Animation<double> _bar1;
  late final Animation<double> _bar2;
  late final Animation<double> _bar3;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _bar1 = CurvedAnimation(
      parent: _barController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
    );
    _bar2 = CurvedAnimation(
      parent: _barController,
      curve: const Interval(0.12, 0.7, curve: Curves.easeOutBack),
    );
    _bar3 = CurvedAnimation(
      parent: _barController,
      curve: const Interval(0.24, 0.85, curve: Curves.easeOutBack),
    );
    _glow = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    if (widget.autoPlay) {
      _barController.forward();
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _barController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow halo.
          if (widget.enableGlow)
            AnimatedBuilder(
              animation: _glow,
              builder: (context, _) {
                return Container(
                  width: size * 1.4,
                  height: size * 1.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        kSleekAccent.withOpacity(0.32 * _glow.value),
                        kSleekAccent3.withOpacity(0.18 * _glow.value),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                );
              },
            ),
          // "K" monogram.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * .28),
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1B1419)
                  : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.18),
                  blurRadius: size * .18,
                  offset: Offset(0, size * .08),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * .28),
              child: CustomPaint(
                size: Size.square(size),
                painter: _KMonogramPainter(
                  bar1: _bar1.value,
                  bar2: _bar2.value,
                  bar3: _bar3.value,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KMonogramPainter extends CustomPainter {
  _KMonogramPainter({
    required this.bar1,
    required this.bar2,
    required this.bar3,
  });

  final double bar1;
  final double bar2;
  final double bar3;

  @override
  void paint(Canvas canvas, Size size) {
    final padding = size.width * 0.22;
    final barWidth = size.width * 0.16;
    final barRadius = Radius.circular(barWidth / 2);

    // Bar 1 — vertical, pink → red gradient (left side of the K).
    final bar1Height = (size.height - padding * 2) * bar1;
    if (bar1Height > 0) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          padding,
          size.height - padding - bar1Height,
          barWidth,
          bar1Height,
        ),
        barRadius,
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFFF4D6D), Color(0xFFFF2A2A)],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }

    // Bar 2 — upper-right diagonal, yellow → orange.
    final bar2Progress = bar2;
    if (bar2Progress > 0) {
      canvas.save();
      final pivot = Offset(
        padding + barWidth * 0.5,
        size.height * 0.5,
      );
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(-0.62); // ~ -36°
      final fullLength = (size.width - padding * 1.6) * 0.95;
      final length = fullLength * bar2Progress;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          -barWidth / 2,
          length,
          barWidth,
        ),
        barRadius,
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Color(0xFFFFD23F), Color(0xFFFF8A3D)],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
      canvas.restore();
    }

    // Bar 3 — lower-right diagonal, green → cyan (matches logo).
    final bar3Progress = bar3;
    if (bar3Progress > 0) {
      canvas.save();
      final pivot = Offset(
        padding + barWidth * 0.5,
        size.height * 0.5,
      );
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(0.62); // ~ +36°
      final fullLength = (size.width - padding * 1.6) * 0.95;
      final length = fullLength * bar3Progress;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          -barWidth / 2,
          length,
          barWidth,
        ),
        barRadius,
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Color(0xFF20C997), Color(0xFF3FA9F5)],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _KMonogramPainter oldDelegate) =>
      oldDelegate.bar1 != bar1 ||
      oldDelegate.bar2 != bar2 ||
      oldDelegate.bar3 != bar3;
}

/// Fallback painted logo used when the asset is missing.
class _KoinlyLogoGlyph extends StatelessWidget {
  const _KoinlyLogoGlyph({required this.size, required this.borderRadius});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: kKoinlyBrandGradientLg(),
      ),
      child: const Icon(Icons.account_balance_wallet_rounded,
          color: Colors.white),
    );
  }
}
