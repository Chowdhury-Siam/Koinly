import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enhanced UI packages are declared and wired into the app', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final app = File('lib/main.dart').readAsStringSync();
    final loans = File('lib/loans/loan_screens.dart').readAsStringSync();

    expect(pubspec, contains('fl_chart: ^0.69.0'));
    expect(pubspec, contains('lottie: ^3.5.1'));
    expect(pubspec, contains('timelines_plus: ^2.0.1'));
    expect(pubspec, contains('flutter_spinkit: ^5.2.2'));
    expect(pubspec, contains('awesome_snackbar_content: ^0.1.8'));
    expect(pubspec, contains('intl: ^0.20.3'));
    expect(pubspec, contains('flutter_slidable: ^4.0.3'));
    expect(pubspec, contains('workmanager: ^0.10.10'));
    expect(pubspec, contains('- assets/lottie/'));

    expect(app, contains("import 'package:lottie/lottie.dart';"));
    expect(app, contains("import 'package:flutter_spinkit/flutter_spinkit.dart';"));
    expect(app, contains("import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';"));
    expect(app, contains("import 'package:flutter_slidable/flutter_slidable.dart';"));
    expect(app, contains("import 'package:timelines_plus/timelines_plus.dart';"));
    expect(app, contains('Lottie.asset('));
    expect(app, contains('SpinKitThreeBounce('));
    expect(app, contains('SpinKitFadingCircle('));
    expect(app, contains('AwesomeSnackbarContent('));
    expect(app, contains('PieChart('));
    expect(app, contains("ValueKey('transaction-\${tx.id}')"));
    expect(app, contains("ValueKey('planned-\${item.id}')"));
    expect(loans, contains("ValueKey('loan-\${loan.id}')"));
    expect(loans, contains('TimelineTile('));
  });

  test('bundled Lottie empty-state animation is present', () {
    final animation = File('assets/lottie/empty_state.json');
    expect(animation.existsSync(), isTrue);
    expect(animation.lengthSync(), greaterThan(100));
  });
}
