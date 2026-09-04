import 'package:flutter/material.dart';

/// PixelPlayer-inspired visual primitives for Koinly.
///
/// These components intentionally stay cheap to render: no BackdropFilter,
/// no continuously running decorative controllers, no large blur shadows, and
/// no layout-changing animations. Motion is limited to short opacity/color/
/// transform transitions so low-end Android devices and desktop builds remain
/// stable.
class KoinlyPixelTokens {
  const KoinlyPixelTokens._();

  static const Color darkBackground = Color(0xFF140E12);
  static const Color darkSurface = Color(0xFF20161C);
  static const Color darkSurfaceRaised = Color(0xFF2A1C24);
  static const Color darkSurfaceHighest = Color(0xFF35242E);
  static const Color lightBackground = Color(0xFFFFF8FB);
  static const Color lightSurface = Color(0xFFFFFBFD);
  static const Color lightSurfaceRaised = Color(0xFFF8EAF0);
  static const Color lightSurfaceHighest = Color(0xFFF1DDE6);

  static const Color pink = Color(0xFFF0A6C5);
  static const Color lavender = Color(0xFFD6B9FF);
  static const Color cyan = Color(0xFF7EDBE7);
  static const Color green = Color(0xFF83D6A9);
  static const Color red = Color(0xFFFF8D9B);
  static const Color amber = Color(0xFFF2C879);

  static const Duration quick = Duration(milliseconds: 110);
  static const Duration normal = Duration(milliseconds: 170);
  static const Curve curve = Cubic(0.2, 0.0, 0.0, 1.0);

  static BorderRadius radius(double value) => BorderRadius.circular(value);
  static const BorderRadius radiusSmall = BorderRadius.all(Radius.circular(14));
  static const BorderRadius radiusMedium = BorderRadius.all(Radius.circular(19));
  static const BorderRadius radiusLarge = BorderRadius.all(Radius.circular(26));
  static const BorderRadius radiusXL = BorderRadius.all(Radius.circular(34));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

class PixelFinanceBackground extends StatelessWidget {
  const PixelFinanceBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? KoinlyPixelTokens.darkBackground : KoinlyPixelTokens.lightBackground,
      child: child,
    );
  }
}

class PixelFinanceSurface extends StatelessWidget {
  const PixelFinanceSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = 20,
    this.onTap,
    this.border = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double radius;
  final VoidCallback? onTap;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final resolvedColor = color ?? (dark ? KoinlyPixelTokens.darkSurface : KoinlyPixelTokens.lightSurface);
    final decoration = BoxDecoration(
      color: resolvedColor,
      borderRadius: BorderRadius.circular(radius),
      border: border ? Border.all(color: scheme.outlineVariant.withOpacity(dark ? .20 : .42)) : null,
    );
    final body = Padding(padding: padding, child: child);
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: body);
    }
    return Material(
      color: resolvedColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: border ? BorderSide(color: scheme.outlineVariant.withOpacity(dark ? .20 : .42)) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}

class PixelFinanceHeader extends StatelessWidget {
  const PixelFinanceHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = false,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;
    final compact = width < 420;
    return Padding(
      padding: EdgeInsets.fromLTRB(desktop ? 28 : 18, desktop ? 20 : 12, desktop ? 28 : 14, desktop ? 12 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBack) ...[
            PixelRoundAction(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
            SizedBox(width: compact ? 10 : 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (desktop ? theme.textTheme.headlineMedium : theme.textTheme.headlineSmall)?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.8,
                    height: 1.0,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 8),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        ],
      ),
    );
  }
}

class PixelRoundAction extends StatelessWidget {
  const PixelRoundAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        backgroundColor: selected
            ? scheme.primaryContainer
            : (dark ? KoinlyPixelTokens.darkSurface : KoinlyPixelTokens.lightSurfaceRaised),
        foregroundColor: selected ? scheme.onPrimaryContainer : scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    return button;
  }
}

class PixelSectionLabel extends StatelessWidget {
  const PixelSectionLabel(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -.25,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class PixelPill extends StatelessWidget {
  const PixelPill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? scheme.primaryContainer
        : (dark ? KoinlyPixelTokens.darkSurfaceRaised : KoinlyPixelTokens.lightSurfaceRaised);
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: compact ? 16 : 18, color: fg),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
    if (onTap == null) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 15, vertical: compact ? 8 : 10),
        decoration: BoxDecoration(color: bg, borderRadius: KoinlyPixelTokens.pill),
        child: content,
      );
    }
    return Material(
      color: bg,
      borderRadius: KoinlyPixelTokens.pill,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 15, vertical: compact ? 8 : 10),
          child: content,
        ),
      ),
    );
  }
}

class PixelMetricBlock extends StatelessWidget {
  const PixelMetricBlock({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return PixelFinanceSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PixelEmptyState extends StatelessWidget {
  const PixelEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PixelFinanceSurface(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(21)),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
          if (action != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: action, child: Text(actionLabel ?? 'Continue')),
          ],
        ],
      ),
    );
  }
}
