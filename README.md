<p align="center">
  <img src="docs/images/koinly-readme-banner.png" alt="Koinly personal finance tracker banner" width="100%">
</p>

# Koinly

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-Material%203-02569B?logo=flutter&logoColor=white" alt="Flutter"></a>
  <a href="https://github.com/Chowdhury-Siam/Koinly/actions/workflows/build-android-apks.yml"><img src="https://github.com/Chowdhury-Siam/Koinly/actions/workflows/build-android-apks.yml/badge.svg" alt="Build status"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20Windows-00B8C8" alt="Android and Windows">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0 license"></a>
</p>

<p align="center">
  A private, local-first personal finance app for Android and Windows.<br>
  Use it completely offline, or connect your own Cloudflare Worker for optional multi-device sync.
</p>

## Quick navigation

| Start here | Self-hosted sync | App & backups | Developers |
| --- | --- | --- | --- |
| [1. What is Koinly?](#what-is-koinly)<br>[2. Features](#features)<br>[3. Getting started](#getting-started) | [4. What self-hosted sync means](#optional-self-hosted-sync)<br>[5. Deploy your Worker](#deploy-your-self-hosted-worker)<br>[6. Connect Koinly](#connect-koinly-to-your-worker)<br>[Administration portal](#worker-administration-portal)<br>[7. Telegram backups](#optional-telegram-cloud-backup) | [8. Automatic local backup](#automatic-local-backup)<br>[9. Data safety](#data-safety-and-security)<br>[12. Troubleshooting](#troubleshooting) | [10. Build from source](#build-from-source)<br>[11. Worker development](#worker-development)<br>[13. Project structure](#project-structure)<br>[14. License](#license) |

---

<a id="what-is-koinly"></a>
## 1. What is Koinly?

Koinly is a personal finance tracker designed to keep your data under your control.
Your accounts, transactions, categories, budgets, loans, plans, and other finance data are saved to a local SQLite database first.

You **do not need an account or server to use Koinly**. Install the app, choose **Use offline**, and start tracking your money.

If you want the same data on multiple devices, Koinly also supports **self-hosted sync**. You create a small Cloudflare Worker connected to your own Turso database, then enter the Worker URL in the app.

### 1.1 In simple terms

- **Koinly app** = the finance app on your phone or PC.
- **Cloudflare Worker** = your small private sync server.
- **Turso** = the database used by that sync server.
- **GitHub Actions** = automatically deploys the Worker for you.

You do not need to write Cloudflare or Turso code yourself.

<a id="features"></a>
## 2. Features

### 2.1 Personal finance

- Multiple cash, bank, card, savings, and custom accounts
- Income, expense, and transfer transactions
- Single dates/times or optional start/end ranges
- Custom income and expense categories
- Monthly budgets and progress tracking
- Lending and borrowing with repayments, interest, due dates, and timestamps
- Purchase planning with item name, expected price, category, total planned cost, editing, and one-tap purchase conversion
- Cash-flow trends, category analysis, balances, and net results
- Search and filters for account, category, type, and date
- Quick account/category creation from transaction pickers

### 2.2 Backup and restore

- Encrypted `.koinlybackup` files
- Merge-based restore instead of destructive replacement
- Automatic category deduplication while restoring or syncing
- Restore-or-Start-New onboarding
- Automatic local backups on a daily, weekly, or monthly schedule
- User-selected Android backup folder using the system folder picker
- Optional deletion of the previous automatic backup after a new backup succeeds
- Privacy-safe diagnostics in **Advanced settings > Data health**

### 2.3 App experience

- Material 3 design
- Light, dark, and system themes
- Android and Windows layouts
- Spring-based touch feedback and restrained elastic motion
- Interactive FL Chart cash-flow, balance, and category visualizations
- Swipe/slide quick actions for transactions, planned purchases, and loans
- Chronological loan repayment timelines
- Branded SpinKit loading states, semantic rich snackbars, and restrained Lottie empty-state animation
- App-wide keyboard/focus dismissal for text and numeric fields
- Profile image/GIF/short-video media with repositioning, crop framing, and zoom
- Android reminders
- GitHub Releases update checks

### 2.4 Self-hosted sync

- Your own Cloudflare Worker and Turso database
- A private administration portal for creating and managing sync accounts
- Username/password login from additional devices
- Recovery-key password reset without requiring an email address
- Offline-first local outbox
- Realtime foreground synchronization over an authenticated Cloudflare WebSocket hub, with incremental pull fallback
- Merge-first **Restore cloud copy** and **Upload local changes**
- Category deduplication across devices
- Version-based conflict handling
- Optional Telegram `.koinlybackup` delivery

---

<a id="getting-started"></a>
## 3. Getting started

### 3.1 Use Koinly without sync

This is the easiest option and requires no Cloudflare, Turso, or GitHub setup.

1. Install and open Koinly.
2. Tap **Use offline**.
3. Choose **Start New** to create a fresh local profile, or **Restore** to merge an existing `.koinlybackup` file.
4. Finish the setup screens and start using the app.

Everything stays on that device unless you later connect a self-hosted Worker.

### 3.2 Use Koinly on multiple devices

Set up the self-hosted Worker once, then use the same Worker URL and account on your other devices.

The full beginner-friendly deployment guide is below.

---

<a id="optional-self-hosted-sync"></a>
# 4. Optional self-hosted sync

Self-hosted sync is optional. It is only needed if you want your Koinly data synchronized through your own backend.

Before starting, you need:

- a GitHub account;
- a Turso account;
- a Cloudflare account; and
- a fork of this repository.

### 4.1 The eight values you will create

You will add these names to **GitHub > Settings > Secrets and variables > Actions**:

| Name | What it is | Where it comes from |
| --- | --- | --- |
| `CLOUDFLARE_NAME` | Your Worker name, such as `my-koinly-sync` | You choose it |
| `CLOUDFLARE_API_TOKEN` | Lets GitHub deploy your Worker | Cloudflare |
| `CLOUDFLARE_ACCOUNT_ID` | Identifies your Cloudflare account | Cloudflare |
| `TURSO_DATABASE_URL` | Your `libsql://...turso.io` database address | Turso |
| `TURSO_AUTH_TOKEN` | Read/write access token for the Turso database | Turso |
| `JWT_SECRET` | Long random secret used by your Worker | You generate it |
| `ADMIN_USERNAME` | Administrator username for the `/profile` dashboard | You choose it |
| `ADMIN_PASSWORD` | Administrator password for the `/profile` dashboard | You choose it |

Keep the token/secret values private. Never post them in issues, screenshots, chats, logs, or source files.

---

<a id="deploy-your-self-hosted-worker"></a>
# 5. Deploy your self-hosted Worker

The normal setup is:

```text
Fork Koinly on GitHub
        ↓
Create a Turso database
        ↓
Create a Cloudflare API token
        ↓
Add 8 values to GitHub Actions
        ↓
Run "Deploy Self-Hosted Sync Worker"
        ↓
Copy the workers.dev URL
        ↓
Open /profile and create a sync account
        ↓
Sign in to that account in Koinly
```

## 5.1 Step 1 — Fork Koinly

1. Open this repository on GitHub.
2. Click **Fork** in the upper-right corner.
3. Create the fork under your GitHub account.
4. Open your new fork.

The deployment workflow runs from your fork, so you do not need to edit Worker source code.

## 5.2 Step 2 — Create your Turso account and database

Turso stores the synchronized copy of your Koinly data.

1. Go to **https://app.turso.tech/**.
2. Create an account or sign in.
3. Open **Databases**.
4. Click **Create Database**.
5. Keep **New Database** selected.
6. Enter a simple name such as `koinly`.
7. Leave the normal/default group selected unless you specifically need another one.
8. Click **Create Database**.

### 5.2.1 Copy the Turso database URL

After the database is created:

1. Open the database.
2. Open its **Overview** page.
3. Find **Connect**.
4. Copy the **Database URL**.

The correct value looks similar to:

```text
libsql://koinly-yourname.turso.io
```

Add it to GitHub later as:

```text
TURSO_DATABASE_URL
```

> **Important:** Do not copy the normal `https://app.turso.tech/...` browser address. Koinly needs the `libsql://...turso.io` database URL shown under **Connect**.

### 5.2.2 Create the Turso token

In the current Turso dashboard shown in the setup recording:

1. Open your database **Overview** page.
2. In the **Connect** section, click **Create Token**.
3. Turso immediately opens a **Token Created** dialog.
4. Copy the long token from the first field. This is your `TURSO_AUTH_TOKEN`.
5. The same dialog also shows the `libsql://...turso.io` database URL. You can copy it there as a second check for `TURSO_DATABASE_URL`.
6. Save the token before closing the dialog because the full token is not shown again later.

If Turso adds an authorization/permission choice in a future dashboard version, the Worker needs normal **read and write** database access. Do not enable **Block Reads** or **Block Writes** on the database.

## 5.3 Step 3 — Create your Cloudflare account

Cloudflare runs the Koinly sync Worker.

1. Go to **https://dash.cloudflare.com/**.
2. Create an account or sign in.
3. Select the Cloudflare account you want to use.

You do not need to buy or configure a domain for the normal Koinly setup. The deployment uses a `workers.dev` address.

## 5.4 Step 4 — Create the Cloudflare API token

1. In Cloudflare, open **Manage account > Account API tokens**.
2. Click **Create Token**.
3. Choose the **Edit Cloudflare Workers** template.
4. Give the token a recognizable name such as `koinly`.
5. In the policy, scope the token to the Cloudflare account that will host Koinly. **Do not use “Read all resources” or “Write all resources”, and do not select every permission group.** The Worker deployment does not need account-wide access to unrelated products.
6. Keep the permissions supplied by the **Edit Cloudflare Workers** template. The current template includes **Workers Routes Write**, **Workers Scripts Write**, **Workers KV Storage Write**, **Workers Tail Read**, **Workers R2 Storage Write**, **Account Settings Read**, **User Details Read**, and **User Memberships Read**. You do **not** need to manually turn every permission group into **Read & Write**.
7. Click **Review token**, then **Create token**.
8. On the **Token created successfully** dialog, copy **Your API Token** immediately. This is `CLOUDFLARE_API_TOKEN`.
9. The same success dialog shows **Account ID**. Copy that value too; it is `CLOUDFLARE_ACCOUNT_ID`.

The deployment workflow checks the values before running Wrangler. If Cloudflare changes the template later, recreate the token from the **Edit Cloudflare Workers** template rather than granting unrelated account-wide permissions.

## 5.5 Step 5 — Confirm your Cloudflare Account ID

The easiest place to copy the Account ID is the **Token created successfully** dialog shown immediately after creating the token. Use the Account ID from the same Cloudflare account that owns the Worker.

Copy it and add it to GitHub later as:

```text
CLOUDFLARE_ACCOUNT_ID
```

## 5.6 Step 6 — Choose a Worker name

Choose a short name such as:

```text
my-koinly-sync
```

Rules:

- lowercase letters, numbers, and `-` only;
- 1 to 63 characters;
- do not start or end with `-`.

Add the name to GitHub as:

```text
CLOUDFLARE_NAME
```

Your final address will look similar to:

```text
https://my-koinly-sync.<your-workers-subdomain>.workers.dev
```

The workflow prints the exact URL after deployment.

## 5.7 Step 7 — Choose your security credentials

Choose the remaining three values from the checklist in Section 4.1:

- **`JWT_SECRET`:** Use your password manager to generate a random value of at least 32 characters. It protects login sessions and encrypted Worker data. Keep it unchanged when updating an existing Worker.
- **`ADMIN_USERNAME`:** Choose a lowercase username such as `worker-admin`. Use 3–32 letters, numbers, dots, dashes, or underscores, starting and ending with a letter or number.
- **`ADMIN_PASSWORD`:** Choose a strong, unique password of 12–256 characters and save it in your password manager. This is the password you will enter when signing in to `/profile`.

Enter these values directly in the GitHub secret fields in the next step. The deployment workflow hashes the administrator password automatically before sending its verifier to Cloudflare. You do not need to generate a hash or open a separate setup page. GitHub stores repository secrets encrypted; the password is not printed in deployment logs or stored in the account database.

Use different values for `JWT_SECRET` and `ADMIN_PASSWORD`, and do not reuse your GitHub, Cloudflare, or Koinly account password.

## 5.8 Step 8 — Add the values to GitHub

Open your **forked Koinly repository**, then go to:

**Settings > Secrets and variables > Actions**

### 5.8.1 Add these as repository secrets

Open the **Secrets** tab and create:

```text
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
ADMIN_USERNAME
ADMIN_PASSWORD
```

For each one:

1. Click **New repository secret**.
2. Enter the exact name shown above.
3. Paste the matching value.
4. Click **Add secret**.

### 5.8.2 Add the Worker name

For `CLOUDFLARE_NAME`, either:

- add it as a **repository variable** under the **Variables** tab (recommended); or
- add it as a repository secret.

Example:

```text
CLOUDFLARE_NAME = my-koinly-sync
```

### 5.8.3 Final checklist

Before deploying, your GitHub configuration should contain:

```text
CLOUDFLARE_NAME
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
ADMIN_USERNAME
ADMIN_PASSWORD
```

Spelling matters. The workflow expects these exact names.

## 5.9 Step 9 — Deploy the Worker

1. Open the **Actions** tab in your fork.
2. If GitHub asks you to enable Actions for the fork, enable them.
3. Select **Deploy Self-Hosted Sync Worker**.
4. Click **Run workflow**.
5. Wait for the deployment job to finish.

The workflow automatically:

1. installs the Worker dependencies;
2. checks the Worker source;
3. runs Worker tests;
4. applies the Koinly schema to your Turso database;
5. hashes `ADMIN_PASSWORD` automatically and uploads the Worker secrets securely;
6. deploys the Cloudflare Worker; and
7. checks that the deployed Worker is healthy.

When it succeeds, open the workflow run summary and copy the **Worker URL**.

Example:

```text
https://my-koinly-sync.example-subdomain.workers.dev
```

You do **not** need to manually create Turso tables. The workflow applies the schema for you.

---

<a id="connect-koinly-to-your-worker"></a>
# 6. Connect Koinly to your Worker

After completing Sections 4 and 5, create and manage sync accounts from your Worker's [administration portal](#worker-administration-portal). Use the administrator credentials you already added to the main setup checklist.

To connect an account to the app:

1. Open Koinly.
2. Go to **Settings > Account & sync**.
3. Paste your Cloudflare Worker URL, without `/profile` at the end.
4. Select **Validate and use Worker**.
5. Select **Login** and enter the username and password created in the administration portal.
6. While signed in, open **Recovery key**, generate a key, and save it securely.
7. Repeat these steps on other devices using the same account.

Existing accounts can continue to sign in with their current credentials. For Workers without administrator settings, the app still allows the first account to be created through **Create account** and displays a recovery key during registration. Once administrator settings are configured, use `/profile` to create accounts.

### 6.1 Forgot your password?

On the Login screen, choose **Forgot password?** and enter your username, saved recovery key, and a new password. A successful reset revokes the old refresh sessions and signs the current device in with the new password.

While signed in, **Settings > Account & sync > Recovery key** creates a replacement recovery key. The previous recovery key stops working immediately.

> Existing self-hosted databases created by older Koinly releases are migrated from email login to username login when the latest deployment workflow applies the schema. The old email's part before `@` becomes the initial username. Existing accounts do not have a recovery key until you sign in once and create one from **Recovery key**.

### 6.2 Sync controls

- **Upload local changes** merges your current local data into the Worker copy.
- **Restore cloud copy** downloads the Worker copy and merges it into the device.

Both are merge-based. Matching records are reconciled rather than blindly duplicated, while local-only and cloud-only records are preserved.

When two signed-in devices are open, the Worker uses an authenticated Durable Object WebSocket hub to announce committed changes immediately. The receiving device then performs the normal versioned incremental pull. A slower periodic pull remains enabled as a fallback for dropped or suspended realtime connections.

<a id="worker-administration-portal"></a>
### 6.3 Worker administration portal (`/profile`)

Manage your Worker's accounts through a private web dashboard. Administrator access is included in the normal setup in Sections 4 and 5; use the `ADMIN_USERNAME` and `ADMIN_PASSWORD` you saved there.

> **Existing Worker owners: redeployment is required.** After updating your project, check that all eight values from Section 4.1 are saved on GitHub, then open **Actions > Deploy Self-Hosted Sync Worker > Run workflow**. Choose the branch with your updated files, start the workflow, and wait for success. The deployment now also provisions the `SyncHub` Durable Object used for realtime cross-device notifications. Updating the Koinly app alone does not update your Worker. Keep the same Worker name, Turso database, and `JWT_SECRET`.

The administrator login manages the Worker. Sync accounts are the accounts people use to sign in to Koinly; they are listed in the dashboard. Your administrator login is separate and is not included in that count.

#### 6.3.1 Open the dashboard and sign in

1. Open your Worker URL in a browser and add `/profile` to the end. For example:

   ```text
   https://koinly-test.sweets-4c4.workers.dev/profile
   ```

2. Enter the administrator username saved in `ADMIN_USERNAME`.
3. Enter the password you saved as `ADMIN_PASSWORD` in GitHub.
4. Select **Sign in**.

The dashboard shows the total number of registered accounts and a list of their usernames, creation dates, and status. **Invited** means an account has not signed in yet. **Active** means it has signed in at least once; it does not indicate that the person is online. Use **Previous** and **Next** to browse lists larger than 50 accounts.

#### 6.3.2 Create an account from the website

1. In the dashboard, select **+ Create account**.
2. Enter the new account's **Username**.
3. Enter an 8–256 character password in **New password** and repeat it in **Confirm password**.
4. Select **Create account**.
5. Wait for **Account created**. The account will appear in the list.
6. Give the account holder the Worker URL, username, and password through a private channel. They can now select **Login** in Koinly and create their own recovery key after signing in.

Each account keeps its own synchronized data. Creating an account here does not grant administrator access.

#### 6.3.3 Change or reset an account password

1. Find the account in the list and select **Change password**.
2. Enter and confirm the new password.
3. Select **Change password** and wait for the success message.
4. Give the account holder their new password privately.

You do not need the old password. The reset signs out the account's devices and invalidates its previous recovery key. The account holder must sign in again and generate a replacement recovery key.

#### 6.3.4 Delete an account

1. Find the account and select **Delete**.
2. Check the username in the confirmation dialog and read what will be removed.
3. Select **Cancel** to keep the account, or **Delete account** to remove it permanently.
4. Wait for **Account deleted** and confirm that the account is no longer listed.

Deletion removes that account's synchronized cloud data, device and session records, and Telegram backup settings. It cannot be undone. Copies already saved on devices or sent to Telegram remain. Other accounts and the separate administrator login are preserved.

#### 6.3.5 Change the administrator password

1. In your GitHub repository, open **Settings > Secrets and variables > Actions**.
2. Find `ADMIN_PASSWORD` and select its edit button.
3. Enter your new administrator password and save the change.
4. Open **Actions > Deploy Self-Hosted Sync Worker > Run workflow**, choose the updated branch, and start the workflow.
5. When deployment succeeds, sign in to `/profile` with your new password.

The workflow hashes the new password automatically. Deployments refresh the administrator verifier and sign out existing dashboard sessions. Keep `JWT_SECRET` unchanged; it also protects other Worker credentials and encrypted data.

#### 6.3.6 Common messages

| Message or problem | What to do |
| --- | --- |
| Administrator login is not configured | Check `ADMIN_USERNAME` and `ADMIN_PASSWORD` in the main GitHub secrets checklist, then run the deployment workflow again. |
| Invalid administrator username or password | Use the username and password saved as `ADMIN_USERNAME` and `ADMIN_PASSWORD` on GitHub. |
| Duplicate username | Choose a different username, or find the existing account and change its password. |
| Session expired | Sign in again. Dashboard sessions last one hour. |
| Too many attempts | Wait fifteen minutes before trying again. |
| Server/database error | Open the latest GitHub Actions run and check the failed step. Confirm the Turso settings in Section 5, then rerun the deployment workflow. |
| `/profile` is not found | Confirm that the workflow deployed the updated files to the Worker URL you are opening. |

Use **Sign out** when finished. The dashboard supports desktop and mobile browsers, light/dark/system appearance, and reduced-motion preferences. Account information and administrative actions require a signed-in administrator; passwords are stored as hashes and are never displayed in account lists.

Optional command-line instructions and implementation details are in the [Worker developer reference](cloud/worker/README.md#optional-command-line-setup).

---

<a id="optional-telegram-cloud-backup"></a>
## 7. Optional Telegram cloud backup

Telegram backup is available only when using your self-hosted Worker.

In **Settings > Account & sync**, tap the bot icon in the upper-right corner.

You can configure:

- Telegram bot token;
- group or channel Chat ID;
- daily, weekly, or monthly upload schedule;
- exact delivery time;
- test delivery; and
- **Upload backup now**.

The Worker creates a `.koinlybackup` from the synchronized cloud data and sends it as a Telegram document.

For a Telegram channel, add the bot as an administrator with permission to post messages.

The saved bot token is encrypted by the Worker before it is stored in Turso.

---

<a id="automatic-local-backup"></a>
## 8. Automatic local backup

Open **Settings > Advanced settings > Automatic local backup**.

You can choose:

- daily, weekly, or monthly frequency;
- backup time;
- weekly day or monthly date;
- destination folder; and
- whether the previous automatic backup is deleted after a new one succeeds.

On Android, Koinly uses the system folder picker and creates/uses a `Koinly/Backup` folder under the selected location.

---

<a id="data-safety-and-security"></a>
## 9. Data safety and security

- Finance data is written to local SQLite first.
- Sync access and refresh tokens use platform secure storage.
- Turso credentials and `JWT_SECRET` stay on your Cloudflare Worker.
- The Flutter app does not contain your Turso or Cloudflare credentials.
- Sync requests are scoped to the signed-in owner account.
- Sync operations are versioned and designed to be idempotent.
- Local/cloud restore is merge-based.
- Backup imports reconcile equivalent categories to reduce duplicates.
- Telegram bot tokens saved for cloud backup are encrypted before Turso storage.
- Profile media remains device-local and is not part of finance synchronization.

---

<a id="build-from-source"></a>
# 10. Build from source

Most users do not need this section. It is for developers or people building Koinly themselves.

## 10.1 Requirements

- Flutter with Dart `>=3.5.0 <4.0.0`
- Android Studio / Android SDK 36 / Java 17 for Android
- Visual Studio with **Desktop development with C++** for Windows
- Node.js 22 for Worker development

## 10.2 Run locally

```bash
git clone https://github.com/Chowdhury-Siam/Koinly.git
cd Koinly
flutter pub get
flutter run
```

A Worker is not required for local/offline use.

## 10.3 Android build

```bash
flutter build apk --release \
  --no-tree-shake-icons \
  --dart-define=KOINLY_APP_VERSION=1.0.1100
```

## 10.4 Windows build

```bash
flutter build windows --release \
  --dart-define=KOINLY_APP_VERSION=1.0.1100
```

The GitHub release workflow reads the official version/build number from `pubspec.yaml`.

### 10.4.1 GitHub Actions

| Workflow | Purpose |
| --- | --- |
| `build-android-apks.yml` | Tests/builds Android APKs and Windows release artifacts |
| `deploy-sync-worker.yml` | Deploys a fork owner's self-hosted Cloudflare Worker |

### 10.4.2 Android signing

Release APK builds expect a permanent signing key through repository secrets. Keep the keystore and passwords outside the repository.

### 10.4.3 Windows signing

Windows code signing is optional. Without a signing certificate, the installer can still be generated, but Windows SmartScreen may show an unrecognized-publisher warning.

---

<a id="worker-development"></a>
## 11. Worker development (optional)

This section is for developers. For normal setup and account management, use the website steps in Sections 5 and 6.

```bash
cd cloud/worker
npm ci
npm run typecheck
npm test
```

Apply the schema locally:

```bash
export TURSO_DATABASE_URL='libsql://your-db.turso.io'
export TURSO_AUTH_TOKEN='your-token'
npm run schema:apply
```

For deployment, use **Actions > Deploy Self-Hosted Sync Worker > Run workflow** on GitHub. This handles the administrator password securely and applies the required database updates.

See [`cloud/worker/README.md`](cloud/worker/README.md) for Worker API and development details.

---

<a id="troubleshooting"></a>
# 12. Troubleshooting

## 12.1 GitHub says a deployment value is missing

Open your fork and check:

**Settings > Secrets and variables > Actions**

Make sure these exact names exist:

```text
CLOUDFLARE_NAME
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
ADMIN_USERNAME
ADMIN_PASSWORD
```

Also check that you did not accidentally add an extra space to a name or value.

## 12.2 `TURSO_DATABASE_URL` is rejected

The value must be the Turso database URL that starts with `libsql://` and normally ends with `.turso.io`.

Correct style:

```text
libsql://koinly-yourname.turso.io
```

Wrong values include:

```text
https://app.turso.tech/...
https://something.workers.dev/...
```

## 12.3 Cloudflare authentication error / code 10000

Create a new Cloudflare API token using the **Edit Cloudflare Workers** template, then replace `CLOUDFLARE_API_TOKEN` in your GitHub repository secrets and run the deployment again.

## 12.4 Worker validation fails in Koinly

Open this address in a browser:

```text
https://<your-worker>.workers.dev/health
```

A ready Worker should report values including:

```text
ok: true
service: koinly-sync
databaseReachable: true
schemaReady: true
registrationMode: first-user
```

If it does not, open the failed GitHub Actions deployment and read the first red/error step.

## 12.5 Cloudflare error 1042

Confirm that `TURSO_DATABASE_URL` is your Turso `libsql://...turso.io` URL, not a Cloudflare Worker URL. Also remove any Worker route that loops back into the same Koinly Worker.

## 12.6 I cannot create another Koinly account

To create a separate account, sign in to your Worker's `/profile` website and select **+ Create account**. If administrator access is not configured, follow [the portal setup guide](#worker-administration-portal). To use an existing account on another device, choose **Login** in Koinly with that account's username and password.

## 12.7 Telegram backup is empty or fails

1. Make sure the latest Worker is deployed.
2. In Koinly, use **Upload local changes** once.
3. Open Telegram backup and try **Upload backup now** again.

The Worker rejects an empty finance backup instead of intentionally sending an empty file.

## 12.8 Android automatic folder backup fails

Open **Automatic local backup**, choose the destination again with Android's system folder picker, then save the settings. This renews the persistent folder permission.

---

<a id="project-structure"></a>
## 13. Project structure

```text
Koinly/
├── lib/                         # Flutter app, local storage, sync and UI
├── lib/loans/                   # Lending/borrowing domain
├── lib/profile/                 # Profile media handling and UI
├── android/                     # Android runner and platform integration
├── windows/                     # Windows runner
├── cloud/worker/                # Self-hosted Cloudflare Worker + Turso schema
├── test/                        # Flutter/unit/source-contract tests
├── .github/workflows/
│   ├── build-android-apks.yml
│   └── deploy-sync-worker.yml
├── pubspec.yaml
└── README.md
```

<a id="license"></a>
## 14. License

Licensed under the Apache License 2.0. See [`LICENSE`](LICENSE).
