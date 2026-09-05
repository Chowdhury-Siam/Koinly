import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// -----------------------------------------------------------------------------
// Koinly "Ember" design tokens — warm gradient palette inspired by the app
// logo (coral red → tangerine → amber). The full app theme is built on top of
// these in `KoinlyApp._theme()` inside main.dart.
//
// Token NAMES are preserved from the original Sleek theme so the existing
// 14k-line main.dart keeps compiling. Only the VALUES change to the new warm
// palette. New tokens (kSleekAccent2, kSleekAccent3, kSleekRose, kSleekPlum,
// the dark-surface variants) are added for the new theme builder.
// -----------------------------------------------------------------------------

// Brand core (the warm gradient that mirrors the K "monogram" in the icon).
const Color kSleekAccent = Color(0xFFFF5A3C); // coral red — primary action
const Color kSleekAccent2 = Color(0xFFFF8A3D); // tangerine — secondary
const Color kSleekAccent3 = Color(0xFFFFB547); // amber — tertiary highlight
const Color kSleekRose = Color(0xFFFF4D6D); // pink-red — used for emphasis
const Color kSleekPlum = Color(0xFF7B5BFF); // soft violet — used for tertiary

// Income / Expense / Warning semantics.
const Color kSleekIncome = Color(0xFF20C997);
const Color kSleekExpense = Color(0xFFFF5A3C);
const Color kSleekWarning = Color(0xFFF6A609);
const Color kSleekMuted = Color(0xFF7A7686);

// Light surfaces (warm paper — used by KoinlyAtmosphere light mode).
const Color kSleekBackground = Color(0xFFFBF7F2);
const Color kSleekSurface = Color(0xFFFFFFFF);
const Color kSleekSurfaceHigh = Color(0xFFF4EFE8);
const Color kSleekSurfaceHigher = Color(0xFFEAE3DA);

// Dark surfaces (warm charcoal — never pure black).
const Color kSleekBackgroundDark = Color(0xFF141113);
const Color kSleekSurfaceDark = Color(0xFF1C181B);
const Color kSleekSurfaceHighDark = Color(0xFF252025);
const Color kSleekSurfaceHigherDark = Color(0xFF322C33);

const appTitle = 'Koinly';
const appVersion = String.fromEnvironment('KOINLY_APP_VERSION', defaultValue: '1.0.1062');

// Premium animations are now always enabled — `kLowEndFriendlyUi` is exposed
// but no longer hard-disables motion. We keep the symbol so existing read
// sites continue to compile, but treat it as a hint rather than a hard kill
// switch.
const bool kLowEndFriendlyUi = false;

const backupPassword = 'YOUR_SECRET_PASSWORD';
const kSyncAdminTelegramUrl = 'https://t.me/Ch0wdhury_Siam';
const int kHomeTabIndex = 0;
const int kAnalysisTabIndex = 1;
const int kLoansTabIndex = 2;
const int kTransactionTabIndex = 3;
const int kCategoriesTabIndex = 4;

bool get kUsesDesktopSqlite => !kIsWeb && (Platform.isWindows || Platform.isLinux);
bool get kIsDesktopApp => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
bool get kSupportsLocalNotifications => !kIsWeb && Platform.isAndroid;

// Desktop builds store SharedPreferences separately from Android. Older Windows
// builds could inherit `onboardingCompleted=true` and skip the setup flow.
// Bumping this desktop setup marker forces the setup pages to appear once on PC
// without resetting mobile users or deleting any finance data. Revision 20260621 also
// corrects installs that previously skipped the Windows setup flow.
const int kRequiredDesktopSetupVersion = 20260623;

// Helper used by other UI files to fetch the brand gradient.
const List<Color> kKoinlyBrandGradient = <Color>[
  kSleekAccent,
  kSleekAccent2,
  kSleekAccent3,
];

const List<Color> kKoinlyBrandGradientDark = <Color>[
  Color(0xFFFF6A4D),
  Color(0xFFFF9342),
  Color(0xFFFFB947),
];
