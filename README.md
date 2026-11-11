# Cafe POS

Multi-tenant point-of-sale for cafes and restaurants (Flutter web + Firebase).

- **Master Admin** — onboard cafes, plans, subscription payments, staff, audit log
- **Manager** — POS billing, tables, menu (sizes, add-ons, photos), reports, captains
- **Captain** — kitchen screen

Every cafe's data lives under `cafes/{cafeId}/…` and is isolated by Firestore
security rules using server-assigned roles (Firebase Auth custom claims).

**Go-live and testing:** see [docs/SETUP.md](docs/SETUP.md).

| Folder | What |
|---|---|
| `lib/` | Flutter app |
| `functions/` | Cloud Functions (invites, cafes, subscription job) |
| `firestore.rules`, `storage.rules` | Security rules |
| `firestore-tests/` | Rules tests (Firestore emulator) |
| `tools/admin/` | Local admin scripts: backup, bootstrap, migration, menu import |
