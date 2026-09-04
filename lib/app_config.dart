import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// UI palette adapted from the reference app's Material 3 dark theme.
// The finance-specific semantic colors remain distinct, while the chrome,
// surfaces, controls, and navigation use the softer mauve/rose language.
const Color kSleekBackground = Color(0xFF161217);
const Color kSleekSurface = Color(0xFF1F1A1F);
const Color kSleekSurfaceHigh = Color(0xFF231E23);
const Color kSleekSurfaceHigher = Color(0xFF2E282E);
const Color kSleekAccent = Color(0xFFB76AC2);
const Color kSleekIncome = Color(0xFF39A96B);
const Color kSleekExpense = Color(0xFFE45D67);
const Color kSleekWarning = Color(0xFFD99A2B);
const Color kSleekMuted = Color(0xFF988E97);

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
