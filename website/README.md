# Koinly public website

A dependency-free static website with a self-contained, fictional-data interactive demo. It is **not** a Flutter web build, a real account portal or a connection to your Koinly Worker. No backend credentials should ever be added to this folder.

## Preview locally

From the project root:

```sh
python3 -m http.server 8000 --directory website
```

Open `http://localhost:8000`. The interactive demo uses `sessionStorage`, so it persists within the same browser tab until the tab/session ends. "Reset demo" restores the supplied sample. The demo never calls the app backend.

## Publish the website

### GitHub Pages

1. Push this project to your repository's `main` branch.
2. In the repository, select **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. Run **Deploy Koinly Website** from Actions; subsequent changes under `website/` trigger the same workflow. Forks are deliberately skipped.
4. Add your custom domain in GitHub Pages settings if desired and configure DNS/HTTPS there.

The workflow uploads **only `website/`**. Android signing keys, Worker secrets and the rest of the application repository are never included in the website artifact.

### Cloudflare Pages (alternative)

Create a Pages project connected to your repo. Set the project root to the repository root, leave the build command blank and set the output directory to `website`. No Worker or Turso credentials are needed for this informational site. Use either GitHub Pages or Cloudflare Pages for the same domain, not both.

## Before app-store launch — required owner actions

- Edit `site-config.js` after the **real** Google Play and Microsoft Store listings are published. Blank links deliberately render as **Coming soon**, not fake download buttons. Set `githubUrl` to the right official repository and `supportEmail` to your public support address.
- **Finalize the privacy policy.** `privacy.html` is explicitly a non-indexed draft. Review release-build data flows, Firebase Analytics and Crashlytics behavior, optional backup providers, hosting/retention, operator details and any applicable disclosures. Replace placeholders, remove the draft banner and `noindex` only after verification, and remove the `Disallow: /privacy.html` rule from `robots.txt` so the finalized policy can be indexed. Update the footer label from "Privacy policy draft" to "Privacy policy" in `index.html` and `support.html`.
- Add a real support address and contact information. Confirm the website and actual store descriptions agree with the shipped app.
- Set the final domain in your search engine metadata and replace relative `og:image` with an absolute HTTPS URL for consistent link previews. Supply real app screenshots only if you want to represent the exact shipping app UI; the website's built-in preview is intentionally illustrative.
- Check your real store release and available desktop downloads; this website does not claim unpublished products are already in a store.

## Basic smoke checks

From the project root, with Node.js installed:

```sh
node --check website/app.js
node website/tests/site-contract.cjs
node website/tests/demo-smoke.cjs
```

The demo smoke test exercises state changes using a lightweight DOM stub; it is not a substitute for a final browser/device pass on your deployed domain. Verify the note toolbar, mobile navigation and both store links in real browsers before publishing.

## Demo coverage

Visitors can navigate Dashboard, Transactions, Budgets, Analytics, Plan, Subscriptions and Notes; add/edit/delete sample transactions; edit sample budget limits; add/buy plans; create subscriptions and record them manually; create/edit notes with basic rich formatting; and reset all demo data. Account balances, recent activity and analytics update from demo state. The demo intentionally does not expose real sync, account creation, actual scheduled jobs, PDF downloads or privileged Worker configuration.

## Maintenance

The site has no npm dependencies, build tools, tracking tags or external fonts. `index.html`, `styles.css` and `app.js` are the public frontend; `site-config.js` holds only public links. Update the browser demo if actual product workflows change; keep it clearly labeled as an illustration.
