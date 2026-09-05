import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Color kSleekBackground = Color(0xFF09090B);
const Color kSleekSurface = Color(0xFF131011);
const Color kSleekSurfaceHigh = Color(0xFF201B1E);
const Color kSleekSurfaceHigher = Color(0xFF30292D);
const Color kSleekAccent = Color(0xFFFF2D68);
const Color kSleekIncome = Color(0xFF00BF69);
const Color kSleekExpense = Color(0xFFF04B69);
const Color kSleekWarning = Color(0xFFF59E0B);
const Color kSleekMuted = Color(0xFF85818C);

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
