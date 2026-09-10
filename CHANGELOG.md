# Changelog

## [1.0.1081] - 2026-09-11

### Changed

- Moved **Upload local changes** beside **Restore cloud copy** on the signed-in Account & sync screen, with Recovery key and Sign out kept together on the row below.

### Fixed

- Fixed the Android release workflow overwriting Koinly's custom splash resources when it regenerated missing Gradle wrapper binaries. Release builds now preserve the complete checked-in Android project and copy back only the generated wrapper files, so Android 12+ uses the dedicated transparent/padded K mark instead of falling back to the rounded-square launcher icon.
- Tightened the Flutter loading mark bounds so the in-app fallback splash also keeps the full K artwork visible without clipping.

## [1.0.1080] - 2026-09-11

### Changed

- Loan-generated entries remain visible in **Transactions**, but opening one now uses a dedicated **Loan** classification instead of presenting it as Expense, Income, or Transfer. The Loan classification is shown only for transactions linked to a loan or loan repayment.
- Loan transaction categories are fixed to **Loan** in the transaction editor so users cannot accidentally reclassify a loan entry as a normal income/expense category.

### Fixed

- Reworked the Android launch artwork to use a transparent, extra-safe padded Koinly mark instead of the full rounded-square launcher tile, preventing OEM splash-screen masks from cropping the launch logo.
- Editing a linked loan transaction now keeps the underlying loan/repayment record and account balance synchronized. Deleting a linked repayment removes its repayment record safely, while deleting a loan disbursal transaction detaches only the recorded account movement from the loan.

## [1.0.1079] - 2026-09-11

### Added

- Added an **Automatic update pop-ups** toggle on the Updates screen. Turning it off keeps manual update checks available while suppressing automatic update-detail pop-ups.

### Fixed

- Fixed self-hosted sign-in dropping back to the login form immediately after cloud data finished loading. Preference reloads now preserve current self-hosted access/refresh tokens and only run legacy token cleanup when the legacy sync-mode marker actually exists.
- Fixed GitHub release changelog rendering so inline Markdown bold markers such as `**Forgot password?**` display as styled text instead of showing the literal asterisks.
- Fixed the Android launch presentation with a dedicated, correctly padded native splash icon and a launch background that matches the app theme on Android 12+ and older supported Android versions.

## [1.0.1078] - 2026-09-11

### Added

- Added username-based self-hosted authentication and removed email from the login/create-account flow.
- Added recovery-key based **Forgot password?** recovery, including recovery-key rotation for signed-in users.
- Added compatibility migration for existing self-hosted databases and local preferences that still use email-based account identifiers.

### Changed

- Reworked centered popup bodies to stay non-scrollable and scale to the available viewport while keeping intentionally scrollable picker lists contained inside their own fixed-height regions.
- Updated the Turso and Cloudflare setup guide to match the current dashboards shown in the setup recording and the current Cloudflare **Edit Cloudflare Workers** token template.

### Security

- Recovery keys are stored only as keyed hashes, password-recovery attempts are rate limited, successful recovery revokes existing refresh sessions, and recovery responses are marked private/no-store.

## [1.0.1077] - 2026-09-10

- Rewrote the main README as a beginner-friendly user and self-hosted deployment guide suitable for public distribution.
- Simplified the self-hosted GitHub Actions variable/secret names to `CLOUDFLARE_NAME`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`, and `JWT_SECRET`.
- Updated the deployment workflow, Worker documentation, validation messages, and Wrangler comments to use the same names consistently.


## [1.0.1076] - 2026-09-10

- Added app-wide text-field focus dismissal on outside taps so amount, payment amount, title, notes, profile fields, loan fields, sync fields, and other text inputs release focus when the user moves to another control.
- Simplified Account & sync to one runtime-configured self-hosted Cloudflare Worker, including first-owner registration and Telegram backup access.
- Added migration for existing self-hosted Worker URLs and safely clears obsolete non-self-hosted sync sessions without deleting local finance data.
- Simplified Android/Windows builds and Worker deployment so no sync endpoint is compiled into the app.
- Updated the self-hosted Worker to first-owner registration only and removed the old registration-key deployment path.
- Reworked the main and Worker documentation around the self-hosted-only sync model.

## [1.0.1075] - 2026-09-10

### Changed

- Moved the cash-flow **Net** value into the upper-right of the Cash flow trend header beside the date-range control, keeping the requested value visible without duplicating the metric below.
- Account and category selection sheets now include **Add account** / **Add category** actions. A newly created entry is returned to the originating form and selected immediately.
- Category creation launched from an expense/income picker is locked to the required category type, preventing a newly created incompatible category from being selected accidentally.
- Empty account/category pickers can now open and create their first item instead of failing early.

## [1.0.1074] - 2026-09-10

### Changed

- Transaction date selection now starts in single-date mode. **Use range** explicitly enables Start/End selection, while existing ranged transactions reopen in range mode.
- Reworked the transaction date picker into a bounded, scrollable body with sticky actions so the calendar and controls remain usable on short Android screens.
- Added the same opt-in range workflow to transaction time selection. A transaction can now span a same-day time range or combine a date range with independent start/end times.
- Transaction history labels display a saved time range when the start and end times differ.
- New transactions no longer contain a literal `0` in the Amount field. Zero is now a visual placeholder that disappears as soon as Amount receives focus.
- Opening Category, Account, From account, To account, Date, or Time explicitly dismisses Amount focus and the numeric keyboard first.

### Fixed

- Fixed the transaction date-range dialog being effectively unscrollable when its calendar exceeded the available popup height.
- Same-day time ranges are now persisted through the existing transaction `end_on` field instead of being discarded merely because both endpoints use the same date.

## [1.0.1073] - 2026-09-09

### Changed

- Added restrained spring/elastic micro-interactions across tappable cards, selectors, navigation, and the Transaction Add/Plan actions without redesigning the UI.
- Mobile lists now use a soft elastic edge response while desktop mouse/trackpad scrolling remains clamped and precise.
- Page and bottom-tab changes now combine a short fade with a subtle scale/slide transition instead of hard swaps.
- Low-end-friendly rendering still avoids expensive gradients/shadows, but no longer disables all lightweight UI animation; Android/iOS Reduce Motion remains respected.
- Added light haptic feedback for main tab changes and Transaction Add/Plan actions.

## [1.0.1072] - 2026-09-09

### Fixed
- Fixed self-hosted Telegram backups that could decrypt successfully but contain zero finance rows. The Worker now refuses to send an empty `.koinlybackup` and returns a clear recovery message instead of producing a file that later appears to restore successfully.
- Telegram backup generation now reconstructs current cloud state from sync history when `sync_entities` is unexpectedly empty but recoverable `sync_changes` still exist.
- Backup restore now validates the actual supported finance-row count rather than treating a database object containing only empty arrays as valid data.
- **Upload local changes** now reconciles the complete local snapshot, so records that existed before signing in to a self-hosted Worker are uploaded instead of being missed because they were never in the sync outbox.
- **Upload backup now** and enabling automatic Telegram backup first force a full local/cloud reconciliation, ensuring the Worker packages the latest complete device data.
- Forced reconciliation now completes rebased conflict operations in the same action instead of waiting for a later background retry.
- A stale local entity version from another backend now rebases to server version `0` when the new Worker has no matching entity, allowing the local row to be inserted instead of silently disappearing from cloud backups.
- Signing out resets account-specific sync versions, cursor, conflicts, and outbox tracking without deleting finance data, preventing state from the Default Worker from contaminating a Self-hosted Worker (or another account).
- Existing-account login now pulls/merges the cloud first and then adopts the complete merged local snapshot back to that account, so local-only records become part of future Worker backups automatically.

### Changed
- Telegram-generated backups include per-table `record_counts` and a total `finance_record_count` diagnostic field while remaining compatible with the existing `.koinlybackup` restore format.

## [1.0.1071] - 2026-09-09

### Added
- Optional Telegram `.koinlybackup` delivery for the **self-hosted Sync Worker**. A bot button now appears in the Account & sync app bar only while Self-hosted is selected and the device is signed in.
- Self-hosted owners can configure a Telegram bot token, group/channel Chat ID, daily/weekly/monthly schedule, exact local time, weekly day or monthly date, test delivery, and **Upload backup now** from Koinly.
- The self-hosted Worker encrypts the saved bot token with an AES-GCM key derived from its `JWT_SECRET`, stores only the encrypted token in Turso, creates a cloud-state `.koinlybackup`, and uploads it directly to Telegram.
- A dedicated self-hosted Wrangler config adds a five-minute Cron Trigger. The managed/default owner Worker does not receive this trigger and the Telegram-backup API rejects managed invite-key deployments.

### Changed
- Self-hosted deployment applies the Telegram backup settings table automatically; no extra GitHub/Cloudflare secret is required for the user's backup bot because its token is configured from the authenticated app screen.

## [1.0.1070] - 2026-09-09

### Added
- The **Plan** page now shows the combined price of every planned item in the top-right header area.
- Existing profile media can now be repositioned and zoom-cropped non-destructively, with framing saved locally and reused for the profile avatar and previews.

### Changed
- Removed the **Savings Suggestion** feature, its profile/preferences UI, suggestion bubbles, recommendation model, and active preference payloads.
- Removed **Bio** from Profile information; profile information now contains the display name and sync-account details only.
- Cloud sync now automatically closes conflict records after the merged/rebased entity has no pending outbox operation. Data health also clears legacy stale conflicts that predate the last successful sync, so already-resolved conflicts do not remain permanently open.
- Repeated server conflicts for the same entity update the existing open conflict record instead of creating duplicate open diagnostics.

### Migration
- Legacy Savings Suggestion and profile Bio preference keys are purged during preference loading so older local/cloud payloads cannot revive removed UI or behavior.

## [1.0.1069] - 2026-09-09

### Added
- Added a **Plan** floating action button on the Transaction tab for purchase planning.
- Added a dedicated Plan page where users can create and edit items with an expected price and expense category.
- Planned items can be purchased directly: Koinly opens a centered account chooser, creates an expense transaction with the current date/time, deducts the selected account, and removes the completed planned item.
- Planned purchases are included in local backups, merge restores, category deduplication, and multi-device sync.

### Changed
- Planned purchase records participate in the same non-destructive merge and conflict-resolution pipeline as the rest of the finance database.
- Category deduplication now remaps planned-item category references as well as transaction and budget references.

## [1.0.1068] - 2026-09-09

### Changed
- Starter Cash/Card/Bank Account placeholders are now created only after the user explicitly chooses **Start new**. Fresh **Login** and **Restore backup** flows no longer begin with preloaded accounts.
- Backup restore and cloud-login import paths remove only untouched built-in starter-account fingerprints before merging, preventing duplicate placeholder Cash/Card/Bank Account rows while preserving used or customized accounts.
- Automatic-backup retention no longer uses a numeric **How many to keep** slider. The new **Delete older automatic backups** switch defaults on; when enabled, only the newest automatic backup is kept, and when disabled, automatic backup history is retained.
- Automatic local backup now requires an explicit folder. The **App storage** destination option has been removed.
- Choosing an automatic-backup location creates and uses a dedicated `Koinly/Backup` subfolder. Android keeps the parent folder grant through Storage Access Framework so scheduled backups continue after restarts.
- Removed **Restore last safety backup** from Advanced settings. Safety backups remain internal protection for risky data operations.

### Fixed
- Restoring a backup during first-run offline setup no longer leaves Koinly's preloaded starter accounts beside the restored accounts.
- Existing-account login now discards untouched preloaded starter placeholders before and after the cloud merge, and pushes tombstones so old cloud placeholders cannot return.
- Upgrading an existing installation that already has the old duplicate-starter bug now detects a redundant untouched starter fingerprint and cleans the remaining built-in placeholders while preserving used or customized accounts.

## [1.0.1067] - 2026-09-09

### Added
- Android automatic backup folders now use the system Storage Access Framework and retain a persistent write grant, allowing scheduled backups to save to user-selected internal or SD-card folders after app restarts.
- Added a shared non-destructive finance merge engine for local backups, cloud restores, legacy snapshot sync, and conflict recovery.
- Added merge regression tests covering local-only/cloud-only rows, same-ID reconciliation, category deduplication, preference remapping, and Android folder-access contracts.

### Changed
- **Upload local changes** is now merge-first: cloud-only records are preserved and newer same-ID records are reconciled instead of replacing the cloud dataset.
- **Restore cloud copy** now performs a two-way merge. Local-only records remain on the device, the full cloud history is folded in, and any resulting local changes are queued back to cloud.
- Loading a `.koinlybackup` or restoring the last safety backup now merges with the active local database rather than replacing it.
- Categories are deduplicated semantically by category type plus normalized, case-insensitive name. For example, local `Food` and cloud ` food ` resolve to one category and transaction/budget/preference references are remapped to it.
- Same-ID entity conflicts use `updated_on` (falling back to `created_on`) to retain the newer row; unrelated IDs are unioned.
- The older Sync ID/PIN snapshot screen now follows the same merge semantics for both upload and download.

### Fixed
- Fixed Android `PathAccessException: Operation not permitted` when automatic backup targeted raw `/storage/...` paths under scoped storage.
- Older raw-path automatic-backup settings are detected and ask the user to choose the folder once through Android's system picker instead of repeatedly attempting an unwritable filesystem path.
- Upload conflicts are rebased even when the subsequent pull contains no additional rows, preventing a newer local edit from disappearing at a cursor boundary.
- Removed the Flutter client's destructive replace-all path from restored-data synchronization; legacy pending restore flags are migrated into normal merge upserts.

## [1.0.1066] - 2026-09-09

### Added
- First-run **Use offline** now opens a **Restore backup / Start new** choice instead of immediately entering the new-profile setup flow.
- Creating a sync account during onboarding now opens the same setup choice automatically. Restoring a backup makes the restored local dataset authoritative for the newly created sync account.
- If the setup chooser is dismissed after account creation, onboarding shows **Continue setup** so the user can return to the Restore/Start New decision without creating another account.

### Changed
- Restoring a backup during first-run setup completes onboarding immediately because the backup already contains the user's finance data and preferences. **Start new** continues through Currency and Accounts as before.
- The first-run restore option clearly warns that the current local finance data on the device will be replaced.
- New sync-account registration during onboarding now waits for the Restore/Start New decision before seeding cloud data, so temporary starter data is not uploaded when the user intends to restore a backup.

### Fixed
- Switching from **Create account** to **Login** inside onboarding now restores the existing cloud copy and completes setup instead of returning to first-run local setup.

## [1.0.1065] - 2026-09-09

### Added
- Loan start dates, due dates, and repayment records now include an editable time as well as a date. Existing loan records remain compatible and continue to load normally.
- Added **Advanced settings > Automatic local backup** with daily, weekly, or monthly scheduling, a selectable backup time, configurable retention count, and a selectable local backup folder.
- Automatic backups use separate `koinly_auto_*.koinlybackup` files, prune only older automatic backups, and never delete manual or safety backups.
- Missed scheduled backups are created when Koinly next opens or resumes, and the settings screen shows the last/next automatic backup state.

### Changed
- Loan detail and payment history now display the recorded time alongside the date.

## [1.0.1064] - 2026-09-07

### Fixed
- Removed the Android CI temporary signing-key fallback. Release APK builds now require the permanent Koinly signing secrets and fail immediately if any signing secret is missing.
- Added validation for the decoded release keystore, configured alias, and store password before Flutter starts the Android release build.
- The workflow now prints the configured release certificate SHA-256 fingerprint in the build log so the signing identity can be checked between releases.

### Changed
- Android release signing now uses only the permanent `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` repository secrets.

## [1.0.1063] - 2026-09-07

### Fixed
- Restored `android/app/google-services.json` to the source tree so Android Firebase configuration is available directly during local and GitHub Actions builds.
- Removed the `GOOGLE_SERVICES_JSON_BASE64` GitHub secret requirement and its CI decode step.
- Stopped ignoring `android/app/google-services.json` in `.gitignore`.

## [1.0.1062] - 2026-09-04

### Fixed
- Rebuilt the shared Choose picker layout so the active option is rendered only once; removed the duplicate selected-value preview row below the picker.
- Choose Date Filter, Theme, Account, Category, and other shared selectors now shrink to the number of available options instead of leaving a large empty wheel viewport on desktop.
- Replaced the fragile fixed-center wheel presentation in shared selectors with a compact native-scrolling list that keeps the selected row highlighted and preserves smooth mouse-wheel, touchpad, and touch scrolling.
- Currency selection now uses the same compact selectable-list behavior, with search retained and no duplicate selected-value summary.

### Changed
- Long Choose lists show up to four rows at once with a desktop scrollbar; short lists stay compact while Cancel and Done remain fixed below the options.

## [1.0.1061] - 2026-09-04

### Fixed
- Removed the custom desktop pointer-wheel animation layer that queued `animateTo` calls and caused jerky, overshooting, or jumping scroll behavior. Desktop pages, mouse wheels, touchpads, and fixed-item Choose pickers now use Flutter's native scrolling pipeline.
- Removed selection-size changes from wheel rows so Theme, Currency, account/category selectors, and other Choose pickers no longer resize items while they are moving.
- Windows updates now download inside Koinly instead of opening the GitHub installer URL directly. The Windows updater now shows the same live percentage, transferred size, speed, animated progress panel, cancel state, and retry behavior used by Android.
- Downloaded Windows installers are retained as pending updates and can be launched again if installation is not completed on the first attempt.

### Changed
- Windows update downloads now verify that the installer comes from the configured Koinly GitHub release before saving or launching it.

## [1.0.1060] - 2026-09-04

### Fixed
- First-run account creation now offers Savings alongside Regular and Credit, so a savings account can be created directly during onboarding.
- Choice-wheel scrolling now uses a dedicated fixed-item desktop animator instead of the generic page-scroll handler; Theme, Currency, and other wheel selectors move and snap cleanly without visible jumps.
- Profile media no longer shows technical file metadata or the supported-format/size helper after media has been added.

### Changed
- Improved selection motion in wheel-based pickers with consistent scale/opacity transitions across the app.

## [1.0.1059] - 2026-09-04

### Fixed
- Download progress wave now continuously animates while an update is downloading instead of becoming static when reduced-motion settings are enabled.
- Choose Color no longer uses a nested non-scrollable grid that could swallow desktop mouse-wheel input; preset colors now use a wrap layout so the page scrolls normally.
- Transaction date-range selection now opens in Koinly's centered popup instead of taking over the entire screen.

### Changed
- Transaction Title now appears above Amount for Expense and Income entry.
- Removed the “Tap or drag for exact values” helper text from Cash flow trend.

## [1.0.1058] - 2026-09-04

### Fixed

- Reworked the appearance-color screens for Windows/large displays so the preset palette uses compact fixed-density rows instead of oversized empty grid cells.
- Rebuilt the custom color picker with a desktop two-column layout and a capped color wheel, preventing the wheel and controls from stretching far beyond usable desktop sizes.
- Constrained the photo color picker on desktop so the complete appearance-color workflow remains readable at wide window sizes.
- Made the generated Windows runner title patch handle both Flutter runner templates so the title bar consistently shows `Koinly` instead of the lowercase generated project name.

### Changed

- Reduced CI release work by building only the requested ARM32, ARM64, and Universal Android APKs; removed the unnecessary x86_64 APK and AAB release artifacts.
- Added reusable Dart package caching, cached Windows extracted native dependencies, skipped already-installed Android SDK/NDK packages, and avoided reinstalling Inno Setup when it is already present.
- Universal Android APKs are now produced directly by Flutter instead of building an AAB and running bundletool, reducing release-job overhead.

## [1.0.1057] - 2026-09-04

### Fixed

- New sync-account registration during first-run setup now always continues through Currency and Accounts instead of accidentally completing onboarding when registration was selected from the Login screen.
- The Accounts setup step now makes add, edit, and remove actions explicit.

### Changed

- Replaced the previous Analysis Trend card with a cleaner cash-flow trend that includes Income/Expense/Net summaries, Both/Income/Expense views, clearer date labels, touch values, and an improved empty state.
- Increased the profile photo/GIF/video limit from 500 KB to 1000 KB across validation, UI guidance, and tests.

## [1.0.1056] - 2026-09-01

### Fixed

- Update checks now read a public release manifest before using the GitHub API,
  avoiding GitHub API rate-limit failures for normal in-app update checks.

## [1.0.1055] - 2026-09-01

### Changed

- Removed the Advanced settings performance toggle.
- Made low-end-friendly UI rendering the default by reducing heavy motion,
  press animations, gradients, and shadows automatically.

## [1.0.1054] - 2026-08-31

### Changed

- Reworked mobile scrolling to use smoother Android-style clamping with tuned
  fling momentum instead of the previous iOS-like bouncing behavior.
- Added smoother desktop mouse-wheel/trackpad scrolling through the shared app
  scroll behavior.

## [1.0.1053] - 2026-08-31

### Fixed

- Made the update prompt appear automatically after startup and retry on app
  resume when the first background check hits a temporary GitHub/network issue.
- Aligned the native Android version name/code with the Flutter release version.

## [1.0.1052] - 2026-08-31

### Fixed

- Transaction history now filters and sorts ranged transactions by their end
  date, so an Aug 25 to Aug 31 transaction appears with Aug 31 records.

## [1.0.1051] - 2026-08-31

### Fixed

- Raised the full cloud replacement upload limit to 25000 operations with a
  dedicated `MAX_SYNC_REPLACE_SIZE` Worker setting.

## [1.0.1050] - 2026-08-31

### Fixed

- Added a targeted owner Worker deployment hint when Cloudflare returns `1042`
  during the health check because a Worker route or backend URL is looping.

## [1.0.1049] - 2026-08-31

### Fixed

- Made Worker deployment health checks wait through fresh workers.dev TLS and
  route propagation instead of failing immediately on transient curl TLS exits.

## [1.0.1048] - 2026-08-31

### Changed

- Removed the committed Firebase Android config and restored it during Android
  CI builds from the `GOOGLE_SERVICES_JSON_BASE64` GitHub secret.

## [1.0.1047] - 2026-08-30

### Changed

- Pointed GitHub update checks, release workflow gates, documentation links,
  and the in-app GitHub link at `Chowdhury-Siam/Koinly`.

## [1.0.1046] - 2026-08-28

### Added

- Added a Profile entry to the Categories header with editable display name and
  bio fields.
- Added profile photo, animated GIF, and short-video selection, preview,
  replacement, removal, and muted looping playback on Android and Windows.
- Enforced a 500 KB profile-media limit before private app storage and added
  clear validation feedback for oversized or unsupported files.
- Added a first-launch Android Photos and videos permission flow with retry and
  app-settings recovery for denied and permanently denied states.

### Changed

- Moved Savings Suggestion preferences from Settings into the Profile screen so
  they have one configuration location.
- Removed the date-range pill from the Categories breakdown header while
  retaining the active app-wide date range for calculations and chart context.

## [1.0.1045] - 2026-08-28

### Fixed

- Prevented categories with different IDs but the same normalized name and type
  from multiplying after backup restore, upload, or multi-device sync.
- Existing duplicates are merged deterministically while transaction, budget,
  filter, and default-category references are moved to the retained category.
- New categories and loan-generated categories now reject or reuse equivalent
  names instead of creating another record.

## [1.0.1044] - 2026-08-28

### Added

- Added an optional start-to-end date range to income, expense, and transfer
  transactions while applying each transaction amount only once.
- Transaction history now displays the saved date span, and older single-date
  transactions remain compatible.

### Changed

- Advanced the local database, backup, and full-sync payload versions for the
  optional transaction end date.

## [1.0.1043] - 2026-08-28

### Changed

- Simplified the main Settings screen and centralized backup and restore tools
  in Advanced settings.

## [1.0.1042] - 2026-08-28

### Added

- Added a required Title field when creating or editing an income or expense
  transaction.
- Transaction titles now appear as the primary label throughout transaction,
  category, and budget history.

### Changed

- Existing income and expense records receive their category name as a safe
  title during the database upgrade.
- Backup and full-sync payload versions were advanced for the new transaction
  field.

## [1.0.1041] - 2026-08-28

### Changed

- Moved Loans from the Home dashboard into the center of the primary bottom
  navigation, between Analysis and Transactions.
- Added the same Loans destination to the Windows navigation rail and removed
  the duplicate Loans card from Home.

## [1.0.1040] - 2026-08-28

### Added

- Added a complete lending and borrowing tracker with contacts, due dates,
  notes, repayment history, statuses, and Home summary totals.
- Added no-interest, simple-interest, flat-interest, and compound-interest
  calculations using a consistent annual percentage rate, with optional
  installment estimates and interest-first repayment allocation.
- Added optional account-linked disbursal and repayment movements, due-date
  reminders, backup and sync coverage, and loan-specific data-health checks.
- Added focused tests for repayment calculations, due-date behavior, APR
  semantics, and report exclusions.

### Changed

- Loan-linked account movements update account balances but are excluded from
  income, expense, budget, and cash-flow reporting.

## [1.0.1039] - 2026-08-28

### Changed

- Removed the extra overview badge from the Home balance summary and tightened
  the surrounding layout.

## [1.0.1038] - 2026-08-28

### Changed

- Removed obsolete compatibility paths and unused media from the source
  package.
- Updated project documentation to match the current feature set.

## [1.0.1037] - 2026-08-28

### Changed

- Worker changes in `Chowdhury-Siam/Koinly` now automatically deploy the
  Owner/Default sync Worker, while the owner deployment job is always skipped
  in forks.
- Worker changes in fork repositories now automatically deploy the User
  Self-hosted sync Worker, while automatic original-repository pushes skip the
  self-hosted deployment job.
- Manual self-hosted deployment remains available in any repository; manual
  owner deployment remains restricted to the original repository.

## [1.0.1036] - 2026-08-28

### Fixed

- Stable update checks now use GitHub's designated Latest release, preventing
  the older `1.0.1035` tag from replacing newer releases such as `1.0.77` in
  the update dialog.
- Prerelease checks preserve GitHub's release-feed order instead of sorting
  historical tags by their numeric semantic version.

### Changed

- Restored monotonically increasing release versioning at `1.0.1036` so apps
  using the previous updater can discover and install this correction.

## [1.0.78] - 2026-08-28

### Changed

- Android APK/AAB and Windows installer jobs now run automatically only in the
  original `Chowdhury-Siam/Koinly` repository. Fork owners can still start
  artifact builds manually.
- Stable GitHub Release publishing is restricted to the original repository,
  including manually dispatched builds.

## [1.0.77] - 2026-08-28

### Fixed

- Self-hosted account creation now removes the Registration Key field as soon
  as Self-hosted is selected and never includes a registration key in the
  request payload.
- Self-hosted endpoints must report first-owner registration mode before the
  app accepts them, and authentication stays disabled until the selected
  endpoint is validated.

## [1.0.76] - 2026-08-28

### Changed

- Separated the user self-hosted deployment configuration from the legacy owner deployment configuration.

## [1.0.75] - 2026-08-27

### Changed

- Separated self-hosted GitHub deployment configuration from the legacy owner deployment configuration.

## [1.0.74] - 2026-08-27

### Changed

- Split Worker deployment into a fork-friendly self-hosted workflow and a
  manual owner/default-service workflow with separate owner-prefixed secrets.
- Owner deployment now verifies invite-key mode and bootstraps Telegram
  registration-key delivery without affecting user self-hosted deployments.

## [1.0.73] - 2026-08-26

### Fixed

- Worker deployment now health-checks the exact public target reported by
  Wrangler instead of reconstructing the `workers.dev` URL.
- Deployment rejects non-Turso database URLs and reports Cloudflare error pages
  without producing a misleading `jq` parse error.

## [1.0.72] - 2026-08-26

### Added

- Added optional self-hosted cloud sync using a user-owned Cloudflare Worker
  and Turso database, with runtime endpoint selection and health validation.

### Changed

- Self-hosted deployment now requires only Cloudflare, Turso, and JWT
  configuration; Telegram and registration-administrator secrets are not
  required.
- Fork builds can use temporary Android signing when permanent signing secrets
  are absent, and the default sync endpoint is optional.
- Rewrote the project README with complete setup, deployment, security, build,
  and troubleshooting documentation.

### Fixed

- Self-hosted account creation no longer asks for a managed-service
  registration key and safely closes registration after the first owner.
- Release builds and tags now use the version declared in `pubspec.yaml`.

## Unreleased

### Added

- Added server-enforced, invite-key-based account registration with one active single-use key, atomic consumption/rotation, expiration, revocation, and an auditable Turso key ledger.
- Added automatic Telegram delivery for each newly rotated registration key, delivery retry tracking, and protected administrator status/reveal/rotate/revoke/retry endpoints.

### Fixed

- Hardened account sync with transactional compare-and-set writes so concurrent devices cannot both accept the same entity base version.
- Idempotent sync retries now return the version assigned by the original accepted operation instead of the stale client base version.
- Budget scope edits and budget deletion now enqueue cloud tombstones for removed account/category mappings.
- Removed runtime schema mutation from normal Cloudflare Worker requests; schema deployment remains an explicit deployment step.

- Account signup now rejects missing, invalid, expired, revoked, and previously used registration keys with clear user-facing messages.
- Latest release changelog now publishes only the current update notes instead of the full accumulated development history.

### Changed

- Android release signing now requires injected keystore secrets; the release keystore and passwords are no longer stored in source.
- Removed the obsolete device-lock module from the application UI, models,
  notifications, and dependencies.

- The default-service Create account form now requires a Registration Key and
  relies on backend validation; self-hosted registration uses the first-owner
  flow without a key.
- Added a Pursenal-style Load backup workflow in Settings that opens a file picker, loads a `.koinlybackup` file, replaces local data, and triggers the existing cloud-upload path when signed in.
- Android package/application ID changed from `com.siamapps.koinly` to `com.koinly.siam`.
- Transaction amount entry now uses the normal phone/desktop keyboard instead of Koinly's old custom on-screen keypad.
- Release automation now falls back to only the first/current bullet under each Unreleased heading, so accidental older notes do not flood the newest GitHub Release body.

### Previous development history

- Long scrolling lists now avoid duplicate row repaint boundaries, unnecessary keep-alive bookkeeping, and semantic index calculations that made Windows scrolling feel choppier.
- Desktop card surfaces now avoid animated container work, heavy shadows, and per-card gradients during normal rendering for smoother Windows scrolling.
- Desktop list preloading was reduced so fast scrolling builds fewer off-screen finance cards at once.
- Login/cloud restore now removes untouched starter Cash/Card/Bank Account placeholders from the restored local copy, even when real cloud data also exists.
- Other signed-in devices now automatically pull cloud changes while the app is open and whenever the app resumes, so new transactions appear across devices without manual restore.
- Android no longer reopens the package installer for a downloaded update after that same version is already installed.
- Made Account & sync uploads more reliable by giving full restore uploads a longer request timeout and replacing raw timeout exceptions with clean user-facing messages.
- Prevented Upload restored/local changes from appearing to do nothing while a background sync retry is already running.
- Login from setup or Account & sync now always treats cloud data as the source of truth and fully replaces local finance data on the device.
- Release notes are grouped by current changes, additions, removals, and fixes so the in-app updater shows only the useful “what changed in this update” text.
- Renamed the Account & sync upload button to “Upload restored data” whenever a restored local backup still needs to become the cloud source of truth.
- Hid the Account & sync backend-configuration explanation card and the restore/upload help paragraph to keep the sync page cleaner.
- Reduced Cloudflare Worker subrequests during `/v1/sync/replace` by batching snapshot entity/change writes instead of calling Turso several times per entity.
- Removed per-operation sequence lookups from authoritative cloud replace uploads; the app only needs accepted entity versions plus the final server cursor for this flow.
- Hardened the Cloudflare Worker `/v1/sync/replace` endpoint so duplicate snapshot upserts are coalesced by entity before writing to Turso.
- Made replace-sync processed operation writes idempotent, preventing repeated operation IDs from turning cloud overwrite attempts into 500 responses.
- Added sanitized Worker-side logging for unexpected internal errors so future Cloudflare logs show the useful failure reason.
- Fixed Android release builds on newer Flutter SDKs by hiding Flutter's `Category` and `Summary` annotation exports where they collided with Koinly finance models.
- Fixed clean ZIP packaging on Windows so entries use GitHub-compatible `/` paths instead of literal backslash filenames.
- Ensured workflow files package as `.github/workflows/*.yml`, allowing GitHub Actions to detect them after upload.
- Continued Phase 13 source-structure cleanup by extracting shared icon lookup/rendering helpers into `lib/icon_helpers.dart`.
- Reduced `lib/main.dart` further by moving reusable icon glyph and icon bubble UI helpers out of the main app file.
- Continued Phase 12 source-structure cleanup by extracting reusable Koinly branding widgets into `lib/branding_widgets.dart`.
- Moved the shared `firstOrNull` collection extension into `lib/collection_utils.dart`.
- Continued Phase 11 source-structure cleanup by extracting `ReminderService` into `lib/reminder_service.dart`.
- Moved legacy Cloudflare sync, account sync API, and MongoDB snapshot sync helpers into `lib/sync_services.dart`.
- Removed notification/timezone/MongoDB implementation details from `lib/main.dart`, leaving the app controller/UI to consume service APIs.
- Continued Phase 10 source-structure cleanup by extracting preference/secure credential stores into `lib/persistence_stores.dart`.
- Moved shared sync error/session data types into `lib/sync_models.dart` so future sync-service extraction can happen without touching UI code.
- Continued Phase 9 source-structure cleanup by extracting shared UI foundation primitives into `lib/ui_foundation.dart`.
- Moved responsive breakpoints, motion constants, shape helpers, page transitions, pressable wrapper behavior, and optimized scroll behavior out of `lib/main.dart`.
- Started Phase 8 source-structure cleanup by extracting app configuration/constants into `lib/app_config.dart` and finance data models/helpers into `lib/models.dart`.
- Reduced the size of `lib/main.dart` and began separating the app into clearer layers so future analyzer/editor performance work can continue safely.
- Added Phase 7 validation reliability: the local validation helper now supports explicit timeouts for `flutter pub get`, `flutter analyze --fatal-infos`, and `flutter test`, plus skip flags for each stage.
- Validation now reports likely analyzer timeout causes clearly instead of hanging silently when the current large single-file Flutter app overwhelms analysis.
- Added Phase 6 validation and packaging cleanup so generated packages no longer include worker `node_modules`, Flutter build folders, local output folders, or transient logs.
- Added reusable `tool/package_project.ps1` and `tool/validate_project.ps1` helpers for clean ZIP creation and repeatable local validation.
- Added repository ignore/exclude rules for Worker dependency/cache folders and generated packaging outputs to keep analysis and release archives focused on source files.
- Added Phase 5 privacy-safe diagnostics reports that can be copied or shared from Data health.
- Diagnostics now summarize app version, platform, setup state, local data counts, sync status, pending uploads, conflicts, update state, and health findings without exposing tokens or backend secrets.
- Added Phase 4 diagnostics with Advanced settings → Data health for local data, sync backlog, sync conflicts, and skipped setup leftovers.
- Added a safe Data health cleanup action for untouched starter accounts that remain after the user skipped account setup.
- Added Phase 3 data safety: automatic local safety backups are created before manual restores, legacy cloud restores, full cloud-overwrite syncs, and server reset sync operations.
- Koinly now keeps the newest 3 safety backups and exposes Restore last safety backup in Advanced settings.
- Login/cloud-restore no longer clears local data before a successful cloud download; the app downloads first, saves a safety backup, then overwrites local finance data.
- Started Phase 2 polish by reducing desktop transitions, card animations, update-wave animation, gradients, and heavy shadows.
- Made desktop page headers more compact for a less oversized Windows layout.
- Started Phase 1 polish with clearer sync stages, explicit Restore cloud copy vs Upload local changes actions, and a Home empty-state recovery card for no-account/offline setups.
- Setup Login now signs in, cloud-overwrites local setup/default data, completes setup, and opens the app immediately.
- Persisted the Accounts setup Skip choice and added a safe cleanup for old installs where the untouched Cash/Card/Bank Account starter placeholders remained visible after skipping.
- Fixed setup-page Create account so it returns to setup instead of completing onboarding early and bouncing back later.
- Restore now automatically schedules an authoritative cloud upload when signed in, so restored data becomes the cloud source of truth.
- Added account-sync replace support so other devices fully clear local finance data before applying a restored cloud copy.
- Removed the Home Quick actions block for a cleaner dashboard.
- Fixed the onboarding account setup Skip action so untouched starter accounts are removed instead of staying in the app.
- Reduced route/tab motion and expensive background glow layers for smoother Android and Windows performance.
- Optimized Android release CI by generating the Universal APK from the AAB instead of running a duplicate universal APK build.
- Added a GitHub Releases-based in-app updater.
- Added Settings → Updates with installed version, latest release, update status, release date, and GitHub release changelog.
- Added Android APK architecture selection for ARM64, ARM32, x86_64, and Universal builds.
- Added in-app Android APK downloading with live progress, speed, downloaded size, and animated wave progress.
- Added Android installer handoff with FileProvider content URI support and install-from-this-source permission handling.
- Added Windows update handling that prefers installer assets before falling back to the GitHub release page.
- Updated release automation to publish semantic-version assets and use changelog text for release notes.
