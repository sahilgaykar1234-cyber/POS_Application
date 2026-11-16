# Production checklist (things done in the Firebase / Google console)

What is already in the code is listed at the end. Everything in the sections
below needs the project owner, because it is a console setting, a paid plan or
a legal decision. Do them in this order.

## 1. Blaze plan + budget alert (needed before selling)
1. Firebase console → ⚙ Usage and billing → Details & settings → Modify plan → **Blaze**.
2. Google Cloud console → Billing → **Budgets & alerts** → budget of e.g. ₹500/month,
   alerts at 50 %, 90 %, 100 %. (Alerts email you; they do not stop spending.)
3. Expected cost: about ₹0 for the first 2–3 cafes (free quota), then ~₹30–100 per cafe per month.

## 2. Backups (needs Blaze)
Daily backups kept for 14 days:
```bash
gcloud firestore backups schedules create \
  --database='(default)' --recurrence=daily --retention=14d --project=suratpos
```
Also enable **Point-in-time recovery** (Firestore → Disaster recovery) to undo
mistakes from the last 7 days. Manual export any time: `cd tools/admin && npm run backup`.

## 3. A separate test project (staging)
Create a second Firebase project (e.g. `suratpos-staging`), add a web app, and
test new versions there first. Never test on the live cafes' data.

## 4. Check the Firestore region
Firebase console → Firestore → the location is shown at the top. Best for India:
`asia-south1` (Mumbai). It cannot be changed later; if it is in the US, plan the
move before many cafes join (new project + data copy).

## 5. App Check (blocks scripts that use the public API key)
1. Google Cloud → reCAPTCHA Enterprise → create a **website key** for your domain(s).
2. Firebase console → App Check → register the web app with that key.
3. Tell the developer the site key: the app needs `firebase_app_check` activated in `main.dart`.
4. Watch the App Check metrics for a few days, then click **Enforce** for Firestore and Authentication.

## 6. Two-step login (MFA) for the Super Admin
Firebase console → Authentication → Settings → upgrade to **Identity Platform**
(free for this size) → enable **SMS multi-factor**. Then enrol your phone for the
Super Admin account (the app needs a small enrolment screen – ask the developer).

## 7. Storage for menu photos
Firebase console → Storage → Get started (Blaze needed for new projects), then
`firebase deploy --only storage` to apply `storage.rules`.

## 8. Your domain
Hosting → Add custom domain (e.g. `app.yourbrand.com`) → add the DNS records shown.
Then add the domain in Authentication → Settings → Authorized domains.

## 9. Legal pages
`web/privacy.html` and `web/terms.html` are templates. Add your legal name,
address, grievance officer (DPDP Act), refund and jurisdiction terms, and have a
lawyer / CA review them. Register for GST on your SaaS income when required.

## 10. After Blaze: server-side checks (Cloud Functions, Node.js)
Planned next in `functions/` (hybrid design – the app keeps reading Firestore
directly for live/offline use):
- recompute each bill's total and assign bill numbers on the server (trigger);
- monthly automatic removal of old customer numbers (today: Settings › Security & privacy › Remove now);
- subscription expiry reminders, Razorpay payment webhooks;
- daily summary documents so reports read a few documents instead of all bills;
- move panel-created logins to server-set claims.

---

## Already in the app (no console work needed)
- Bills are **cancelled with a reason, never deleted**; numbers never reused; rules
  protect bill number, token and creation time; cancelled bills are final.
- Audit log for cancelled bills, edits of paid bills, exports, customer-data removal,
  Manager PIN changes, logins and all Super Admin actions.
- **Manager PIN** for the Manager view on shared cafe logins (Settings › Security & privacy).
  For real separation, give the kitchen a "Kitchen only" login.
- Customer privacy: consent hint at the POS, "Remove customer data" per customer,
  retention period with "Remove older numbers now", Privacy Policy / Terms pages.
- Logins created / turned off / password changed in the Super Admin panel; plan login limits.
- Day-end (Z) report print in Reports.
- Tenant isolation and all of the above covered by Firestore rules tests (`firestore-tests/`).
