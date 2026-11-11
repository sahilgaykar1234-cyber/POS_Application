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

async function createCafe(name, legacy) {
  if (!name || name.trim().length < 2) throw new Error('Usage: create-cafe <name> [--legacy]');
  name = name.trim();

  const dup = await db.collection('cafes').where('name', '==', name).limit(1).get();
  if (!dup.empty) throw new Error(`A cafe named "${name}" already exists (id ${dup.docs[0].id}).`);

  if (legacy) {
    const existing = await db.collection('cafes').where('legacyData', '==', true).limit(1).get();
    if (!existing.empty) throw new Error(`A legacy cafe already exists (id ${existing.docs[0].id}). Only one is allowed.`);
  }

  const ref = db.collection('cafes').doc(); // auto-generated unique ID
  await ref.set({
    name,
    status: 'active',
    legacyData: legacy, // true = data still in old global collections
    createdAt: FieldValue.serverTimestamp(),
    createdBy: 'local-admin-script',
  });
  await db.collection('auditLogs').add({
    action: 'cafe.create',
    actorUid: 'local-admin-script',
    cafeId: ref.id,
    details: { name, legacy },
    at: FieldValue.serverTimestamp(),
  });
  console.log(`Created cafe "${name}" with ID: ${ref.id}${legacy ? '  (legacy data)' : ''}`);
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
    case 'list-cafes':
      return listCafes();
    case 'list-users':
      return listUsers();
    default:
      console.log('Commands: create-super-admin <email> [name] | create-cafe <name> [--legacy] | list-cafes | list-users');
  }
}

main().catch((err) => {
  console.error('FAILED:', err.message);
  process.exit(1);
});
