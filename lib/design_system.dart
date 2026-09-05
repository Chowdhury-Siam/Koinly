import 'package:flutter/material.dart';

import 'app_config.dart';
import 'ui_foundation.dart';

/// Reference palette: ink surfaces, hairline borders and a warm brand accent.
/// Shared by every route, editor, picker and dialog; no data dependencies.
class KoinlyDesign {
  const KoinlyDesign._();

  static const brandGradient = LinearGradient(
    colors: [Color(0xFFFF2D68), Color(0xFFFF7A00), Color(0xFFFFC900)],
    stops: [0, .55, 1],
  );

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF131011) : Colors.white;
    final background = dark ? const Color(0xFF09090B) : const Color(0xFFFCFAFA);
    final text = dark ? const Color(0xFFF7F4F5) : const Color(0xFF17161B);
    final muted = dark ? const Color(0xFFA1A1AA) : const Color(0xFF62616C);
    final border = dark ? const Color(0xFF292427) : const Color(0xFFE9E5E8);
    final raised = dark ? const Color(0xFF201B1E) : const Color(0xFFF5F3F4);
    final scheme = ColorScheme.fromSeed(seedColor: kSleekAccent, brightness: brightness).copyWith(
      primary: kSleekAccent, onPrimary: Colors.white,
      primaryContainer: dark ? const Color(0xFF32101E) : const Color(0xFFFFE4ED),
      onPrimaryContainer: text,
      secondary: dark ? const Color(0xFF00CD78) : const Color(0xFF00894E),
      tertiary: const Color(0xFFFFA000),
      surface: surface, onSurface: text, onSurfaceVariant: muted,
      surfaceContainerLowest: background, surfaceContainerLow: surface,
      surfaceContainer: surface, surfaceContainerHigh: raised,
      surfaceContainerHighest: dark ? const Color(0xFF30292D) : const Color(0xFFEDE9EC),
      outline: muted, outlineVariant: border, surfaceTint: Colors.transparent,
      error: dark ? const Color(0xFFFF758C) : const Color(0xFFBE2344),
    );
    final typography = Typography.material2021().black.apply(
      fontFamily: 'Roboto', bodyColor: text, displayColor: text,
    ).copyWith(
      displaySmall: TextStyle(fontSize: 44, height: 1.08, fontWeight: FontWeight.w700, letterSpacing: -1.8, color: text),
      headlineMedium: TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -.8, color: text),
      headlineSmall: TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -.5, color: text),
      titleLarge: TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -.4, color: text),
      titleMedium: TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: -.15, color: text),
      titleSmall: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: text),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: text),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: text),
      bodySmall: TextStyle(fontSize: 12, height: 1.45, color: muted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text),
      labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .3, color: muted),
      labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: .5, color: muted),
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    const transitions = KoinlyPageTransitionsBuilder();
    return ThemeData(
      useMaterial3: true, brightness: brightness, colorScheme: scheme,
      scaffoldBackgroundColor: background, canvasColor: background,
      textTheme: typography, visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory, dividerColor: border,
      hoverColor: kSleekAccent.withOpacity(.05),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: transitions, TargetPlatform.iOS: transitions,
        TargetPlatform.windows: transitions, TargetPlatform.linux: transitions,
        TargetPlatform.macOS: transitions,
      }),
      cardTheme: CardThemeData(color: surface, elevation: 0, margin: EdgeInsets.zero, shape: shape.copyWith(side: BorderSide(color: border))),
      appBarTheme: AppBarTheme(backgroundColor: background, surfaceTintColor: Colors.transparent,
        elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        iconTheme: IconThemeData(color: muted, size: 21),
        titleTextStyle: typography.titleMedium),
      dialogTheme: DialogThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: typography.titleLarge, contentTextStyle: typography.bodyMedium),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent, showDragHandle: true, dragHandleColor: border,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        constraints: const BoxConstraints(maxWidth: 720)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: surface, isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: typography.bodySmall, hintStyle: TextStyle(color: muted.withOpacity(.7)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kSleekAccent, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: kSleekAccent, foregroundColor: Colors.white, elevation: 0,
        minimumSize: const Size(44, 48), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: typography.labelLarge, shape: const StadiumBorder())),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: text, side: BorderSide(color: border), minimumSize: const Size(44, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: shape,
        textStyle: typography.labelLarge)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        foregroundColor: dark ? kSleekAccent : const Color(0xFFCD174F),
        minimumSize: const Size(44, 44), textStyle: typography.labelLarge)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(
        foregroundColor: muted, minimumSize: const Size(44, 44), iconSize: 21,
        shape: const CircleBorder())),
      listTileTheme: ListTileThemeData(contentPadding: EdgeInsets.zero, minLeadingWidth: 36,
        horizontalTitleGap: 12, titleTextStyle: typography.bodyMedium,
        subtitleTextStyle: typography.bodySmall, iconColor: muted, shape: shape),
      chipTheme: ChipThemeData(backgroundColor: raised, selectedColor: scheme.primaryContainer,
        side: BorderSide(color: border), shape: const StadiumBorder(),
        labelStyle: typography.bodySmall, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5)),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primaryContainer : raised),
        foregroundColor: WidgetStatePropertyAll(text),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        textStyle: WidgetStatePropertyAll(typography.labelLarge))),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: kSleekAccent, foregroundColor: Colors.white,
        elevation: 3, highlightElevation: 1, shape: CircleBorder()),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: kSleekAccent, linearTrackColor: raised),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF00BF69) : raised),
        trackOutlineColor: WidgetStatePropertyAll(border)),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, elevation: 0,
        backgroundColor: const Color(0xFF252027), contentTextStyle: const TextStyle(color: Colors.white), shape: shape),
    );
  }
}

/// Used only for existing primary actions, preserving their callbacks.
class KoinlyPrimaryAction extends StatelessWidget {
  const KoinlyPrimaryAction({super.key, required this.onPressed, this.label, this.icon = Icons.add_rounded});
  final VoidCallback? onPressed;
  final String? label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: onPressed == null ? null : KoinlyDesign.brandGradient,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
        boxShadow: onPressed == null ? null : [BoxShadow(color: kSleekAccent.withOpacity(.18), blurRadius: 18, offset: const Offset(0, 5))]),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: Colors.white,
          minimumSize: Size(label == null ? 48 : 80, label == null ? 48 : 44),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 16),
          shape: const StadiumBorder()),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: label == null ? 26 : 19),
          if (label != null) ...[const SizedBox(width: 6), Text(label!)],
        ]),
      ),
    );
  }
}
