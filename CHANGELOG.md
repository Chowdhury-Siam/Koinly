## [1.0.1189] - 2026-09-25

- Fixed the Note editor phone layout with compact button, text, and chip sizing so the date/time row no longer clips.
- Synchronized application and bundled Worker version metadata to `1.0.1189+233`.

## [1.0.1188] - 2026-09-24

- Removed the H1-H6 heading controls from the Note editor toolbar.
- Synchronized application and bundled Worker version metadata to `1.0.1188+232`.

## [1.0.1187] - 2026-09-24

- Fixed the Note editor dots menu so it opens as a compact icon menu instead of the oversized checked popup.
- Synchronized application and bundled Worker version metadata to `1.0.1187+231`.

## [1.0.1186] - 2026-09-24

- Made the Note editor controls functional: date chips open date picking, time chips open time picking, emoji opens a picker, and the tag/bookmark action gives feedback.
- Synchronized application and bundled Worker version metadata to `1.0.1186+230`.

## [1.0.1185] - 2026-09-24

- Updated the Note editor to match the June-style full-screen canvas with a large title prompt, date/time chips, tag action, hidden formatting tools, and a dots menu.
- Synchronized application and bundled Worker version metadata to `1.0.1185+229`.

## [1.0.1184] - 2026-09-24

- Removed the visible `is:Bookmarked` and `is:Draft` filter chips from the Note list.
- Synchronized application and bundled Worker version metadata to `1.0.1184+228`.

## [1.0.1183] - 2026-09-24

- Added June-style Note list features: search, Recent/More entries grouping, dated note cards, bookmark toggles, and draft/publish swipe actions.
- Notes now persist bookmark and draft state in the local database and local backup payload.
- Synchronized application and bundled Worker version metadata to `1.0.1183+227`.

## [1.0.1182] - 2026-09-24

- Changed Note add/edit from a centered popup to a full-screen editor page.
- Added June-style markdown editing controls for bold, italic, underline, strikethrough, highlight, links, quotes, bullets, inline code, headings, checklist insertion, emoji insertion, undo, and redo.
- Synchronized application and bundled Worker version metadata to `1.0.1182+226`.

## [1.0.1181] - 2026-09-24

- Added a Note feature from the transaction quick menu with local note list, add/edit popup, swipe edit/delete, and local backup/restore support.
- Reworked the centered date range picker to draw the selected span inline across calendar rows, making the chosen start and end dates visually connected.
- Fixed the new range calendar animation to use Koinly's existing `AppMotion.fast` duration.
- Synchronized application and bundled Worker version metadata to `1.0.1181+225`.

## [1.0.1180] - 2026-09-22

- Added saved self-hosted Sync Workers and saved account profiles so one installation can switch between multiple Worker/account combinations.
- Account switching now stages the target account first, downloads its full cloud history, creates a safety backup, then replaces local account-scoped finance data, preferences, profile media, credentials, and server cursor without using the normal merge sync path.
- Added Account & sync controls to switch accounts, add another account, validate a Worker, and create-and-switch to a new account without adopting the current local dataset.
- Stored automatic Worker deployment credentials per Worker while preserving legacy credential fallback.
- Fixed the Account & sync sign-out confirmation so the long keep/clear actions are centered, equal-width, and vertically aligned on phones instead of wrapping into a staggered right-aligned layout.
- Synchronized application and bundled Worker version metadata to `1.0.1180+224`.

## [1.0.1178] - 2026-09-21

- Collapsed the Self-hosted Sync Worker controls by default for signed-in accounts and added an animated top-right Worker settings toggle.
- Replaced the signed-in sync timestamp card title with the configured Cloudflare Worker name (or custom Worker host).
- Added a centered sign-out choice to keep the cloud account's data locally or clear only the device copy; either option leaves all cloud data untouched.
- Clearing local data after sign-out also removes local profile media, filters, defaults, and finance rows without queuing cloud deletions.
- Synchronized application and bundled Worker version metadata to `1.0.1178+222`.

## [1.0.1177] - 2026-09-21

- Added optional reminders to Plan items. Users can enable a reminder while adding or editing a plan and choose its date and time.
- Plan reminder timestamps are stored with the planned purchase, included in backup/cloud synchronization, restored on existing devices, and re-scheduled after sync or app restart.
- Plan cards show the configured reminder, and buying/deleting a plan automatically removes its pending notification.
- Added a dedicated Android notification channel for Plan reminders with exact-alarm fallback behavior.
- Migrated existing databases safely with a nullable `reminder_on` column; existing Plan items remain unchanged with reminders off.
- Synchronized application and bundled Worker version metadata to `1.0.1177+221`.

## [1.0.1176] - 2026-09-21

- Fixed profile-photo flashing when returning to Categories by keeping the decoded static avatar image live in Flutter's image cache across tab rebuilds.
- Profile photo widgets now render the existing fallback avatar while an image frame is decoding instead of exposing an empty circular field.
- Profile-media replacement and cloud download prime the new avatar before switching the cached provider, preventing navigation and sync refreshes from clearing the visible photo first.
- Synchronized application and bundled Worker version metadata to `1.0.1176+220`.

## [1.0.1175] - 2026-09-21

- Fixed the Android status-bar notification icon appearing as a solid white circle by adding a dedicated monochrome Koinly `K` notification icon.
- Applied the status icon to daily expense reminders, loan reminders, Flutter update notifications, native background update notifications, and Android default notification metadata.
- Kept the full-color launcher/adaptive icon unchanged; only Android's small notification icon now uses the required transparent monochrome resource.
- Synchronized application and bundled Worker version metadata to `1.0.1175+219`.

## [1.0.1174] - 2026-09-20

- Added a persistent Transaction sort control with newest/oldest, category, amount, and title ordering. Changing the sort rebuilds a fresh list immediately, so existing transactions are reorganized without rewriting financial data.
- Fixed legacy transaction ordering by using the visible transaction start timestamp (`createdOn`) rather than historical range-end metadata (`endOn`/`listOn`) for date sorting.
- Applied the selected transaction ordering consistently to category transaction lists and synchronized the preference through Koinly settings sync.
- Synchronized application and bundled Worker version metadata to `1.0.1174+218`.

## [1.0.1173] - 2026-09-18

- Fixed transaction history ordering so the complete transaction date/time is sorted newest-first.
- Transactions on the same day now correctly show late-evening entries above afternoon entries.
- Synchronized application and bundled Worker version metadata to `1.0.1173+217`.

## [1.0.1172] - 2026-09-18

- Fixed transaction time ordering so each calendar day remains newest-first while transactions inside that day are listed chronologically from earlier to later.
- Transactions at 12:57 PM now correctly appear above transactions at 11:01 PM when they share the same date.
- Applied the ordering in the shared filtered transaction list so Transaction and category transaction screens stay consistent, with deterministic tie-breaking for identical timestamps.
- Synchronized application and bundled Worker version metadata to `1.0.1172+216`.

## [1.0.1171] - 2026-09-18

- Fixed the desktop **Category spending** hover field so its hover/focus surface spans the complete category row width instead of stopping at the card's horizontal content inset.
- Preserved the existing 18 px content alignment by moving horizontal spacing into each `ListTile`, while keeping the card's vertical breathing room unchanged.
- Kept the shared amount-column progress-width fix from 1.0.1170 intact and synchronized application and bundled Worker version metadata to `1.0.1171+215`.

## [1.0.1170] - 2026-09-16

- Fixed the Home **Category spending** layout so every progress track uses the same available width regardless of the formatted amount length.
- Added a shared dynamically measured amount column so longer currency values no longer shorten only their own progress track on Windows or responsive layouts.
- Synchronized application and bundled Worker version metadata to `1.0.1170+214`.

## [1.0.1169] - 2026-09-16

- Fixed returning users being left on first-run onboarding after a successful existing-account login.
- Existing-account authentication now marks onboarding complete in the controller, independent of the login screen route.
- Added startup recovery for valid persisted sync sessions created by older builds, while preserving the Restore/Start new choice for newly registered accounts.
- Synchronized application and bundled Worker version metadata to `1.0.1169+213`.

## [1.0.1168] - 2026-09-16

- Show an explicit `Administrator` title under the first account in both the in-app Worker Profile and the `/profile` website.
- Make administrator identity strictly follow the earliest account in the Worker database and repair stale cached administrator ownership automatically.
- Return `administratorUserId` from the profile accounts API and pin the administrator to the top of the account list for deterministic rendering.
- Added backward-compatible administrator detection for a single-account Worker when talking to an older profile API.
- Synchronized application and bundled Worker version metadata to `1.0.1168+212`.

## [1.0.1167] - 2026-09-16

- Moved Android closed-app update checks to a native WorkManager worker so update notifications no longer depend on starting a headless Flutter/plugin isolate.
- Added an in-app Worker Profile administration screen with administrator login, account creation, username changes, password changes, account deletion, and refresh/sign-out actions.
- Profile now appears only when the saved self-hosted Worker endpoint has been validated; managed-registration links open the same in-app Profile screen.
- Synchronized application and bundled Worker version metadata to `1.0.1167+211`.

## [Unreleased]

## [1.0.1166] - 2026-09-16

- Fixed cross-platform release compilation in `worker_deployment.dart` by using the namespaced `dart:math` `min` function when batching Turso schema statements.
- Synchronized application and bundled Worker version metadata to `1.0.1166+210`.

## [1.0.1165] - 2026-09-16

- Added **Settings > Profile** for validated self-hosted Workers. It opens that Worker's `/profile` page so users can sign in and manage their Worker account from the app settings flow.
- The **Profile** setting is hidden until a Cloudflare Worker URL has been successfully validated and saved through **Account & sync**, so an unconfigured app never shows a broken profile destination.
- Synchronized application and bundled Worker version metadata to `1.0.1165+209`.

## [1.0.1164] - 2026-09-16

- The first Koinly account created in the Worker database is now the `/profile` administrator; separate `ADMIN_USERNAME` and `ADMIN_PASSWORD` deployment credentials were removed from in-app and GitHub deployments.
- Added **Change username** to the Worker account manager. Renaming an account preserves its user ID and synchronized data, and renaming the first account keeps its administrator role.
- Prevented deletion of the first-account administrator so Worker administration and encrypted deployment recovery cannot be orphaned.
- Updated deployment recovery payloads to version 2 so Cloudflare, Turso, JWT, Worker URL, and version values can be restored after reinstall when the first account signs in, without storing separate administrator credentials.
- Restyled the Worker `/profile` website to the current Koinly app palette, including the charcoal dark surfaces, light surfaces, and `#00BD91` accent.
- Fixed automatic and manual Worker redeployments failing with `migration must include a new_tag because old_tag is set`. Code-only updates now send the existing Durable Object migration tag as both `old_tag` and `new_tag`, including the one-time migration-state retry.
- Added mocked HTTP deployment tests covering existing Workers, first deployments, migration-state recovery, declarative exports, and automatic updates.
- Synchronized application and bundled Worker version metadata to `1.0.1164+208`.

## [1.0.1163] - 2026-09-16

- Fixed Android reminder notifications not firing because the scheduled-notification receiver components required by `flutter_local_notifications` 16+ were missing from the app manifest.
- Fixed reminder times being interpreted as UTC by explicitly binding the `timezone` package to Android's current device time zone, with an offset fallback for OEM-specific zone IDs.
- Daily and loan reminders now use exact `AlarmManager` delivery while allowed, request Android's **Alarms & reminders** special access when a user enables the daily reminder, and safely fall back to inexact allow-while-idle delivery if exact access is denied.
- Existing enabled daily reminders are recreated on app startup, repairing schedules made by older builds and schedules invalidated by package replacement.
- Synchronized application and bundled Worker version metadata to `1.0.1163+207`.

## [1.0.1162] - 2026-09-15

- Added **Settings > Permissions > Ignore Battery Optimization** on Android, with live permission-state refresh when returning from Android settings.
- Added a native Android battery-optimization settings bridge so users can mark Koinly unrestricted and reduce background update/subscription delays caused by Doze or aggressive OEM power management.
- Notification-enabled settings now request Android notification permission again when the user explicitly enables them.
- Removed the unused exact-alarm permission and stripped generated/machine-specific Flutter and Android local configuration from the packaged repository.
- Synchronized application and bundled Worker version metadata to `1.0.1162+206`.

## [1.0.1161] - 2026-09-15

- Added encrypted deployment-value recovery for Workers deployed from Koinly. After reinstalling the app, paste and validate the same Worker URL and sign in with the first sync account; Koinly restores the saved Cloudflare/Turso/JWT deployment profile to secure storage automatically.
- Restricted deployment recovery to the first sync account and encrypted the remote recovery payload before storing it in Turso. The raw administrator password is still never stored or recoverable.
- Kept automatic Worker updates working after reinstall by restoring the deployment profile before checking the Worker version.
- Updated the README and Worker documentation and synchronized application/Worker version metadata to `1.0.1161+205`.

## [1.0.1160] - 2026-09-15

- Fresh self-hosted Workers now allow the first Koinly sync account to be created directly from **Account & sync**, even when `/profile` administrator credentials are configured.
- After the first sync account exists, later app registration remains administrator-managed and continues to redirect account creation to `/profile`.
- Removed the prefilled `koinly-sync` Worker name and `worker-admin` administrator username from the in-app deployment form; both fields now start empty on a fresh deployment.
- Updated the README and Worker documentation for the first-account flow and synchronized application/Worker version metadata to `1.0.1160+204`.

## [1.0.1159] - 2026-09-14

- Fixed in-app Cloudflare Worker updates failing when an existing `SyncHub` Durable Object had already applied the `v1-realtime-sync-hub` migration.
- Koinly now reads the latest Cloudflare Worker version detail to recover the currently applied Durable Object migration tag and sends it back as `old_tag` on subsequent uploads, preserving the existing namespace and data.
- Added a one-time safe retry when Cloudflare reports a migration-tag precondition mismatch, using Cloudflare's expected tag instead of requiring the Worker to be deleted or recreated.
- Synchronized application and Worker version metadata to `1.0.1159+203`.

## [1.0.1158] - 2026-09-14

- Fixed first-time in-app Cloudflare deployments being reported as failed when the `workers.dev` route needed longer than one minute to finish propagating.
- Worker health verification now waits substantially longer, reports intermediate propagation status, and preserves the actual HTTP/database/schema/runtime reason when a deployment never becomes healthy.
- In-app deployments now bind Turso's equivalent HTTPS endpoint to the Cloudflare Worker runtime while continuing to accept the canonical `libsql://...turso.io` URL in the setup form.
- Synchronized application and Worker version metadata to `1.0.1158+202`.

## [1.0.1157] - 2026-09-14

- Fixed in-app Turso validation incorrectly rejecting valid database credentials with HTTP 404. Koinly now validates Turso through the same authenticated Hrana `/v2/pipeline` endpoint used for schema provisioning, using a read-only `SELECT 1` connection check.
- Improved Turso deployment errors so authentication failures, missing database endpoints, and other HTTP failures are reported separately.
- Added a deployment contract regression check that prevents the unsupported Turso `/version` probe from returning.
- Synchronized application and Worker version metadata to `1.0.1157+201`.

## [1.0.1156] - 2026-09-14

- Added automatic self-hosted Worker updates for Workers deployed through **Settings > Account & sync > Deploy Database**.
- The app can now securely retain the Cloudflare/Turso deployment profile on-device, while storing only the derived administrator password verifier rather than the raw administrator password.
- On the first launch after a newer Koinly app update, Koinly compares the active Worker's reported version with the Worker bundled into the app and redeploys only when the bundled Worker is newer.
- Added Worker version reporting to `/health`, automatic update progress/error reporting in **Account & sync**, retry support, and a control to forget saved deployment credentials.
- GitHub-based Worker deployment now verifies that its Worker version matches the app release version before deployment.
- Updated the README and Worker documentation for the automatic redeployment flow and synchronized application version metadata to `1.0.1156+200`.

## [1.0.1155] - 2026-09-14

- Added **Settings > Account & sync > Deploy Database** as a second self-hosted Worker deployment path alongside GitHub Actions.
- Added an in-app deployment guide and form for Cloudflare Worker name/account/token, Turso database URL/token, JWT secret, and Worker administrator credentials.
- In-app deployment now validates Cloudflare and Turso, applies the current Turso schema and legacy migrations, derives the administrator password verifier locally, uploads the bundled Worker, enables the workers.dev route, configures the five-minute scheduler, and waits for the full Worker health contract.
- Deployment failures are shown directly on the deployment page; successful deployment automatically returns the Worker URL to **Account & sync** and validates/enables it.
- Deployment credentials entered in the app are not persisted; official release builds now embed a deployable Worker bundle generated from the current `cloud/worker` source.
- Updated the README for both supported Worker deployment methods and synchronized application version metadata to `1.0.1155+199`.

## [1.0.1154] - 2026-09-14

- Refreshed the public README so it documents the current Koinly experience instead of calling out features that were removed in earlier versions.
- Updated self-hosted account password-reset documentation to describe the current `/profile` administrator flow directly.
- Removed stale README wording around the retired in-app recovery flow and legacy email-login migration.
- Simplified credential and Analytics documentation to describe where current controls live without listing removed UI elements.
- Corrected the README profile-media security note to match authenticated Worker media synchronization.
- Synchronized application version metadata to `1.0.1154+198`.

## [1.0.1153] - 2026-09-14

- Removed the extra transaction-history explanatory copy from Analytics export UI.
- Synchronized application version metadata to `1.0.1153+197`.

## [1.0.1152] - 2026-09-14

- Simplified **Archive > Local backup file > Local** so its outside status now shows only **On** or **Off**, matching the cloud backup indicators.
- Synchronized application version metadata to `1.0.1152+196`.

## [1.0.1151] - 2026-09-14

- Renamed **Local backup File** to **Local backup file** in Archive.
- Renamed the Archive **Cloud** section to **Analytics backup**, and renamed the analytics **Cloud Backup** entry/page to **Cloud**.
- Added outside **On/Off** indicators to both Archive cloud entries: backup-file cloud delivery and analytics-report cloud delivery. The indicators refresh from the Worker and refresh again after returning from either cloud settings page.
- Synchronized application version metadata to `1.0.1151+195`.

## [1.0.1150] - 2026-09-14

- Reduced Android release wall-clock time by building the universal, ARM32, and ARM64 APKs concurrently instead of rebuilding the ABI outputs sequentially in one job, while using the GitHub runner's preinstalled Android toolchain and cache-first Dart dependency resolution.
- Reduced macOS release overhead with separated dependency/build caches, deduplicated parallel AppIcon generation, disabled compiler indexing during release compilation, and concurrent fast-compression DMG/ZIP packaging.
- Preserved the existing three standalone Android APKs and universal Intel + Apple Silicon macOS release outputs.
- Synchronized application version metadata to `1.0.1150+194`.

## [1.0.1149] - 2026-09-14

- Reorganized Archive backup-file scheduling: **Automatic backup** is now **Local backup File**, **Local Backup** is now **Local**, and **Telegram Backup** is now **Cloud**.
- Expanded **Archive > Cloud** so `.koinlybackup` files can be scheduled or uploaded manually to either Telegram or Google Drive using credentials from **Settings > Credential**.
- Added an independent Google Drive `.koinlybackup` schedule. Telegram backup, Google Drive backup, Telegram report, and Google Drive report schedules are all enforced at least 5 minutes apart.
- Google Drive backup uses the configured Drive Folder ID when present; otherwise the Worker creates/reuses a dedicated **Koinly Backup** folder.
- Synchronized application version metadata to `1.0.1149+193`.

## [1.0.1148] - 2026-09-14

- Removed redundant helper copy from Archive backup tiles and Profile media.
- Synchronized application version metadata to `1.0.1148+192`.

## [1.0.1147] - 2026-09-14

- Renamed **Automatic local backup** to **Local Backup** throughout the active app UI and current documentation without changing backup scheduling or behavior.
- Synchronized application version metadata to `1.0.1147+191`.

## [1.0.1146] - 2026-09-14

- Removed the Google Drive Folder ID instructional helper copy from Settings > Credential without changing folder selection behavior.
- Synchronized application version metadata to `1.0.1146+190`.

## [1.0.1145] - 2026-09-14

- Removed the redundant second "Last synced" line from Settings > Account & sync; the primary sync status now shows the sync timestamp only once.
- Synchronized application version metadata to `1.0.1145+189`.

## [1.0.1144] - 2026-09-14

- Removed redundant helper/descriptive copy from reminder, theme, date-filter, credentials, Telegram Backup, Analytics, and Cloud Backup interfaces while preserving the underlying behavior and validation.
- Kept the 5-minute automatic-upload separation enforcement in the Self-Hosted Worker; only the repeated on-screen warning text was removed.
- Synchronized application version metadata to `1.0.1144+188`.

## [1.0.1143] - 2026-09-14

- Added an optional **Google Drive Folder ID** field to **Settings > Credential > Google Drive**. When set, both manual Analytics uploads and scheduled Cloud Backup reports are uploaded directly into that folder; when blank, Koinly continues to create/reuse **Koinly Analytics**.
- Folder IDs are validated by the Worker, custom folders are checked for accessibility/write permission during OAuth connection, and Shared Drive uploads use `supportsAllDrives`. Changing the configured folder forces a fresh Google authorization so the required scope cannot stay stale.
- Google OAuth now keeps the limited `drive.file` scope for the default Koinly-managed folder and requests the broader Drive scope only when a user explicitly configures an existing Folder ID.
- Renamed **Automatic Telegram backup** to **Telegram Backup** throughout the active app UI and current documentation without changing its scheduling or `.koinlybackup` behavior.
- Added the `google_folder_id` Turso schema migration and synchronized application version metadata to `1.0.1143+187`.

## [1.0.1142] - 2026-09-14

- Added **PDF**, **XLSX**, and **TXT** as selectable Analytics report formats for both Summary and Transaction history exports.
- Manual Analytics download, Telegram upload, and Google Drive upload now use the selected report format and correct filename/MIME type.
- Added a per-destination file-format selector to **Settings > Archive > Cloud Backup** so Telegram and Google Drive schedules can independently generate PDF, XLSX, or TXT reports.
- Extended the Self-Hosted Sync Worker and Turso schedule schema to persist report format, generate scheduled XLSX/TXT reports, validate manual uploads by format, and default existing schedules safely to PDF.
- Preserved the existing date filters, custom ranges, schedule cadence, and pairwise five-minute separation across Telegram reports, Google Drive reports, and Telegram `.koinlybackup` uploads.
- Synchronized application version metadata to `1.0.1142+186`.

## [1.0.1141] - 2026-09-14

- Removed the redundant instructional copy from **Archive > Automatic local backup**, including the folder, retention, encrypted-file, and reopen-to-catch-up explanations.
- Replaced Android's foreground/resume-only automatic local backup behavior with a native Android WorkManager job so due local backups can be created while the Koinly UI is closed.
- The background worker reads the current SQLite data and saved backup preferences, writes the same version-7 encrypted `.koinlybackup` format through the persisted Android Storage Access Framework folder grant, applies the existing latest-only/history retention choice, and reports last-backup/error state back to the app.
- Non-Android automatic local backup behavior remains unchanged.
- Synchronized application version metadata to `1.0.1141+185`.

## [1.0.1140] - 2026-09-14

- Replaced custom date-range flows with one centered Koinly range popup that reuses the transaction editor's **Use range** interaction: select Start/End inside the same calendar and apply the range once.
- Applied the centered custom-range picker globally to the main date filter, Analytics, the default date filter in Settings, and automatic Analytics PDF schedules.
- Replaced the automatic PDF date-filter dropdown with the centered **Choose Date Filter** popup and added **Custom range** alongside Today, This Week, This Month, This Year, and All Time.
- Added Worker/Turso support for persisted custom start/end dates so scheduled Telegram and Google Drive PDFs use the exact selected custom range.
- Added a safe schema migration for existing `analytics_pdf_schedules` tables while preserving current schedules and the five-minute automatic-upload separation rule.
- Synchronized application version metadata to `1.0.1140+184`.

## [1.0.1139] - 2026-09-14

- Reorganized **Settings > Archive** so **Automatic local backup** and **Automatic Telegram backup** now appear together under one **Automatic backup** section.
- Kept manual **Backup** and **Load backup** together under **Local**, while **Cloud Backup** remains under **Cloud**.
- No backup behavior, credentials, schedules, or five-minute cloud-upload separation rules were changed.
- Synchronized application version metadata to `1.0.1139+183`.

## [1.0.1138] - 2026-09-14

- Removed the redundant **Telegram destination** credential/status card from **Archive > Automatic Telegram backup**.
- Automatic Telegram backup continues to use the Telegram bot credentials configured exclusively in **Settings > Credential**.
- Kept the existing credential validation, schedule controls, status, manual backup action, and five-minute automatic-upload separation rules unchanged.
- Synchronized application version metadata to `1.0.1138+182`.

## [1.0.1137] - 2026-09-14

- Reorganized Settings into **General**, **Data & cloud**, and **App** groups so related controls are easier to locate.
- Added **Settings > Credential** as the only in-app place to configure the Telegram bot token/destination and Google Drive OAuth credentials/connection.
- Added **Settings > Archive** and moved **Backup**, **Automatic local backup**, and **Load backup** out of Advanced settings.
- Moved **Automatic Telegram backup** out of Account & sync and into Archive; its page now manages only backup scheduling/status while using Telegram credentials from Settings > Credential.
- Added **Archive > Cloud Backup** for automatic Analytics PDF schedules to Telegram and Google Drive; credential editing was removed from Analytics/cloud scheduling.
- Removed the Telegram backup action from Account & sync and removed the Telegram/Drive configuration icons from the Analytics app bar. Manual Analytics PDF uploads continue to use the credentials configured in Settings > Credential.
- Preserved Worker-side pairwise minimum five-minute separation across automatic Telegram PDF, Google Drive PDF, and Telegram `.koinlybackup` schedules.
- Synchronized application version metadata to `1.0.1137+181`.

## [1.0.1136] - 2026-09-13

- Added an inline eye button to every password field in the self-hosted Worker website, including administrator sign-in, account creation, and password reset/change dialogs.
- Password visibility toggles are keyboard accessible, preserve the field value and focus, update their accessible Show/Hide label, and always reset to hidden when credential forms reopen or submit.
- Synchronized application version metadata to `1.0.1136+180`.

## [1.0.1135] - 2026-09-13

- Added configurable automatic Analytics PDF delivery schedules for both Telegram and Google Drive, with separate report type, date filter, daily/weekly/monthly cadence, and delivery time settings.
- Automatic PDFs are generated by the Self-Hosted Sync Worker from the latest synchronized Koinly data, so scheduled delivery does not require the app to stay open.
- Enforced a minimum five-minute separation between every enabled automatic upload time: Telegram Analytics PDF, Google Drive Analytics PDF, and Telegram `.koinlybackup`. Conflicting schedules are rejected by the Worker as well as explained in the app.
- Disconnecting Google Drive now disables its automatic PDF schedule while preserving the rest of the Analytics upload configuration.
- Synchronized application version metadata to `1.0.1135+179`.

## [1.0.1134] - 2026-09-13

- Replaced the Analytics Daily/Weekly/Monthly/Yearly selector with the standard **Choose Date Filter** flow: Today, This Week, This Month, This Year, All Time, and Custom.
- Transaction history PDFs now obey the selected Analytics date filter instead of always exporting every stored transaction; selecting **All Time** restores the full-ledger behavior.
- Added a Telegram bot shortcut beside the Analytics cloud/Drive upload-settings icon.
- Updated Analytics PDF filenames, Telegram captions, empty-state text, and documentation so the selected date filter is carried through consistently.
- Synchronized application version metadata to `1.0.1134+178`.

## [1.0.1133] - 2026-09-13

- Removed the Analytics **Share PDF** action and its analytics-only share-sheet code.
- **Download PDF**, **Upload Telegram**, and **Upload Drive** remain available for both Summary and Transaction history PDF variants.
- Synchronized application version metadata to `1.0.1133+177`.

## [1.0.1132] - 2026-09-13

- Simplified the Analytics screen by keeping comparison, activity, budgets, category breakdowns, and current account snapshots in the PDF instead of duplicating them on-screen.
- Added two PDF report variants: the existing period Summary and a new complete Transaction history report containing every stored transaction.
- Added previous-period comparison details to the Summary PDF so all removed Analytics detail remains available in the exported report.
- Transaction history PDFs include totals plus each transaction's date/time, type, amount, title, category, account path, notes, and report-exclusion status, and work with download, share, Telegram, and Google Drive uploads.
- Synchronized application version metadata to `1.0.1132+176`.

## [1.0.1131] - 2026-09-13

- Fixed Self-Hosted Sync Worker TypeScript compilation with TypeScript 5.9 by keeping Analytics PDF byte arrays explicitly backed by `ArrayBuffer` before passing them to `Blob`.
- This fixes the `Uint8Array<ArrayBufferLike>` / `BlobPart` errors in Telegram and Google Drive Analytics PDF uploads.
- Synchronized application version metadata to `1.0.1131+175`.

## [1.0.1130] - 2026-09-13

- Replaced the persistent Account & sync registration error with a centered administrator-registration prompt.
- When Worker-managed registration blocks app signup, the prompt asks whether to create the account from the admin panel and offers only **Yes** and **No** actions.
- **Yes** opens the configured self-hosted Cloudflare Worker at `/profile`; **No** simply closes the prompt.
- Worker-managed registration failures no longer remain visible as a red sync error on the Account & sync status card.
- Added the `REGISTRATION_MANAGED` Worker error code while retaining message-based compatibility with older deployed Workers.
- Bumped application metadata to `1.0.1130+174`.

## [1.0.1129] - 2026-09-13

### Removed

- Completely removed the in-app **Forgot password** flow from Account & sync.
- Removed the recovery-key popup, recovery-key rotation control, and the client-side recovery API code that existed only for in-app password recovery.
- Account password recovery is now handled from the Self-Hosted Sync Worker's `/profile` administration page.
- Kept the Worker's legacy recovery endpoints intact for backward compatibility with older Koinly app versions.
- Bumped application metadata to `1.0.1129+173`.

## [1.0.1128] - 2026-09-13

- Removed the requested explanatory helper text from Account & sync and Telegram backup without changing the underlying sync, account, backup, or scheduling behavior.
- Tightened spacing where the removed copy previously occupied layout space.
- Bumped application metadata to `1.0.1128+172`.

# Changelog

## [1.0.1127] - 2026-09-13

### Fixed

- Added clear, consistent outlines to the Daily, Weekly, Monthly, and Yearly cards in the subscription Repeat picker.
- The selected repeat option now uses a stronger accent outline while unselected options retain a subtle theme-aware border.
- Bumped application metadata to `1.0.1127+171`.

## [1.0.1126] - 2026-09-13

### Added

- Added direct **Upload Telegram** and **Upload Drive** actions to Analytics PDF reports. These now upload through the authenticated Self-Hosted Sync Worker instead of relying only on the device share sheet.
- Telegram Analytics uploads reuse the existing encrypted Telegram-backup bot token and destination, so no duplicate Telegram configuration is required and automatic Telegram backups may remain disabled.
- Added Google Drive connection settings for Analytics. Users configure their own Google OAuth Web application once, authorize their Google account in the browser, and Koinly uploads reports into a dedicated **Koinly Analytics** folder using the limited `drive.file` scope.
- Added Worker-side encrypted storage for the Google OAuth Client Secret and refresh token, OAuth callback handling, token refresh, Drive folder creation, and PDF upload endpoints.
- Added Worker health/deployment capability reporting for Analytics uploads and schema support for the new encrypted upload settings.

### Changed

- Account deletion now also removes stored Analytics upload credentials while leaving files already sent to Telegram or Google Drive untouched.
- Bumped application metadata to `1.0.1126+170`.

## [1.0.1125] - 2026-09-13

### Added

- Added **Settings > Analytics** with Daily, Weekly, Monthly, and Yearly summaries. Each period reports income, expense, net cash flow, transaction activity, transfers, savings movement, loan/repayment activity, applicable budgets, top income/expense categories, and a current account-balance snapshot.
- Added previous-period comparisons and period navigation/date selection so historical summaries can be reviewed without changing the app-wide default date filter.
- Added local PDF report generation with **Download PDF** and **Share / upload** actions. The share flow uses the device share sheet so the PDF can be sent to Telegram, Google Drive, or another compatible app without adding separate cloud credentials to Koinly.

### Changed

- Removed obsolete fallback positioning parameters from the now-static category breakdown badge widget. Static collision-packed placement and tap-to-select remain unchanged.
- Bumped application metadata to `1.0.1125+169`.

## [1.0.1124] - 2026-09-13

### Changed

- Completely removed manual movement/dragging for the category breakdown percentage bubbles. They are now positioned only by the automatic collision-free layout and cannot be dragged with touch, mouse, or trackpad input.
- Removed the saved per-bubble drag-position state, drag gesture handlers, drag cursor treatment, and dragging visual state while preserving the existing static bubble layout and tap-to-select behavior.
- Bumped application metadata to `1.0.1124+168`.


## [1.0.1123] - 2026-09-13

### Fixed

- Fixed the remaining category-bubble coupling seen after `1.0.1122`: a dragged bubble's saved position could be reused as a collision-packing anchor during a later parent rebuild, which caused untouched bubbles to shift around it.
- The automatic collision-free layout is now calculated only from the donut slice geometry. Saved drag positions are applied afterward per bubble, so moving one bubble cannot recalculate, push, pull, or reposition any other bubble.
- Bumped application metadata to `1.0.1123+167`.


## [1.0.1122] - 2026-09-13

- Fixed category-breakdown bubble dragging so each percentage bubble moves completely independently. Dragging one bubble no longer checks, follows, slides around, or reacts to neighboring bubbles.
- Kept the initial automatic collision-free layout from `1.0.1120`, while manual drag movement is now constrained only by the breakdown chart bounds.
- Bumped application metadata to `1.0.1122+166`.


## [1.0.1121] - 2026-09-13

### Changed

- Replaced the dark-mode app/page background gradient with a single neutral near-black `#0F1217` canvas, matching the flatter desktop reference while preserving all existing card, surface, navigation, control, chart, and content styling.
- Applied the same solid dark canvas through the shared theme background so splash, setup, main pages, and routed screens no longer fall back to the previous green gradient.
- Bumped application metadata to `1.0.1121+165`.


## [1.0.1120] - 2026-09-13

### Fixed

- Fixed the category breakdown percentage bubbles initially stacking on top of each other when several small categories occupy nearly the same donut-chart angle. The default badge layout now performs bounded collision packing before painting, preserving the slice-driven placement while separating dense clusters into readable positions.
- Dragged breakdown bubbles can no longer be moved through or dropped on top of another percentage bubble. Drag motion now stops or slides along neighboring badges while remaining constrained inside the breakdown card.
- Preserved custom dragged positions and the existing selected/dragging visual treatment while adding an 8 px collision gap between badge hit areas.
- Bumped application metadata to `1.0.1120+164`.


## [1.0.1119] - 2026-09-13

### Fixed

- Restored automatic Self-Hosted Sync Worker deployment for fork repositories on every push to `main` or `master`, including app-only updates that can change the client/Worker API contract. Canonical repository pushes remain excluded by the existing job guard, while manual deployment remains available.
- Fixed a deployment race where the health check stopped at the first reachable HTTP 200 and could validate Cloudflare's previous Worker version during propagation. It now waits for the complete current capability contract, including `profileMediaSyncAvailable=true`, before passing.
- Improved the final deployment error so a genuinely stale/outdated Worker is distinguished from temporary Cloudflare propagation.
- Bumped application metadata to `1.0.1119+163`.


## [1.0.1118] - 2026-09-13

### Fixed

- Fixed the misleading `Sync pending • Waiting for internet` state. A pending
  outbox no longer claims that the device has no internet; Koinly now
  distinguishes Worker timeouts, Worker reachability/transport failures, Worker
  errors, and ordinary queued retries.
- Made background sync preserve the real failure message and error code so the
  Account & sync screen and diagnostics can explain why changes are still
  queued instead of hiding silent retry failures.
- Reset the shared HTTP client after Android socket/client/timeout failures so a
  stale pooled connection after Wi-Fi/mobile-network changes cannot keep sync
  stuck while other apps still have internet access.
- Reduced finance upload batches from 100 to 25 operations per Worker request.
  This keeps Turso write transactions smaller and lets large local backlogs
  drain reliably on higher-latency self-hosted deployments while preserving
  idempotent operation IDs.
- Improved Data health backlog findings to show the last sync failure when one
  exists, and made profile-media transfer failures visible instead of reducing
  them to a generic pending state.
- Bumped application metadata to `1.0.1118+162`.


## [1.0.1117] - 2026-09-13

### Fixed

- Restricted Android, Windows, Linux, and macOS release build jobs to the
  canonical `Chowdhury-Siam/Koinly` repository for both push and manual
  workflow runs, so fork repositories cannot build application release
  packages with the inherited workflow.
- Kept the separate Self-Hosted Sync Worker workflow unchanged so fork owners
  can still deploy their own sync Worker.
- Bumped application metadata to `1.0.1117+161`.


## [1.0.1116] - 2026-09-13

### Changed
- Increased profile-media cloud transfer chunks from 512 KiB to 10 MiB while retaining the existing 50 MB maximum media size.
- Increased the self-hosted Worker encoded-chunk validation limit to match 10 MiB binary chunks after Base64 encoding.
- Bumped application metadata to `1.0.1116+160`.

## [1.0.1115] - 2026-09-13

### Changed
- Removed the empty-profile helper sentence under the profile avatar.
- Removed the file-format/size helper line below the Add media button while keeping the existing media validation and upload limits unchanged.
- Bumped application metadata to `1.0.1115+159`.

## [1.0.1114] - 2026-09-13

### Fixed
- Fixed profile media getting stranded on the device where it was selected: photo/GIF/video uploads, framing changes, and removals now keep cloud retry state pending until the self-hosted sync pass can retry them.
- Opening Profile now forces an immediate account sync so another device checks for the latest profile media instead of waiting for the normal realtime/fallback interval.
- Reduced profile-media transfer chunks from 1 MiB to 512 KiB, keeping 50 MB support while making Worker-to-Turso uploads/downloads more reliable on constrained HTTP/database paths.
- Added explicit `profileMediaSyncAvailable` Worker capability reporting and deployment validation. Old Workers now produce a clear update-required sync error instead of silently leaving Device B on the default avatar.
- Bumped application metadata to `1.0.1114+158`.

### Deployment required
- **Redeploy the latest self-hosted Cloudflare Worker** so profile-media endpoints, tables, realtime notifications, and the new capability check are guaranteed to be present. The standard deployment workflow applies the schema automatically.

## [1.0.1113] - 2026-09-13

### Changed
- Made the Home Net Balance sparkline animation substantially more noticeable with a faster travelling wave, stronger vertical motion, and a synchronized line/fill pulse while preserving reduced-motion behavior.
- Bumped application metadata to `1.0.1113+157`.

## [1.0.1112] - 2026-09-13

- Reworked the Transaction quick menu into a vertical stack with Subscription above Plan.
- Added a staged opening sequence: Plan appears first, then Subscription; closing runs in exact reverse order.
- Preserved the blurred backdrop, menu/close morph, touch targets, desktop hover behavior, and existing navigation actions.
- Bumped application metadata to `1.0.1112+156`.

## [1.0.1111] - 2026-09-13

### Changed
- Category breakdown percentage bubbles can now be dragged freely with mouse or touch while remaining fully constrained inside the breakdown chart surface.
- Dragged bubbles are raised visually during movement and keep their custom position while the breakdown view remains mounted.
- Bumped application metadata to `1.0.1111+155`.


## [1.0.1110] - 2026-09-13

### Changed
- Switched the Flutter app typography to an Apple-style SF Pro Display font stack across the full UI.
- Switched the self-hosted Worker administration website to the same SF Pro Display/SF Pro Text system font stack.
- Preserved platform fallbacks for systems where Apple's SF fonts are not installed.
- Bumped application metadata to `1.0.1110+154`.

## [Unreleased]

### Added

- Integrated `ADMIN_USERNAME` and `ADMIN_PASSWORD` into the main eight-value setup checklist and subsequent instructions. The GitHub deployment workflow hashes the administrator password automatically; no separate hash-generation page or command is needed.
- Added the self-hosted Worker's authenticated `/profile` administration portal: account counts, paginated account lists, usernames, creation dates, Active/Invited status, manual account creation, password resets, and confirmed account deletion. The responsive dashboard follows Koinly's emerald colors, rounded cards, inputs, buttons, light/dark themes, transitions, and reduced-motion preferences.
- Added administrator login using `ADMIN_USERNAME` and `ADMIN_PASSWORD` repository secrets, with automatic salted hashing before deployment. Ordinary sync accounts cannot access the portal. The UI displays clear success, invalid-login, duplicate-username, and server/database error messages.
- Added revocable, one-hour administrator sessions with secure HttpOnly cookies, same-origin protection, login throttling, private responses, and a restrictive content security policy. New account passwords use salted PBKDF2 hashes; password resets revoke access/refresh sessions and the previous recovery key. Account deletion removes related cloud records atomically.

### Fixed

- Android Photos and videos permission is no longer requested during startup or onboarding. Koinly now asks for media access only after the user explicitly taps the profile-photo/media upload action.

### Deployment required

- **Users who already have a self-hosted Cloudflare Worker MUST redeploy their Worker after updating to receive the new `/profile` dashboard and account-management functionality. Updating the app alone is not enough.** Run the latest **Deploy Self-Hosted Sync Worker** workflow, which safely applies the schema migration, and provide all eight setup values documented in the README. Manual deployments must apply the latest schema before redeploying.
- Configuring administrator credentials closes public app registration. Create further accounts in `/profile`; existing accounts continue to use Login. The administrator identity is separate from sync accounts and remains available after deleting the last sync account.


## [1.0.1109] - 2026-09-13

### Fixed

- Fixed desktop hover state layers that could visually extend beyond their pointer hit region or stop short of the rendered control edge. Hover motion now stays entirely inside the control's actual hit bounds instead of scaling past them.
- Standard list tiles, buttons, icon buttons, switches, and custom animated surfaces now use consistent shape-aware hover fills so the hover field covers the complete interactive surface without removing hover feedback.
- Preserved the existing hover animation by animating desktop surfaces from a tiny inset rest scale back to their full 1.0 layout size, preventing edge flicker and hover dead strips.
- Bumped application metadata to `1.0.1109+153`.


## [1.0.1108] - 2026-09-12

### Fixed

- Fixed desktop text fields sliding horizontally while selecting text with the mouse. The app-wide scroll behavior no longer claims mouse drag gestures that belong to text selection.
- Prevented Koinly's elastic/always-scrollable page physics from leaking into `EditableText`'s internal caret scrollable, so short field values stay anchored instead of overscrolling or appearing to disappear.
- Kept mouse-wheel and trackpad scrolling for pages/lists while preserving normal mouse selection, copy, cut, paste, and caret behavior in every text field.
- Bumped application metadata to `1.0.1108+152`.

## [1.0.1107] - 2026-09-12

### Added

- Added a centered subscription recurrence picker for Daily, Weekly, Monthly, and Yearly schedules instead of the inline dropdown menu.
- Added an **Auto pay** switch to every subscription. Turning it off keeps the recurring item and its next scheduled date without automatically creating a transaction.
- Expanded **Add now** into a confirmation popup where the user chooses the transaction date, time, and spending account before recording the payment.
- Added database-backed profile media synchronization through the self-hosted Worker. Profile photos, GIFs, and videos now follow the signed-in account to other synced devices, including crop/framing metadata.

### Changed

- Increased the profile photo/video upload limit to **50 MB** and changed local profile-media writes to stream large files instead of loading the full file into memory.
- Profile media uses chunked authenticated Worker uploads and downloads, with realtime sync notifications and retry-safe pending state so finance sync remains available if a large media transfer is interrupted.
- Bumped application metadata to `1.0.1107+151`.

### Deployment required

- **Self-hosted sync users must redeploy the latest Cloudflare Worker** so the new `profile_media` and `profile_media_chunks` database tables and media endpoints are available. The deployment workflow applies the schema automatically before redeploying.

## [1.0.1106] - 2026-09-12

### Changed

- Moved the macOS release job from the legacy Intel GitHub runner to the standard Apple Silicon `macos-15` runner while keeping Flutter's universal release mode enabled, so the published app still contains both `arm64` and `x86_64` slices.
- Replaced the macOS `subosito/flutter-action` setup with a pinned Flutter `3.47.4` source checkout cached between runs. This avoids ARM64 SDK archive resolution failures and removes repeated SDK setup work after the first run.
- Added reusable macOS CocoaPods and incremental `build/macos` caches so later release builds can reuse Xcode/Flutter compilation work instead of rebuilding every dependency from scratch.
- Disabled CocoaPods statistics during CI to remove unnecessary network/analytics overhead.
- Bumped application metadata to `1.0.1106+150`.

### Performance

- The macOS job was the release pipeline bottleneck, spending most of its time inside `flutter build macos` on `macos-15-intel`. The release workflow now targets Apple Silicon and keeps incremental build state, substantially reducing repeat-build wall time.

## [1.0.1105] - 2026-09-12

### Fixed

- Fixed Linux AppImage packaging failure by resizing and validating the Koinly icon as a real 512×512 PNG before passing it to `linuxdeploy`.
- Fixed ARM64 desktop CI setup failures caused by `subosito/flutter-action` being unable to resolve some stable ARM64 SDK archive entries. Linux ARM64 now bootstraps the pinned Flutter `3.47.4` tag directly from the official Flutter repository.
- Reworked macOS packaging into a single verified universal build produced on `macos-15-intel`, containing both `x86_64` and `arm64` slices. This avoids the ARM64 Flutter SDK archive resolution failure while keeping native Apple Silicon support.

### Changed

- Pinned desktop and release CI to Flutter `3.47.4` for reproducible builds across runners.
- Bumped application metadata to `1.0.1105+149`.

## [1.0.1104] - 2026-09-12

### Added

- Added first-class Linux desktop release builds for both x64 and ARM64. GitHub Actions now publishes a broad-distro AppImage plus a portable `.tar.gz` bundle for each architecture.
- Added macOS release builds for Apple Silicon ARM64 and Intel x64, publishing both DMG installers and zipped `.app` bundles.
- Added optional Developer ID signing and Apple notarization support for macOS GitHub releases.
- Added Linux desktop launcher metadata and Koinly branding for packaged AppImages.

### Changed

- Stable GitHub Releases now collect Android, Windows, Linux, and macOS artifacts into the same versioned release and update manifest.
- Updated project documentation and platform metadata for Android, Windows, Linux, and macOS distribution.
- Bumped application metadata to `1.0.1104+148`.

## [1.0.1103] - 2026-09-12

### Fixed
- Fixed the subscription scheduler release-build failure caused by passing a captured nullable `DateTime?` to `dateToDb(DateTime)`. The scheduler now snapshots the processed timestamp into an immutable local before serializing it.
- This fixes both Windows and Android builds that previously failed in `subscription_background_service.dart`.

### Changed
- Bumped application metadata to `1.0.1103+147`.

## [1.0.1102] - 2026-09-12

### Added
- Added a new Subscriptions page for recurring expenses with configurable price, expense category, spending account, date/time, and daily/weekly/monthly/yearly cadence.
- Added manual “Add now” recording for subscriptions without removing the saved subscription.
- Added automatic due-subscription processing in the foreground and through Android WorkManager while the app is closed. Automatic occurrence IDs are deterministic to prevent duplicate cross-device charges.
- Replaced the Transaction Plan FAB with a three-line quick-action menu that expands into Plan and Subscription actions over a blurred animated backdrop.

### Changed
- Subscription data is included in local/cloud merge sync, category remapping, backups, and the self-hosted Worker Telegram backup payload.
- Bumped application metadata to `1.0.1102+146`.

## [1.0.1101] - 2026-09-12

### Fixed

- Restored standard text selection and adaptive copy/cut/paste/select-all context menus for every text field on desktop and mobile.
- Read-only/signed-in fields remain selectable and copyable instead of becoming disabled, including Account & sync username and temporarily locked sync setup fields.
- Bumped application metadata to `1.0.1101+145`.

## [1.0.1100] - 2026-09-12

### Changed
- Refined the shared switch theme so on/off toggles no longer render with a harsh outline around the track.
- Improved inactive thumb/track contrast and kept pressed feedback subtle while preserving the existing Koinly green active state.
- Bumped application metadata to `1.0.1100+144`.

## [1.0.1099] - 2026-09-12

### Changed
- Added an account selector to the loan editor so users can choose which account provides lent money or receives borrowed money.
- Existing loan disbursal records can now move to a different account when the loan is edited, with account balances recalculated correctly.
- Bumped application metadata to `1.0.1099+143`.

## [1.0.1098] - 2026-09-12

### Fixed
- Center popups no longer shrink when the on-screen keyboard opens. Popup sizing now ignores IME insets and stays based on the real safe viewport.
- While typing, popups move toward the top of the screen instead of scaling down, keeping text and controls at their normal readable size.
- The behavior is shared by the transaction editor and every popup using the common Koinly popup frame.

### Changed
- Bumped application metadata to `1.0.1098+142`.

## [1.0.1097] - 2026-09-11

### Changed
- Replaced foreground 3-second-style sync polling with authenticated realtime WebSocket change notifications through a Cloudflare Durable Object hub.
- Reduced local sync upload debounce to 120 ms so edits are committed and announced to other open devices almost immediately.
- Uses a 20-second safety pull while realtime is connected, automatically falls back to 3-second polling if the live channel is unavailable, and pulls immediately after a realtime change event.
- Reduced pending-sync retry cadence to 5 seconds and kept conflict/merge handling unchanged.
- Added the `SYNC_HUB` Durable Object binding and deployment migration to the self-hosted Cloudflare Worker.
- Bumped application metadata to `1.0.1097+141`.

## [1.0.1096] - 2026-09-11

### Changed
- Background update checks now run at Android WorkManager's 15-minute periodic floor, so new-release notifications can arrive while Koinly is closed instead of depending on the next app launch.
- Removed the battery-not-low constraint from the lightweight release check; only an active network connection is required.
- Added a Loan preferences toggle to show or hide loan-linked movements from the main Transaction list without deleting them or changing loan/account data.
- Bumped application metadata to `1.0.1096+140`.

## [1.0.1095] - 2026-09-11

### Changed
- Reduced multi-device sync latency: local edits now queue an upload after a 350 ms debounce instead of 3 seconds.
- Reduced foreground cloud pull cadence from 15 seconds to 3 seconds, with a 2.5-second minimum pull gap.
- Reduced retry cadence for pending sync work from 30 seconds to 10 seconds.
- Reused the sync HTTP client across background push/pull requests to avoid repeated connection and TLS setup.
- Bumped application metadata to `1.0.1095+139`.

## [1.0.1094] - 2026-09-11

### Changed

- Bumped application metadata to `1.0.1094+138` so the latest onboarding/profile-media UI build reports the correct new app version.

## [1.0.1093] - 2026-09-11

### Changed

- Removed the desktop-only three-dot transaction overflow menu from transaction cards. Desktop transaction rows now keep the clean amount-only trailing area shown in the mobile design; opening a transaction by clicking the row and the existing swipe/quick-action behavior remain unchanged.
- Bumped application metadata to `1.0.1093+137`.

## [1.0.1092] - 2026-09-11

### Fixed

- Fixed the remaining transaction Slidable snap bug where the **Duplicate** pane revealed by a left-to-right swipe immediately returned to the closed position on release. The leading pane is 28% of the row width, but its previous `.34` open threshold was larger than the pane's maximum extent, making the open state unreachable. The leading-pane thresholds are now sized to that pane (`openThreshold: .14`, `closeThreshold: .08`) so it stays open after a deliberate swipe, matching the right-to-left Edit/Delete behavior.
- No banner, navigation, loan, chart, update-notification, or other UI behavior was changed in this release.

### Changed

- Bumped application metadata to `1.0.1092+136`.

## [1.0.1091] - 2026-09-11

### Fixed

- Fixed the top success/error/warning feedback banner visual bug. The oversized Awesome Snackbar MaterialBanner surface is now presented as a compact floating top notification with safe-area spacing, restrained height, balanced icon/text/close alignment, consistent Koinly rounding, and no decorative shapes bleeding into the message.
- Preserved the same feedback timing, semantic success/error/warning types, and dismiss behavior; no transaction, Slidable, navigation, loan, chart, update-notification, or other UI behavior was changed in this release.

### Changed

- Bumped application metadata to `1.0.1091+135`.

## [1.0.1090] - 2026-09-11

### Added

- Added Android background update monitoring when **Automatic update pop-ups** is enabled. Android WorkManager performs a battery-aware network check every few hours and Koinly posts one deduplicated local notification per newly detected release, including when the app is not currently open. Turning the setting off cancels the worker and its update notification.
- Added a continuously animated Home balance wave using `fl_chart`. The motion is subtle, looped, and automatically stops when Reduce Motion / disabled animations is active.
- Reworked animated empty states so the Lottie pulse remains as ambient motion while the foreground icon now matches the actual section (budget, category spending, transactions, plans, loans, and other empty cards).

### Changed

- Renamed the transaction **Copy** quick action to **Duplicate** and moved it to the leading/left action pane. **Edit** and **Delete** remain on the trailing/right pane. Loan-generated transactions still omit duplication.
- Moved Awesome Snackbar success/error/warning feedback from the bottom SnackBar position to a top MaterialBanner presentation, so messages such as **Done → Transaction deleted** no longer cover the bottom navigation and Add/Plan controls.
- Updated the automatic-update setting description to make its notification behavior explicit.
- Bumped application metadata to `1.0.1090+134`.

## [1.0.1089] - 2026-09-11

### Fixed

- Reworked Slidable quick actions to eliminate the Android partial-swipe artifacts shown in the latest recording. Transaction, planned-purchase, and loan rows now use native `SlidableAction` surfaces with `ScrollMotion`, stable snap thresholds, and clipping to the row radius.
- Removed opposite-side action panes from the same row. All quick actions now live in one trailing pane, preventing cross-direction drags from leaving red/green edge remnants or briefly collapsing an action into a thin strip.
- Disabled drag-dismiss behavior for quick-action panes so an overswipe cannot push a card beyond its intended action extent.
- Kept per-list auto-close behavior so opening one row cleanly closes any previously open row.

### Changed

- Regular transactions reveal **Copy, Edit, Delete** together; loan-generated transactions reveal **Edit, Delete**. Planned purchases reveal **Buy, Edit, Delete**, and active loans reveal **Payment, Edit**.
- Bumped application metadata to `1.0.1089+133`.

## [1.0.1088] - 2026-09-11

### Fixed

- Fixed Flutter Slidable rows rendering as clipped rectangular action strips during partial swipes. Transaction, planned-purchase, and loan quick actions now use rounded Koinly action surfaces with stable BehindMotion, compact fitted labels, auto-close behavior, and per-list grouping so only one row stays open.
- Fixed the mobile tab transition briefly mixing the previous page with the next tab's dock selection and transaction Plan/Add controls. Page content, dock state, and tab-specific floating actions now transition as one keyed stage.

### Changed

- Removed the **Plan / Monthly installments** controls from the New/Edit loan popup. Existing installment metadata on older loans is preserved when those loans are edited, so the UI cleanup does not erase historical data.
- Removed the per-loan **Account movement** controls from the New/Edit loan popup. New-loan account movement now follows **Loan preferences → Record account movements by default** and automatically uses the default/first regular account when one is available.
- Bumped application metadata to `1.0.1088+132`.

## [1.0.1087] - 2026-09-11

### Fixed

- Fixed `flutter pub get` failing after the Awesome Snackbar Content integration. `awesome_snackbar_content` 0.1.8 uses Flutter localizations, which on the current Flutter 3.47.x toolchain requires `intl ^0.20.3`; Koinly now uses the same compatible Intl constraint instead of the older `^0.19.0`.
- Kept `awesome_snackbar_content` 0.1.8 rather than downgrading it, preserving the current desktop/mobile fixes and semantic snackbar styling.
- Bumped application metadata to `1.0.1087+131`.

## [1.0.1086] - 2026-09-11

### Added

- Added Lottie-powered empty states for key zero-data screens while respecting the system Reduce Motion setting.
- Added Flutter SpinKit loaders and centralized compact/page loading indicators across the app.
- Added Awesome Snackbar Content for semantic success, warning, and failure feedback while preserving Koinly's lightweight top notification for ordinary informational messages.
- Added Flutter Slidable actions to transaction, purchase-plan, and loan rows. Touch users can quickly duplicate/edit/delete transactions, buy/edit/delete planned items, and record/edit loans; desktop transaction rows keep an explicit action menu.
- Added a Timelines-based chronological loan history with loan creation, repayments, dates, amounts, and existing repayment deletion controls. The maintained `timelines_plus` implementation is used for current Flutter compatibility.

### Changed

- Expanded `fl_chart` usage by replacing the custom category donut painter with an animated `PieChart`, while keeping category badges, center totals, and the existing green/dark visual system. Existing cash-flow and balance charts remain interactive FL Chart views.
- Added busy-state protection and branded SpinKit feedback to transaction saving, plus success/failure snackbar feedback.
- Raised the declared Dart SDK floor to 3.12 because the current Lottie release requires it; the GitHub Actions Flutter 3.47.x toolchain uses Dart 3.13.x.
- Bumped application metadata to `1.0.1086+130`.

## [1.0.1085] - 2026-09-11

### Fixed

- Restored Android and Windows release compilation after the desktop elastic-scroll update by importing Flutter's gesture library for `PointerSignalEvent` and `PointerScrollEvent`.
- Kept the desktop mouse-wheel edge spring behavior unchanged while making the pointer-signal types available on every Flutter target.
- Synchronized fallback Android version metadata with `1.0.1085+129`.

## [1.0.1084] - 2026-09-11

### Fixed

- Fixed the spring/elastic UI feedback being too subtle or effectively absent with mouse input on the Windows/desktop build. Shared pressable surfaces, Material buttons/FAB wrappers, cards, selectors, and navigation now react directly to mouse pointer down/up and spring back consistently.
- Added a restrained desktop hover lift before the press compression so short mouse clicks still make the elastic interaction visible without changing layout or hit targets; Windows side-rail navigation icons/labels now use the same feedback.
- Enabled restrained elastic top/bottom edge scrolling on desktop while keeping Flutter's native mouse-wheel/trackpad pipeline; no queued `animateTo` wheel handler was reintroduced, so fast PC scrolling remains precise.
- Kept system Reduce Motion / disabled-animation accessibility behavior intact.

## [1.0.1083] - 2026-09-11

### Fixed

- Fixed Android Back / predictive Back dismissing a page or centered popup together with the on-screen keyboard. While the IME is visible, the first Back action now only clears text-field focus and dismisses the keyboard; all entered values and the current form remain intact. A later Back action, after the keyboard is closed, navigates away normally.
- Centralized the behavior in a shared keyboard-back guard used by every standard `PageScaffold`, every centered Koinly popup, and first-run onboarding currency setup. This covers transaction, account, category, budget, loan, profile, search, login/sync, recovery, currency, and other existing text-entry flows without screen-specific hacks.
- Added the missing tap-outside focus dismissal to all account-recovery text fields so keyboard dismissal behavior is consistent with the rest of the app.

## [1.0.1082] - 2026-09-11

### Changed

- Reworked the app-wide visual system from blue/cyan-tinted dark surfaces to the emerald/forest-green palette shown in the supplied reference video. The update is centralized in shared theme tokens so Home, Analysis, Loans, Transactions, Categories, settings, dialogs, charts, navigation, controls, and future theme-aware components stay consistent.
- Updated dark-mode background/surface layers, glass gradients, navigation highlights, focused controls, progress/switch states, and default theme-facing icon accents to emerald while preserving semantic expense red, warning amber, and category-specific colors.
- Updated the light theme to use a subtle green-neutral surface palette so switching appearance modes keeps the same visual identity.

### Compatibility

- Existing user-selected account/category colors are left untouched. Legacy starter Cash accounts that used the old pale-blue default are still recognized by import/cleanup logic.

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
