#!/usr/bin/env node
/**
 * Local one-off admin commands for the Cafe POS platform.
 * Runs on YOUR machine with a service-account key; never shipped in the app.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=~/secrets/suratpos-admin.json node admin.js <command> ...
 *
 * Commands:
 *   create-super-admin <email> [display name]
 *       Creates (or upgrades) the platform owner account and prints a
 *       one-time "set your password" link. Super Admins can ONLY be created
 *       here, never from inside the app.
 *
 *   create-cafe <name> [--legacy]
 *       Creates a cafe record with an auto-generated ID.
 *       --legacy marks the cafe whose data still lives in the old global
 *       collections (Flamy Wood only, until the Phase 3 migration).
 *
 *   create-staff <email> <manager|captain> <cafeId> [display name]
 *       Creates (or re-assigns) a cafe staff login and prints a one-time
 *       "set your password" link. Works without Cloud Functions.
 *
 *   create-cafe-login <username> <password> <cafeId>
 *       Simple shared cafe login (e.g. flammywood / 123). After signing in
 *       the user picks Manager or Captain view. Re-run to change the password.
 *
 *   list-cafes
 *   list-users
 */

const fs = require('fs');
const admin = require('firebase-admin');

const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!credPath || !fs.existsSync(credPath)) {
  console.error('ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON file.');
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();
const auth = admin.auth();
const { FieldValue } = admin.firestore;
const { loginEmail, loginPassword } = require('./lib/login');

async function createSuperAdmin(email, displayName) {
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) throw new Error('Usage: create-super-admin <email> [name]');
  email = email.trim().toLowerCase();

  let user;
  try {
    user = await auth.getUserByEmail(email);
    console.log(`Account exists (${user.uid}); upgrading to Super Admin.`);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email, displayName: displayName || 'Super Admin' });
    console.log(`Created account ${user.uid}.`);
  }

  await auth.setCustomUserClaims(user.uid, { role: 'superAdmin' });
  await auth.revokeRefreshTokens(user.uid); // force fresh token with new claims
  await db.collection('users').doc(user.uid).set(
    {
      email,
      displayName: displayName || user.displayName || 'Super Admin',
      role: 'superAdmin',
      cafeId: null,
      status: 'active',
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await db.collection('auditLogs').add({
    action: 'superAdmin.bootstrap',
    actorUid: 'local-admin-script',
    targetUid: user.uid,
    at: FieldValue.serverTimestamp(),
  });

  const link = await auth.generatePasswordResetLink(email);
  console.log('\nSuper Admin ready. Open this link ONCE to set your password:\n');
  console.log(link);
}

async function findCafeByName(name) {
  const snap = await db.collection('cafes').where('name', '==', name.trim()).limit(1).get();
  return snap.empty ? null : snap.docs[0];
}

/** Creates a cafe (auto ID). New cafes also get default POS settings. Returns the id. */
async function createCafe(name, legacy, extra = {}) {
  if (!name || name.trim().length < 2) throw new Error('Usage: create-cafe <name> [--legacy]');
  name = name.trim();

  const dup = await findCafeByName(name);
  if (dup) throw new Error(`A cafe named "${name}" already exists (id ${dup.id}).`);

  if (legacy) {
    const existing = await db.collection('cafes').where('legacyData', '==', true).limit(1).get();
    if (!existing.empty) throw new Error(`A legacy cafe already exists (id ${existing.docs[0].id}). Only one is allowed.`);
  }

  const ref = db.collection('cafes').doc(); // auto-generated unique ID
  await ref.set({
    name,
    status: 'active',
    legacyData: legacy, // true = data still in old global collections
    contactNumber: extra.contactNumber || '',
    createdAt: FieldValue.serverTimestamp(),
    createdBy: 'local-admin-script',
  });

  // Legacy cafes bring their own settings in the migration.
  if (!legacy) {
    await ref.collection('settings').doc('business').set({
      shopName: name,
      tagline: extra.tagline || '',
      ownerName: '',
      mobileNumber: extra.contactNumber || '',
      email: '',
      gstNumber: '',
      address: '',
      shopLogoBase64: null,
      receiptHeader: 'Thank you for your order!',
      receiptFooter: 'Visit Again!',
      thankYouMessage: 'Thank You!',
      showGst: false,
      gstPercentage: '5',
      currencySymbol: '₹',
      currencyCode: 'INR',
      defaultOrderType: 'Dine-In',
      defaultTax: '5',
      autoGenBillNumber: true,
      autoGenTokenNumber: true,
      numberOfTables: 12,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  await db.collection('auditLogs').add({
    action: 'cafe.create',
    actorUid: 'local-admin-script',
    cafeId: ref.id,
    details: { name, legacy },
    at: FieldValue.serverTimestamp(),
  });
  console.log(`Created cafe "${name}" with ID: ${ref.id}${legacy ? '  (legacy data)' : ''}`);
  return ref.id;
}

/**
 * Creates (or re-assigns) a Manager/Captain login for a cafe without Cloud
 * Functions. Prints a one-time "set your password" link.
 */
async function createStaff(email, displayName, role, cafeId) {
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) throw new Error('Usage: create-staff <email> <manager|captain> <cafeId> [name]');
  if (!['manager', 'captain'].includes(role)) throw new Error('Role must be manager or captain.');
  const cafe = await db.collection('cafes').doc(cafeId || '-').get();
  if (!cafe.exists) throw new Error(`Cafe ${cafeId} not found. Run list-cafes to see IDs.`);
  email = email.trim().toLowerCase();
  displayName = (displayName || '').trim() || email.split('@')[0];

  let user;
  try {
    user = await auth.getUserByEmail(email);
    const claims = user.customClaims || {};
    if (claims.role === 'superAdmin') throw new Error(`${email} is the Super Admin; use a different email for cafe staff.`);
    console.log(`  ${email}: account exists, assigning ${role} of ${cafe.get('name')}`);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email, displayName });
    console.log(`  ${email}: account created (${role} of ${cafe.get('name')})`);
  }

  await auth.setCustomUserClaims(user.uid, { role, cafeId });
  await auth.updateUser(user.uid, { disabled: false });
  await auth.revokeRefreshTokens(user.uid); // pick up the new role on next sign-in
  await db.collection('users').doc(user.uid).set(
    { email, displayName, role, cafeId, status: 'invited', updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await db.collection('auditLogs').add({
    action: 'staff.invite',
    actorUid: 'local-admin-script',
    cafeId,
    targetUid: user.uid,
    details: { email, role },
    at: FieldValue.serverTimestamp(),
  });
  const link = await auth.generatePasswordResetLink(email);
  return { email, role, cafeName: cafe.get('name'), link };
}

/**
 * Simple cafe login, e.g. username "flammywood" + password "123".
 * The account gets the Manager role; after signing in the app lets them
 * choose Manager (POS) or Captain (kitchen) view. Re-running resets the password.
 */
async function createCafeLogin(username, password, cafeId) {
  username = String(username || '').trim().toLowerCase();
  if (!/^[a-z0-9._-]{3,30}$/.test(username)) throw new Error('Username: 3-30 letters/numbers (no spaces, no @).');
  if (!password || String(password).length < 3) throw new Error('Password must be at least 3 characters.');
  const cafe = await db.collection('cafes').doc(cafeId || '-').get();
  if (!cafe.exists) throw new Error(`Cafe ${cafeId} not found. Run list-cafes to see IDs.`);

  const email = loginEmail(username);
  const pass = loginPassword(username, String(password));
  let user;
  try {
    user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, { password: pass, disabled: false, displayName: cafe.get('name') });
    console.log(`  login "${username}" updated (password reset) for ${cafe.get('name')}`);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email, password: pass, displayName: cafe.get('name') });
    console.log(`  login "${username}" created for ${cafe.get('name')}`);
  }
  await auth.setCustomUserClaims(user.uid, { role: 'manager', cafeId });
  await auth.revokeRefreshTokens(user.uid);
  await db.collection('users').doc(user.uid).set(
    { email, displayName: `${cafe.get('name')} (shared login)`, role: 'manager', cafeId, status: 'active', updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await db.collection('auditLogs').add({
    action: 'staff.invite',
    actorUid: 'local-admin-script',
    cafeId,
    targetUid: user.uid,
    details: { email: username, role: 'manager' },
    at: FieldValue.serverTimestamp(),
  });
  return { username, cafeName: cafe.get('name') };
}

async function listCafes() {
  const snap = await db.collection('cafes').get();
  if (snap.empty) return console.log('No cafes yet.');
  for (const d of snap.docs) {
    const c = d.data();
    console.log(`${d.id}  ${c.name}  [${c.status}]${c.legacyData ? '  (legacy data)' : ''}`);
  }
}

async function listUsers() {
  const snap = await db.collection('users').get();
  if (snap.empty) return console.log('No users yet.');
  for (const d of snap.docs) {
    const u = d.data();
    console.log(`${d.id}  ${u.email}  ${u.role}  cafe=${u.cafeId ?? '-'}  [${u.status}]`);
  }
}

async function main() {
  const [cmd, ...args] = process.argv.slice(2);
  switch (cmd) {
    case 'create-super-admin':
      return createSuperAdmin(args[0], args.slice(1).join(' '));
    case 'create-cafe': {
      const legacy = args.includes('--legacy');
      return createCafe(args.filter((a) => a !== '--legacy').join(' '), legacy);
    }
    case 'create-staff': {
      const r = await createStaff(args[0], args.slice(3).join(' '), args[1], args[2]);
      console.log(`\nOpen this link once to set the password for ${r.email}:\n${r.link}`);
      return;
    }
    case 'create-cafe-login':
      await createCafeLogin(args[0], args[1], args[2]);
      return;
    case 'list-cafes':
      return listCafes();
    case 'list-users':
      return listUsers();
    default:
      console.log(
        'Commands:\n' +
          '  create-super-admin <email> [name]\n' +
          '  create-cafe <name> [--legacy]\n' +
          '  create-staff <email> <manager|captain> <cafeId> [name]\n' +
          '  create-cafe-login <username> <password> <cafeId>\n' +
          '  list-cafes | list-users',
      );
  }
}

module.exports = { createCafe, createStaff, createCafeLogin, findCafeByName, db, auth };

if (require.main === module) {
  main().catch((err) => {
    console.error('FAILED:', err.message);
    process.exit(1);
  });
}
