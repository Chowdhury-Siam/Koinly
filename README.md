<p align="center">
  <img src="docs/images/koinly-readme-banner.png" alt="Koinly personal finance tracker banner" width="100%">
</p>

# Koinly

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-Material%203-02569B?logo=flutter&logoColor=white" alt="Flutter"></a>
  <a href="https://github.com/Chowdhury-Siam/Koinly/actions/workflows/build-android-apks.yml"><img src="https://github.com/Chowdhury-Siam/Koinly/actions/workflows/build-android-apks.yml/badge.svg" alt="Build status"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20macOS-00B8C8" alt="Android, Windows, Linux and macOS">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0 license"></a>
</p>

<p align="center">
  A private, local-first personal finance app for Android, Windows, Linux, and macOS.<br>
  Use it completely offline, or connect your own Cloudflare Worker for optional multi-device sync.
</p>

## Quick navigation

| Start here | Self-hosted sync | App & backups | Developers |
| --- | --- | --- | --- |
| [1. What is Koinly?](#what-is-koinly)<br>[2. Features](#features)<br>[3. Getting started](#getting-started) | [4. What self-hosted sync means](#optional-self-hosted-sync)<br>[5. Deploy your Worker](#deploy-your-self-hosted-worker)<br>[6. Connect Koinly](#connect-koinly-to-your-worker)<br>[Administration portal](#worker-administration-portal)<br>[7. Credentials & Archive](#optional-telegram-cloud-backup) | [8. Local](#local-backup)<br>[9. Data safety](#data-safety-and-security)<br>[12. Troubleshooting](#troubleshooting) | [10. Build from source](#build-from-source)<br>[11. Worker development](#worker-development)<br>[13. Project structure](#project-structure)<br>[14. License](#license) |

---

<a id="what-is-koinly"></a>
## 1. What is Koinly?

Koinly is a personal finance tracker designed to keep your data under your control.
Your accounts, transactions, categories, budgets, loans, plans, subscriptions, and other finance data are saved to a local SQLite database first.

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
- Recurring subscriptions with scheduled date/time, price, category, spending account, daily/weekly/monthly/yearly repeat, automatic transaction recording, and manual “Add now”
- Cash-flow trends, category analysis, balances, and net results
- Analytics summaries driven by the same **Choose Date Filter** flow used elsewhere in Koinly: Today, This Week, This Month, This Year, All Time, or a Custom date range
- Analytics reports support **PDF**, **XLSX**, and **TXT** in both Summary and Transaction history variants, with direct and scheduled Self-Hosted Worker uploads to Telegram and Google Drive
- Search and filters for account, category, type, and date
- Quick account/category creation from transaction pickers

### 2.2 Backup and restore

- Encrypted `.koinlybackup` files
- Merge-based restore instead of destructive replacement
- Automatic category deduplication while restoring or syncing
- Restore-or-Start-New onboarding
- Local `.koinlybackup` scheduling on a daily, weekly, or monthly schedule
- User-selected Android backup folder using the system folder picker
- Optional deletion of the previous automatic backup after a new backup succeeds
- Privacy-safe diagnostics in **Advanced settings > Data health**

### 2.3 App experience

- Material 3 design
- Light, dark, and system themes
- Adaptive Android, Windows, Linux, and macOS layouts
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
- Administrator-managed account password resets through the private `/profile` dashboard
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

Before starting, you need a **Turso account** and a **Cloudflare account**. A GitHub account and fork are required only when you choose the GitHub Actions deployment method.

Koinly supports two Worker deployment methods:

- **Deploy Database in the app** — open **Settings > Account & sync > Deploy Database**, follow the setup guide, enter the deployment values, and let Koinly create/update the database and Worker directly.
- **GitHub Actions** — fork this repository, save the same deployment values as repository secrets/variables, and run **Deploy Self-Hosted Sync Worker**.

Both methods deploy the same Worker contract and can be used again later to update an existing Worker. When redeploying, keep the same Worker name, Turso database, and `JWT_SECRET` unless you intentionally want a separate backend.

### 4.1 The six deployment values

The in-app deployment page asks for these values directly. The GitHub Actions method stores the same values under **GitHub > Settings > Secrets and variables > Actions**:

| Name | What it is | Where it comes from |
| --- | --- | --- |
| `CLOUDFLARE_NAME` | Your Worker name, such as `my-koinly-sync` | You choose it |
| `CLOUDFLARE_API_TOKEN` | Authorizes Worker deployment | Cloudflare |
| `CLOUDFLARE_ACCOUNT_ID` | Identifies your Cloudflare account | Cloudflare |
| `TURSO_DATABASE_URL` | Your `libsql://...turso.io` database address | Turso |
| `TURSO_AUTH_TOKEN` | Read/write access token for the Turso database | Turso |
| `JWT_SECRET` | Long random secret used by your Worker | You generate it |

Keep the token/secret values private. Never post them in issues, screenshots, chats, logs, or source files.

---

<a id="deploy-your-self-hosted-worker"></a>
# 5. Deploy your self-hosted Worker

Create the Turso and Cloudflare values once, then choose either deployment path:

```text
Create a Turso database + token
        ↓
Create a Cloudflare API token + copy Account ID
        ↓
Choose Worker name, JWT secret, and administrator credentials
        ↓
        ├─ In Koinly: Settings > Account & sync > Deploy Database
        │      ↓
        │   Deploy directly and auto-fill the Worker URL
        │
        └─ GitHub: save the 8 values and run Deploy Self-Hosted Sync Worker
               ↓
            Copy the Worker URL into Koinly
        ↓
Create the first sync account directly in Koinly
        ↓
Use /profile only for additional accounts and account administration
```

If you use the in-app method, you can skip Sections **5.1, 5.8, and 5.9** and continue with **5.10** after gathering the common values in Sections 5.2–5.7.

## 5.1 Step 1 — Fork Koinly (GitHub Actions method only)

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

Use this value as `TURSO_DATABASE_URL` in whichever deployment method you choose.

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

Both deployment methods validate the Cloudflare values before uploading the Worker. If Cloudflare changes the template later, recreate the token from the **Edit Cloudflare Workers** template rather than granting unrelated account-wide permissions.

## 5.5 Step 5 — Confirm your Cloudflare Account ID

The easiest place to copy the Account ID is the **Token created successfully** dialog shown immediately after creating the token. Use the Account ID from the same Cloudflare account that owns the Worker.

Use this value as `CLOUDFLARE_ACCOUNT_ID` in whichever deployment method you choose.

## 5.6 Step 6 — Choose a Worker name

Choose a short name such as:

```text
my-koinly-sync
```

Rules:

- lowercase letters, numbers, and `-` only;
- 1 to 63 characters;
- do not start or end with `-`.

Use the name as `CLOUDFLARE_NAME` in GitHub Actions, or enter it as **Cloudflare Worker name** on the in-app deployment page.

Your final address will look similar to:

```text
https://my-koinly-sync.<your-workers-subdomain>.workers.dev
```

GitHub Actions prints the exact URL after deployment; in-app deployment fills the URL in **Account & sync** automatically.

## 5.7 Step 7 — Generate the Worker security secret

Choose **`JWT_SECRET`** from the checklist in Section 4.1. Use your password manager to generate a random value of at least 32 characters. It protects login sessions and encrypted Worker data, so keep it unchanged when updating an existing Worker.

There is no separate Worker-administrator deployment username or password. After deployment, the **first Koinly account created in the app becomes the Worker administrator automatically**. That same username and password are used to sign in to `/profile`.

When **Automatic Worker updates** is enabled in the in-app deployment page, Koinly securely stores the Cloudflare/Turso/JWT deployment values. After the first account exists, it also keeps an encrypted recovery copy on the Worker. If Koinly is reinstalled, paste the same Worker URL and sign in with that first account to restore the **Enter deployment values** fields automatically.

## 5.8 Step 8 — Add the values to GitHub (GitHub Actions method only)

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
```

Spelling matters. The workflow expects these exact names.

## 5.9 Step 9 — Deploy the Worker with GitHub Actions

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
5. uploads the Turso and JWT Worker secrets securely;
6. deploys the Cloudflare Worker; and
7. checks that the deployed Worker is healthy.

When it succeeds, open the workflow run summary and copy the **Worker URL**.

Example:

```text
https://my-koinly-sync.example-subdomain.workers.dev
```

You do **not** need to manually create Turso tables. The workflow applies the schema for you.

## 5.10 Deploy directly from Koinly

After you have the values from Sections 5.2–5.7:

1. Open **Settings > Account & sync** in Koinly.
2. Select **Deploy Database** under **Self-hosted Sync Worker**.
3. Use the Cloudflare and Turso shortcut buttons on that page if you still need to copy a value.
4. Enter the Worker name, Cloudflare Account ID, Cloudflare API token, Turso database URL, Turso auth token, and JWT secret.
5. Select **Deploy Worker**.
6. Keep the page open while Koinly validates Cloudflare and Turso, applies the current database schema, uploads the Worker, enables its `workers.dev` route, configures the five-minute scheduler, and waits for the Worker health check. A first-time `workers.dev` route can take a few minutes to finish TLS/routing propagation; Koinly keeps polling and shows the current health stage instead of treating the first minute as a failure.
7. If a step fails, the deployment page shows the error there so you can correct the value and retry.
8. Leave **Automatic Worker updates** enabled if you want this device to keep the Worker current after future Koinly app updates.
9. When deployment succeeds, Koinly returns to **Account & sync**, automatically fills the **Cloudflare Worker URL**, and validates that Worker for use by the app.

With **Automatic Worker updates** enabled, Koinly saves the deployment profile in the platform secure credential store. This includes the Cloudflare API token, Turso token, JWT secret, Worker/account identifiers, Worker URL, and Worker version. After the first sync account is created or the owner signs in, Koinly also stores an encrypted recovery copy in that user's Worker database. Only the first Koinly sync account can read that recovery copy.

This means a reinstall does not require entering all deployment values again. Paste and validate the same Worker URL, then sign in with the first sync account. Koinly restores the deployment profile to the device secure store automatically, so **Enter deployment values** is populated again and automatic Worker updates can continue.

On a later Koinly app version, the app checks the active Worker's `/health` version and redeploys only when the embedded Worker is newer. If the active Worker URL has been changed to a different Worker, that Worker's recovery profile is used only after its owner account signs in. Choosing **Forget saved deployment credentials** removes the local secure copy and, when the owner account is signed in, the Worker's encrypted recovery copy too.

Cloudflare still receives the Worker secrets required by the deployed service. If secure credential storage is unavailable on the device, the Worker can still be deployed manually, but automatic future redeployment cannot be enabled on that device.

The release workflow embeds the matching deployable Worker bundle into official Koinly builds. If a source build reports that the deployable bundle is missing, build the app through the repository release workflow or run `npm run bundle:app` inside `cloud/worker` before building Flutter.

### 5.10.1 Automatic Worker updates

Automatic Worker updating applies only to the Worker deployed from that device through **Deploy Database** with **Automatic Worker updates** enabled. After a newer Koinly app version is installed and opened, Koinly checks the saved deployment profile and the active Worker URL. If they match, it reads the Worker's reported version from `/health`. A current Worker is left untouched; an older or legacy Worker is redeployed with the Worker bundle embedded in the installed app, the existing Turso database, and the same Worker identity.

The update runs in the background so app startup is not blocked. **Account & sync** shows progress while a Worker update is running and displays a retryable error if Cloudflare, Turso, network, or credential validation fails. The existing deployed Worker is not deleted when an update attempt fails. If the app was reinstalled, sign in to the same Worker with the first sync account once; Koinly restores the encrypted deployment profile before checking for a newer Worker.

Users who first deployed with Koinly `1.0.1155` or earlier must open **Deploy Database** once on `1.0.1156` or later and complete a deployment with **Automatic Worker updates** enabled so the secure deployment profile can be created.

---

<a id="connect-koinly-to-your-worker"></a>
# 6. Connect Koinly to your Worker

After completing Sections 4 and 5, the first sync account can be created directly from Koinly. The Worker's [administration portal](#worker-administration-portal) is used for additional accounts and account administration.

To connect an account to the app:

1. Open Koinly and go to **Settings > Account & sync**.
2. If you deployed through **Deploy Database**, the Worker URL is already filled and validated automatically. If you deployed through GitHub Actions, paste the Worker URL without `/profile` and select **Validate and use Worker**.
3. On a fresh Worker with no sync accounts yet, enter the username and password you want and select **Create account**. This first database account automatically becomes the Worker administrator.
4. On another device, select **Login** and use that same sync-account username and password.
5. To create a second or later account, go to **Settings > Profile** and sign in with the first account (the Worker administrator), then use **Create account**.

**Settings > Profile** is shown only after a Worker URL has been successfully validated. It opens Koinly's native in-app Worker administration screen rather than launching a browser. The Worker `/profile` web portal remains available for direct web access. The first account remains the administrator and cannot be deleted, so further account creation stays administrator-managed.

### 6.1 Password reset

If an account holder needs a new password, open **Settings > Profile**, sign in as the Worker administrator, select the account, and use **Change password**. The same operation remains available from the Worker's direct `/profile` web portal. The reset signs out that account's existing sessions, and the user can then sign in again with the new password.

### 6.2 Sync controls

- **Upload local changes** merges your current local data into the Worker copy.
- **Restore cloud copy** downloads the Worker copy and merges it into the device.

Both are merge-based. Matching records are reconciled rather than blindly duplicated, while local-only and cloud-only records are preserved.

When two signed-in devices are open, the Worker uses an authenticated Durable Object WebSocket hub to announce committed changes immediately. The receiving device then performs the normal versioned incremental pull. A slower periodic pull remains enabled as a fallback for dropped or suspended realtime connections.

<a id="worker-administration-portal"></a>
### 6.3 Worker administration portal (`/profile`)

Koinly provides the same Worker account administration directly inside the app at **Settings > Profile** after the Worker URL is validated. The first Koinly account created on that Worker is the administrator. Sign in with that account's current username and password. The Worker also continues to expose the private `/profile` web dashboard for direct web administration.

> **Existing Worker owners:** Workers deployed through **Deploy Database** can now update automatically after future Koinly app updates when **Automatic Worker updates** is enabled and the saved deployment profile still matches the active Worker URL. Koinly compares the Worker's reported version with the Worker bundled into the installed app and redeploys only when the bundled Worker is newer. GitHub-based deployments continue to redeploy automatically when the fork receives the updated project. Keep the same Worker name, Turso database, and `JWT_SECRET` so the existing backend continues to use the same identity and encrypted data.

The administrator is the first sync account in the database, not a separate deployment login. It appears in the account list with an **Administrator** badge and cannot be deleted, although its username and password can be changed.

#### 6.3.1 Open the dashboard and sign in

1. Open your Worker URL in a browser and add `/profile` to the end. For example:

   ```text
   https://koinly-test.sweets-4c4.workers.dev/profile
   ```

2. Enter the username of the first Koinly account created on this Worker.
3. Enter that account's current password. Use the eye button inside the password field when you need to verify what you typed.
4. Select **Sign in**.

The dashboard shows the total number of registered accounts and a list of their usernames, creation dates, and status. **Invited** means an account has not signed in yet. **Active** means it has signed in at least once; it does not indicate that the person is online. Use **Previous** and **Next** to browse lists larger than 50 accounts.

#### 6.3.2 Create an account from the website

1. In the dashboard, select **+ Create account**.
2. Enter the new account's **Username**.
3. Enter an 8–256 character password in **New password** and repeat it in **Confirm password**. Both fields include an eye button for temporary password visibility.
4. Select **Create account**.
5. Wait for **Account created**. The account will appear in the list.
6. Give the account holder the Worker URL, username, and password through a private channel. They can now select **Login** in Koinly.

Each account keeps its own synchronized data. Creating an account here does not grant administrator access.

#### 6.3.3 Change an account username

1. Find the account in the list and select **Change username**.
2. Enter the new username and select **Change username**.
3. The account keeps the same synchronized data and identity. The account holder uses the new username on the next login.

Changing the administrator username does not transfer administrator access; the first account remains the administrator because the Worker tracks its account ID, not the text of its username.

#### 6.3.4 Change or reset an account password

1. Find the account in the list and select **Change password**.
2. Enter and confirm the new password. Use either field's eye button if you need to verify the entry before saving.
3. Select **Change password** and wait for the success message.
4. Give the account holder their new password privately.

You do not need the old password. The reset signs out the account's devices. The account holder must sign in again with the replacement password.

#### 6.3.5 Delete an account

1. Find the account and select **Delete**.
2. Check the username in the confirmation dialog and read what will be removed.
3. Select **Cancel** to keep the account, or **Delete account** to remove it permanently.
4. Wait for **Account deleted** and confirm that the account is no longer listed.

The administrator account cannot be deleted from `/profile`; change its username or password instead. Deletion of other accounts removes that account's synchronized cloud data, device and session records, and Telegram backup settings. It cannot be undone. Copies already saved on devices or sent to Telegram remain. Other accounts and the administrator account are preserved.

#### 6.3.6 Change the administrator username or password

The administrator is the first Koinly account, so its credentials are managed from the same account row as every other account:

- Select **Change username** to rename the administrator account. Its administrator role remains attached to the same account ID.
- Select **Change password** to set a replacement password. This signs out that account's devices and invalidates its current `/profile` session, so sign in again with the new password.

No Worker redeployment is required for either change.

#### 6.3.7 Common messages

| Message or problem | What to do |
| --- | --- |
| No administrator account exists yet | Create the first Koinly account from the app. That first account automatically becomes the Worker administrator. |
| Invalid administrator username or password | Use the current username and password of the first Koinly account created on this Worker. |
| Duplicate username | Choose a different username, or find the existing account and change its password. |
| Session expired | Sign in again. Dashboard sessions last one hour. |
| Too many attempts | Wait fifteen minutes before trying again. |
| Server/database error | Confirm the Turso values in Section 5 and redeploy. For in-app deployment, read the error shown on **Deploy Database**; for GitHub deployment, inspect the failed Actions step. |
| `/profile` is not found | Confirm that the latest Worker deployment completed successfully and that you are opening the exact deployed Worker URL. |

Use **Sign out** when finished. The dashboard supports desktop and mobile browsers, light/dark/system appearance, and reduced-motion preferences. Account information and administrative actions require a signed-in administrator; passwords are stored as hashes and are never displayed in account lists.

Optional command-line instructions and implementation details are in the [Worker developer reference](cloud/worker/README.md#optional-command-line-setup).

---

<a id="optional-telegram-cloud-backup"></a>
## 7. Credentials, Telegram backup, and cloud report backup

Cloud delivery is available only when using your self-hosted Worker.

Koinly keeps service credentials in **Settings > Credential**. Configure the Telegram bot token and destination there, and configure/connect Google Drive there.

### Telegram credentials

In **Settings > Credential > Telegram bot**, configure:

- Telegram bot token;
- group or channel Chat ID; and
- optional test delivery.

For a Telegram channel, add the bot as an administrator with permission to post messages. The saved bot token is encrypted by the Worker before it is stored in Turso.

### Google Drive credentials

In **Settings > Credential > Google Drive**, create and connect your own OAuth 2.0 **Web application**:

1. Enable **Google Drive API** for the Google Cloud project.
2. Configure the OAuth consent screen. If the app remains in Testing, add the Google account you will use as a test user.
3. Create an **OAuth 2.0 Client ID** with application type **Web application**.
4. Copy the **Authorized redirect URI** shown in Koinly and add that exact URI to the Google OAuth client.
5. Paste the Client ID and Client Secret into Koinly. Optionally paste a **Google Drive Folder ID** if reports and cloud backup files should go into a specific existing folder.
6. Select **Save and connect Google Drive**, then finish authorization in the browser.

If **Google Drive Folder ID** is blank, Koinly requests the limited `drive.file` scope and creates/reuses a dedicated **Koinly Analytics** folder. If a Folder ID is configured, Koinly requests the broader Drive scope needed to access that existing folder, verifies that the folder is active and writable during connection, and sends manual/scheduled Analytics uploads and Google Drive `.koinlybackup` files there. The Folder ID is the value after `/folders/` in a Google Drive folder URL. The Worker encrypts the Google OAuth Client Secret and refresh token before storing them in Turso.

### Archive

Backup and scheduled-delivery controls are grouped under **Settings > Archive**:

- **Local** contains **Backup** for creating a `.koinlybackup` now and **Load backup** for merging a selected backup with the active device data.
- **Local backup file** contains **Local** and **Cloud**. **Local** schedules device-folder `.koinlybackup` files. **Cloud** schedules `.koinlybackup` delivery to Telegram and Google Drive through the credentials configured in **Settings > Credential**.
- **Analytics backup** contains **Cloud** for scheduled Analytics report delivery to Telegram and Google Drive in PDF, XLSX, or TXT.

In **Archive > Local backup file > Cloud**, Telegram and Google Drive have independent `.koinlybackup` schedules. Each destination supports daily, weekly, or monthly frequency, exact delivery time, and the applicable weekday/month date, plus **Upload backup now**. The Worker packages the latest synchronized cloud data. Google Drive uses the configured Folder ID when present; otherwise it creates/reuses a dedicated **Koinly Backup** folder.

### Analytics backup

Open **Settings > Analytics** to choose the report date filter, report type, and output format: **PDF**, **XLSX**, or **TXT**. **Download**, **Upload Telegram**, and **Upload Drive** all use the selected format. Manual cloud uploads use the credentials configured in **Settings > Credential**.

For automatic delivery, open **Settings > Archive > Analytics backup > Cloud**. Telegram and Google Drive each have an independent report schedule with:

- Summary or Transaction history report type;
- output format (**PDF**, **XLSX**, or **TXT**);
- date filter (**Today**, **This Week**, **This Month**, **This Year**, **All Time**, or a fixed **Custom range**);
- daily, weekly, or monthly cadence; and
- delivery time.

The Worker generates scheduled reports in the selected format from the latest synchronized cloud data, so the app does not need to remain open. **Custom range** uses the same centered Start/End calendar interaction as transaction date ranges and repeats the exact saved range on the chosen schedule.

Every enabled automatic cloud upload must be at least **5 minutes** away from every other one. This is enforced pairwise across Telegram report, Google Drive report, Telegram `.koinlybackup`, and Google Drive `.koinlybackup` schedules. For example, `03:00`, `03:05`, `03:10`, and `03:15` are valid; `03:00` and `03:04` are rejected. The same rule also handles midnight correctly.

> If the Worker was originally deployed through **Deploy Database** with automatic updates enabled, Koinly handles newer Worker redeployment on the first launch of the updated app. GitHub-based deployments continue to update through the deployment workflow. If an automatic update fails, open **Settings > Account & sync** to see the error and retry or refresh the saved deployment credentials.

---

<a id="automatic-local-backup"></a>
## 8. Local

Open **Settings > Archive > Local**.

You can choose:

- daily, weekly, or monthly frequency;
- backup time;
- weekly day or monthly date;
- destination folder; and
- whether the previous automatic backup is deleted after a new one succeeds.

On Android, automatic local backups run through a native WorkManager job using the persisted folder permission from the system folder picker. A due backup can therefore be created while the Koinly UI is closed, and the resulting file is written to the selected `Koinly/Backup` location.

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
- Google Drive OAuth Client Secrets and refresh tokens used by Analytics uploads are encrypted by the Worker before Turso storage.
- Profile media can synchronize through authenticated Worker media endpoints and is kept separate from the normal finance sync payload.

---

<a id="build-from-source"></a>
# 10. Build from source

Most users do not need this section. It is for developers or people building Koinly themselves.

## 10.1 Requirements

- Flutter with Dart `>=3.12.0 <4.0.0`
- Android Studio / Android SDK 36 / Java 17 for Android
- Visual Studio with **Desktop development with C++** for Windows
- Linux desktop build packages (`clang`, `cmake`, `ninja-build`, `pkg-config`, GTK 3, libsecret and SQLite development libraries) for Linux
- Xcode + CocoaPods on a supported Mac for macOS
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
  --dart-define=KOINLY_APP_VERSION=1.0.1172
```

## 10.4 Windows build

```bash
flutter config --enable-windows-desktop
flutter create --platforms=windows --project-name koinly --no-pub .
flutter pub get
flutter build windows --release \
  --dart-define=KOINLY_APP_VERSION=1.0.1172
```

## 10.5 Linux build

For Debian/Ubuntu development machines, install Flutter's Linux requirements plus the libraries used by Koinly's secure storage, SQLite, and desktop notifications:

```bash
sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libsecret-1-dev libsqlite3-dev libnotify-dev

flutter config --enable-linux-desktop
flutter create --platforms=linux --project-name koinly --no-pub .
flutter pub get
flutter build linux --release \
  --dart-define=KOINLY_APP_VERSION=1.0.1172
```

The release workflow builds both **x64** and **ARM64** Linux packages on Ubuntu 22.04. The x64 runner uses the pinned Flutter SDK release directly; the ARM64 runner bootstraps the same pinned Flutter tag from source so it does not depend on missing prebuilt ARM64 SDK archive entries. Each architecture gets:

- `Koinly-v<version>-linux-<arch>.AppImage` — the recommended broad-distro package.
- `Koinly-v<version>-linux-<arch>.tar.gz` — the raw Flutter portable bundle.

The AppImage is intended for broad compatibility across mainstream **glibc-based** distributions. Distros with materially different userspaces, such as musl-only systems, may need compatibility packages or a source build.

## 10.6 macOS build

Run this on macOS with Xcode installed:

```bash
flutter config --enable-macos-desktop
flutter create --platforms=macos --project-name koinly --org com.koinly --no-pub .
flutter pub get
flutter build macos --release \
  --dart-define=KOINLY_APP_VERSION=1.0.1172
```

The release workflow builds one **universal macOS package** containing both **Apple Silicon (ARM64)** and **Intel (x64)** slices. GitHub Releases publish `Koinly-v<version>-macos-universal.dmg` and a matching `.zip` containing `Koinly.app`. CI runs on GitHub's Apple Silicon `macos-15` runner for faster Xcode/Flutter compilation, bootstraps the pinned Flutter `3.47.4` source tag into a reusable SDK cache, keeps Flutter's universal macOS mode enabled, verifies both architecture slices with `lipo`, and reuses CocoaPods plus incremental macOS build caches between releases. It also applies Koinly's icon and `com.koinly.siam` bundle identifier and enables network access plus user-selected file read/write access for sync, import, and backup workflows.

The GitHub release workflow reads the official version/build number from `pubspec.yaml`.

### Profile media sync

When a signed-in user chooses a profile photo, animated GIF, or profile video, Koinly can synchronize that media through the user's own self-hosted Worker. Media is stored in the Worker database in authenticated chunks rather than inside the normal finance sync payload, so another signed-in device can download the same profile media without bloating transaction sync. The maximum profile-media size is **50 MB**. Existing Worker deployments must be redeployed after upgrading to a version that includes this feature so the new media tables and endpoints are created.

## 10.7 GitHub Actions

| Workflow | Purpose |
| --- | --- |
| `build-android-apks.yml` | Builds Android APKs, the Windows installer, Linux AppImage/portable archives, macOS DMG/ZIP packages, and publishes the stable GitHub Release |
| `deploy-sync-worker.yml` | Deploys a fork owner's self-hosted Cloudflare Worker |

### 10.7.1 Android signing

Release APK builds expect a permanent signing key through repository secrets. Keep the keystore and passwords outside the repository.

### 10.7.2 Windows signing

Windows code signing is optional. Without a signing certificate, the installer can still be generated, but Windows SmartScreen may show an unrecognized-publisher warning.

### 10.7.3 macOS signing and notarization

For public distribution outside the Mac App Store, configure these optional GitHub Actions secrets:

- `MACOS_CERTIFICATE_BASE64` — Base64-encoded Developer ID Application `.p12`.
- `MACOS_CERTIFICATE_PASSWORD` — password for the `.p12`.
- `MACOS_SIGNING_IDENTITY` — optional exact Developer ID Application identity; CI auto-detects it when omitted.
- `APPLE_ID` — Apple ID used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password for the Apple ID.
- `APPLE_TEAM_ID` — Apple Developer Team ID.

When these are present, CI signs the app with hardened runtime, submits the signed app to Apple for notarization, staples the notarization ticket to `Koinly.app`, and then packages the stapled app into the DMG and ZIP. If they are omitted, CI still produces DMG/ZIP artifacts, but macOS can show normal Gatekeeper warnings for an unnotarized application.

---

<a id="worker-development"></a>
## 11. Worker development (optional)

This section is for developers. For normal setup and account management, use the deployment and administration steps in Sections 5 and 6.

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

For normal deployment, use either **Settings > Account & sync > Deploy Database** in Koinly or **Actions > Deploy Self-Hosted Sync Worker > Run workflow** on GitHub. Both paths apply the required database updates and deploy the same Worker contract.

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
```

Also check that you did not accidentally add an extra space to a name or value. The `/profile` administrator is not a GitHub secret; it is the first Koinly account created on the Worker.

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

Create a new Cloudflare API token using the **Edit Cloudflare Workers** template, then use the replacement token in **Deploy Database** or update the `CLOUDFLARE_API_TOKEN` GitHub repository secret and redeploy.

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

A fresh Worker allows its first sync account to be created directly from **Settings > Account & sync > Create account**. After that first account exists, create any additional accounts from the Worker's `/profile` website with **+ Create account**. To use an existing account on another device, choose **Login** in Koinly with that account's username and password.

## 12.7 Telegram backup is empty or fails

1. Make sure the latest Worker is deployed.
2. In Koinly, use **Upload local changes** once.
3. Open **Archive > Local backup file > Cloud > Telegram** and try **Upload backup now** again.

The Worker rejects an empty finance backup instead of intentionally sending an empty file.

## 12.8 Android automatic folder backup fails

Open **Archive > Local**, choose the destination again with Android's system folder picker, then save the settings. This renews the persistent folder permission and re-registers the native background job.

If an OEM battery manager has explicitly restricted Koinly, allow background activity for the app. A manual Android **Force stop** suspends scheduled WorkManager jobs until the app is launched again.

---

<a id="project-structure"></a>
## 13. Project structure

```text
Koinly/
├── lib/                         # Flutter app, local storage, sync and UI
├── lib/loans/                   # Lending/borrowing domain
├── lib/profile/                 # Profile media handling and UI
├── android/                     # Android runner and platform integration
├── windows/                     # Windows runner (generated in CI/local Flutter create)
├── linux/                       # Linux runner (generated in CI/local Flutter create)
├── macos/                       # macOS runner (generated in CI/local Flutter create)
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
