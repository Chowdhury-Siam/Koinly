import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Color kSleekBackground = Color(0xFF140E12);
const Color kSleekSurface = Color(0xFF20161C);
const Color kSleekSurfaceHigh = Color(0xFF2A1C24);
const Color kSleekSurfaceHigher = Color(0xFF35242E);
const Color kSleekAccent = Color(0xFFF0A6C5);
const Color kSleekIncome = Color(0xFF83D6A9);
const Color kSleekExpense = Color(0xFFFF8D9B);
const Color kSleekWarning = Color(0xFFF2C879);
const Color kSleekMuted = Color(0xFFB7AAB1);

const appTitle = 'Koinly';
const appVersion = String.fromEnvironment('KOINLY_APP_VERSION', defaultValue: '1.0.1063');
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
