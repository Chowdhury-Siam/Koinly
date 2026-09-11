import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Koinly's visual system uses an emerald-on-ink palette. Keep app-wide
// surfaces here so screens, popups, charts and navigation all inherit the
// same green cast instead of drifting back toward blue/cyan.
const Color kSleekBackground = Color(0xFF06110D);
const Color kSleekSurfaceLow = Color(0xFF081510);
const Color kSleekSurface = Color(0xFF0B1914);
const Color kSleekSurfaceContainer = Color(0xFF0E1E18);
const Color kSleekSurfaceHigh = Color(0xFF11251D);
const Color kSleekSurfaceHigher = Color(0xFF183127);
const Color kSleekOutline = Color(0xFF29463A);
const Color kSleekOutlineVariant = Color(0xFF19372C);

const Color kSleekLightBackground = Color(0xFFF6F9F6);
const Color kSleekLightSurfaceLow = Color(0xFFFBFDFB);
const Color kSleekLightSurface = Color(0xFFFFFFFF);
const Color kSleekLightSurfaceContainer = Color(0xFFF3F8F4);
const Color kSleekLightSurfaceHigh = Color(0xFFECF4EF);
const Color kSleekLightSurfaceHigher = Color(0xFFE3EFE7);
const Color kSleekLightOutline = Color(0xFFB9CBC1);
const Color kSleekLightOutlineVariant = Color(0xFFD9E7DE);

const Color kSleekAccent = Color(0xFF10B981);
const Color kSleekIncome = Color(0xFF34D399);
const Color kSleekExpense = Color(0xFFFF5353);
const Color kSleekWarning = Color(0xFFF59E0B);
const Color kSleekMuted = Color(0xFF8FA69C);

const String kSleekAccentHex = '#10B981';
const String kLegacyStarterCashIconHex = '#78D8E8';

const appTitle = 'Koinly';
const appVersion = String.fromEnvironment('KOINLY_APP_VERSION', defaultValue: '1.0.1092');
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
