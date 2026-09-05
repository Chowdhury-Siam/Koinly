import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// -----------------------------------------------------------------------------
// Koinly design tokens — emerald "private finance" palette.
// Dark surfaces are deep green-blacks; cards separate from the background by
// value, accents are emerald/amber/red, and text uses a white→sage ramp.
// -----------------------------------------------------------------------------

/// App background (dark): deep green-black.
const Color kSleekBackground = Color(0xFF0B0F0E);
/// Card surface (dark).
const Color kSleekSurface = Color(0xFF141A17);
/// Elevated surface (dark): inputs, hover states.
const Color kSleekSurfaceHigh = Color(0xFF1A231F);
/// Highest surface (dark): active pills, pressed states.
const Color kSleekSurfaceHigher = Color(0xFF1F2926);
/// Primary accent: emerald.
const Color kSleekAccent = Color(0xFF10B981);
/// Income / positive money color.
const Color kSleekIncome = Color(0xFF10B981);
/// Expense / negative money color.
const Color kSleekExpense = Color(0xFFEF4444);
/// Warning / budget pressure color.
const Color kSleekWarning = Color(0xFFF59E0B);
/// Secondary text color that stays legible in both themes.
const Color kSleekMuted = Color(0xFF7A8683);

// Light-mode counterparts of the dark tokens above.
const Color kSleekLightBackground = Color(0xFFF7F8F5);
const Color kSleekLightSidebar = Color(0xFFF0F2EC);
const Color kSleekLightCard = Color(0xFFFFFFFF);
const Color kSleekLightCardHigh = Color(0xFFF3F4F1);
const Color kSleekLightText = Color(0xFF111111);
const Color kSleekLightSecondaryText = Color(0xFF6B7280);
const Color kSleekLightMutedText = Color(0xFF9CA3AF);
const Color kSleekLightBorder = Color(0xFFE7EAE3);
const Color kSleekLightIncome = Color(0xFF059669);
const Color kSleekLightExpense = Color(0xFFE11D48);

/// Deep emerald used for primary buttons (dark theme).
const Color kSleekPrimaryButton = Color(0xFF10B981);
/// Text/foreground drawn on the emerald accent.
const Color kSleekOnAccent = Color(0xFFFFFFFF);
/// Avatar fallback accent (reference uses a warm orange).
const Color kSleekAvatarAccent = Color(0xFFF97316);

/// Sidebar rail width when collapsed to icons.
const double kSidebarCompactWidth = 84;
/// Sidebar rail width when fully extended.
const double kSidebarExtendedWidth = 244;

const appTitle = 'Koinly';
const appVersion = String.fromEnvironment('KOINLY_APP_VERSION', defaultValue: '1.0.1062');
const kLowEndFriendlyUi = true;
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
