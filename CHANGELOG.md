# Changelog

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

- Owner/default-service deployment keeps the existing unprefixed GitHub
  configuration, while user self-hosted deployment uses separate `_U` names.

## [1.0.75] - 2026-08-27

### Changed

- User self-hosted GitHub configuration now uses the `_U` suffix, while
  owner/default-service configuration uses the `_A` suffix.

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
- Started Phase 2 polish with a desktop-default Performance mode that reduces transitions, card animations, update-wave animation, gradients, and heavy shadows.
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
