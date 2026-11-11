# Cafe POS — Go-Live Runbook

This is the exact order to set up and switch over. Follow it top to bottom.
Steps marked **(once)** are only done the first time.

> Nothing in this project touches your live Firebase until **you** run these
> commands. The old Flamy Wood data is never modified or deleted.

---

## 0. What you need

| Item | Where |
|---|---|
| Firebase project `suratpos` on the **Blaze** plan | Firebase Console → Usage and billing |
| Admin key (service account JSON) | Console → Project settings → Service accounts → *Generate new private key*. Save **outside** this folder, e.g. `~/secrets/suratpos-admin.json`. Never commit or share it. |
| Firebase CLI logged in | `firebase login` |
| Node 22 | already installed |

Set the key for every terminal you use:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/suratpos-admin.json
```

---

## 1. Firebase Console settings (once)

1. **Billing → Budgets**: add a budget alert (e.g. ₹100/month).
2. **Authentication → Sign-in method**: enable **Email/Password**.
3. **Project settings → General → Public-facing name**: `Cafe POS`
   (shown in invite/reset emails).
4. **Authentication → Templates → Password reset** (optional): change the
   subject to e.g. "Set your Cafe POS password" — the same email is used for
   new-staff invitations.
5. **Storage → Get started**: open it once so the bucket
   `suratpos.firebasestorage.app` is active (used for menu photos).

---

## 2. Back up everything (every time before a big change)

```bash
cd ~/pos_app/tools/admin
npm install          # once
npm run backup
```

Note the document counts it prints. The backup folder is `~/pos_app/backups/…`
— also copy it to Google Drive.

---

## 3. Deploy the backend (functions + indexes)

```bash
cd ~/pos_app/functions && npm install        # once
cd ~/pos_app
firebase deploy --only functions,firestore:indexes
```

Deploys: `inviteStaff`, `setStaffActive`, `createPasswordResetLink`,
`confirmFirstSignIn`, `createCafe`, `deleteCafe`, and the daily
`checkSubscriptions` job (06:00 IST). Indexes take a few minutes to build.

> Do **not** deploy `firestore:rules` yet — the currently live app still
> uses the old collections. Rules go live in step 6.

---

## 4. Create your Super Admin and the Flamy Wood cafe (once)

```bash
cd ~/pos_app/tools/admin
node admin.js create-super-admin you@example.com "Your Name"   # open the printed link, set your password
node admin.js create-cafe "Flamy Wood" --legacy                 # prints the Flamy Wood cafe ID
```

Use the exact spelling you want shown in the admin panel (rename later in
*Cafes → Flamy Wood → Edit*).

---

## 5. Switch-over (do this after closing time — takes ~10 minutes)

No orders should be placed during these steps.

```bash
cd ~/pos_app/tools/admin
npm run backup                                                   # fresh backup
node migrate_legacy.js --cafe <FLAMY_WOOD_ID> --dry-run          # read the report
node migrate_legacy.js --cafe <FLAMY_WOOD_ID>                    # copy + verify + switch
```

The migration:
- copies every order **with the same ID** (bill numbers unchanged), the
  business settings, and the menu (56 items, Regular/Medium/Standard sizes kept);
- compares every copied order field-by-field and the total of all bills;
- only then marks Flamy Wood as migrated. If anything differs it stops and
  changes nothing in the old data.

Then publish the new app and the security rules:

```bash
cd ~/pos_app
flutter build web --release
firebase deploy --only hosting
node tools/admin/migrate_legacy.js --cafe <FLAMY_WOOD_ID> --delta   # catches any order placed during the switch
firebase deploy --only firestore:rules,storage
```

From now on the old screens with passwords 123/456 no longer exist.

---

## 6. Give Flamy Wood staff their logins

1. Open the app → sign in as Super Admin.
2. **Cafes → Flamy Wood → Staff → Add staff** → Manager (name + email).
3. They get an email "set your password" (also shown as a link you can
   WhatsApp). After setting it they sign in with email + password.
4. The Manager can add Captains from the 👥 button in the POS header.

---

## 7. Onboard Pizza La Forno

1. **Plans → New plan** (e.g. "Monthly" ₹999 / 30 days) — optional.
2. **Cafes → New cafe**: name **exactly** `Pizza La Forno`, owner details,
   logo, plan/dates, first payment (optional), first manager email.
   Copy the cafe ID shown afterwards (also in *Overview → Cafe ID*).
3. Check the extracted menu against the PDF:
   `docs/pizza_la_forno_menu_review.txt` (assumptions are listed at the top
   of `tools/admin/data/pizza_la_forno_menu.js`). Edit that file if needed.
4. Import it:

```bash
cd ~/pos_app/tools/admin
node import_menu.js --cafe <PIZZA_LA_FORNO_ID> --menu data/pizza_la_forno_menu.js --dry-run
node import_menu.js --cafe <PIZZA_LA_FORNO_ID> --menu data/pizza_la_forno_menu.js
```

The importer refuses to write into a cafe whose name is not "Pizza La Forno",
so it can never touch Flamy Wood.

---

## 8. Test checklist

**Super Admin**
- [ ] Dashboard numbers look right (cafes, managers, captains, revenue).
- [ ] Create a test cafe with a manager → invitation email arrives.
- [ ] Suspend it → its manager sees "suspended" and cannot use the POS. Activate → works again.
- [ ] Subscription → set expiry to yesterday → POS blocked; record payment with *Renew* → works again.
- [ ] Download a payment receipt PDF.
- [ ] Delete the test cafe (type its name) → its staff can no longer sign in. Restore works.
- [ ] Activity tab lists all of the above.

**Flamy Wood Manager**
- [ ] Sees only Flamy Wood orders/menu/settings; old bills and bill numbers are there.
- [ ] New order → size picker for two-size pizzas → print draft bill → place → complete → receipt.
- [ ] Totals with/without GST are the same as before for the same items.
- [ ] Menu tab: add/edit item with sizes, mark *Sold out* (greyed in POS), add a photo, delete.
- [ ] 👥 Staff: add a Captain, send reset, disable/enable.
- [ ] Reports and Customer Directory still work.

**Captain**
- [ ] Sees only their cafe's active orders; *Start Cooking* / *Mark Ready* work.

**Isolation**
- [ ] Pizza La Forno manager never sees Flamy Wood data (and vice-versa).

**Password**
- [ ] *Forgot password?* on the login screen sends a reset email.

---

## 9. Developer checks

```bash
flutter analyze && flutter test                 # app logic (30 tests)
cd functions && npm test                        # server permissions/validation/expiry (18)
cd tools/admin && npm test                      # migration + Pizza La Forno data (13)
cd firestore-tests && npm test                  # security rules on the emulator (needs Java 21)
```

---

## Reference

**Roles**
| | Super Admin | Manager | Captain |
|---|---|---|---|
| All cafes, plans, payments | ✔ | | |
| Own cafe POS, menu, settings, reports | (view) | ✔ | |
| Add/disable Captains | ✔ | own cafe | |
| Add/disable Managers | ✔ | | |
| Kitchen status (cooking/ready) | | ✔ | ✔ |

**Subscription policy** — POS is blocked (data kept) when the cafe is
inactive/suspended/deleted, the subscription is expired/suspended, or the
expiry date has passed. A banner warns 7 days before expiry and while a
payment is pending. The same policy is enforced by `firestore.rules`.

**Costs** — Blaze is pay-as-you-go; at a few cafes usage stays inside the free
allowance (Functions, Scheduler: 3 free jobs, Firestore, Auth email). No paid
third-party services are used.

**Where things live**
- App: `lib/` (`core/` shared, `features/admin|auth|menu|staff`, existing POS screens at top level)
- Server: `functions/` · Rules: `firestore.rules`, `storage.rules`
- Admin scripts: `tools/admin/` · Rules tests: `firestore-tests/`
