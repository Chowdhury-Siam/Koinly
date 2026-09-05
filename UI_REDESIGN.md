# Koinly UI redesign

This source project retains version 1.0.1062 and uses the supplied Koinly logo reference designs as its visual direction. The supplied Android project and Windows build workflow are retained.

## Presentation changes

- Neutral light and dark themes, pink accents, warm gradient primary actions, lighter typography, subtle borders and consistent spacing.
- Desktop sidebar ordered Home, Activity, Insights, Loans, Categories, Settings. Original persisted tab indexes are unchanged.
- Compact mobile navigation with visible labels and an Add transaction action. All five existing destinations remain available.
- Framed page headers, full-width balance summary, responsive individual account cards and recent activity. Existing account management, savings, budgets, category spending and empty-account recovery remain accessible.
- Settings reorganized into Appearance, Sync & Data, Preferences and About Koinly. Backup and restore remain in Advanced settings.
- Category management uses responsive tiles. The existing interactive category breakdown and chart controls remain available.
- Updated metric panels, loan surfaces, pickers, forms, dialogs and profile styling. The transaction editor puts the amount first and retains title, notes, account/category selection, transfer destination, date range, time, edit and delete behavior.
- Short fade transitions, pressed states and animated selections, with reduced-motion handling. No animation package or new dependency is required.

Reference-only capabilities such as transaction search, automatic saving and biometric locking were not introduced. Reference sample names, balances, percentages and charts are not used as application data.

## Preservation checks completed

- Every original file remains in the project, except that presentation code within seven existing Dart files was edited. No original file was deleted.
- Database, AppController, finance calculations and business helpers in main.dart are byte-for-byte identical to the uploaded project.
- Backend, sync services, repositories, models, persistence, reminder/update services, dependency manifests, platform configuration, existing tests and assets are byte-for-byte identical.
- Source parsing completed without Dart syntax errors. This is a syntax check, not Flutter analysis or compilation.

New presentation files: lib/design_system.dart and lib/redesigned_shell.dart.
New regression checks: test/redesign_layout_test.dart, covering six primary screens at four widths in both themes, plus transfer editor fields.

## Verification limitation

The editing environment did not have Flutter or Dart installed, and the Flutter SDK download was unavailable. Consequently, flutter analyze, flutter test, native compilation and rendered visual/interaction QA were not executed. The added regression tests are unexecuted. This archive is updated source code, not a verified release build. Pixel-level matching to the reference has not been confirmed on a running app.

On a Flutter development machine, run from the project root:

```sh
flutter pub get
flutter analyze
flutter test
```

Use the original README and existing build workflow for Android/Windows setup and packaging. The original archive does not include a Windows platform directory; its workflow generates that platform as before.

Before releasing, verify light/dark themes at phone and desktop sizes, keyboard focus, reduced motion, transaction creation/edit/delete/transfer, account and category editing, budget navigation, loan repayments, profile editing, filters, sync, backup and restore against a disposable test database. Existing cloud services require the same configuration as before.
