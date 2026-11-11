/**
 * Cloud Functions for privileged staff operations.
 *
 * All of these run with Admin SDK rights on Google's servers. The Flutter app
 * only calls them; it never holds admin credentials. Each function re-checks
 * the caller's role from their verified ID token before doing anything.
 *
 * Deploy:  firebase deploy --only functions   (requires the Blaze plan)
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const { ROLES, canManageUser, validateInvite } = require('./src/permissions');

admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();

// Mumbai region: lowest latency for cafes in India. Must match the Flutter
// client (lib/core/config/app_config.dart -> functionsRegion).
setGlobalOptions({ region: 'asia-south1', maxInstances: 10 });

/** Reads the verified caller from the request, or rejects. */
function requireCaller(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in again.');
  const { uid, token } = request.auth;
  return { uid, role: token.role ?? null, cafeId: token.cafeId ?? null, email: token.email ?? null };
}

async function writeAudit(entry) {
  await db.collection('auditLogs').add({
    ...entry,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/** Loads a staff member's profile doc (source for role/cafe checks). */
async function loadTargetUser(uid) {
  if (typeof uid !== 'string' || uid.length === 0 || uid.length > 128) {
    throw new HttpsError('invalid-argument', 'Invalid user.');
  }
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) throw new HttpsError('not-found', 'User not found.');
  return { uid, ...snap.data() };
}

/**
 * Invite a Manager or Captain.
 * Creates the Auth account WITHOUT a password, sets role claims, writes the
 * profile, and returns a one-time "set your password" link. The app also asks
 * Firebase to email that link to the user.
 */
exports.inviteStaff = onCall(async (request) => {
  const caller = requireCaller(request);
  const parsed = validateInvite(request.data);
  if (!parsed.ok) throw new HttpsError('invalid-argument', parsed.error);
  const target = parsed.value;

  // A manager can only ever add staff to their own cafe.
  if (caller.role === ROLES.MANAGER) target.cafeId = caller.cafeId;

  if (!canManageUser(caller, target)) {
    throw new HttpsError('permission-denied', 'You are not allowed to add this user.');
  }

  const cafeSnap = await db.collection('cafes').doc(target.cafeId).get();
  if (!cafeSnap.exists || cafeSnap.get('status') === 'deleted') {
    throw new HttpsError('not-found', 'Cafe not found.');
  }

  try {
    await auth.getUserByEmail(target.email);
    throw new HttpsError('already-exists', 'An account with this email already exists.');
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    if (err.code !== 'auth/user-not-found') throw new HttpsError('internal', 'Could not check email.');
  }

  const user = await auth.createUser({ email: target.email, displayName: target.displayName });
  try {
    await auth.setCustomUserClaims(user.uid, { role: target.role, cafeId: target.cafeId });
    await db.collection('users').doc(user.uid).set({
      email: target.email,
      displayName: target.displayName,
      role: target.role,
      cafeId: target.cafeId,
      status: 'invited',
      invitedBy: caller.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const setupLink = await auth.generatePasswordResetLink(target.email);

    await writeAudit({
      action: 'staff.invite',
      actorUid: caller.uid,
      actorRole: caller.role,
      cafeId: target.cafeId,
      targetUid: user.uid,
      details: { email: target.email, role: target.role },
    });

    return { uid: user.uid, setupLink };
  } catch (err) {
    // Roll back the half-created account so the invite can be retried.
    await auth.deleteUser(user.uid).catch(() => {});
    await db.collection('users').doc(user.uid).delete().catch(() => {});
    throw new HttpsError('internal', 'Could not create the account. Please try again.');
  }
});

/** Enable or disable a staff account. Disabling also signs them out everywhere. */
exports.setStaffActive = onCall(async (request) => {
  const caller = requireCaller(request);
  const active = request.data?.active;
  if (typeof active !== 'boolean') throw new HttpsError('invalid-argument', 'Missing "active".');

  const target = await loadTargetUser(request.data?.uid);
  if (!canManageUser(caller, target)) {
    throw new HttpsError('permission-denied', 'You are not allowed to change this user.');
  }

  await auth.updateUser(target.uid, { disabled: !active });
  if (!active) await auth.revokeRefreshTokens(target.uid);
  await db.collection('users').doc(target.uid).update({
    status: active ? 'active' : 'disabled',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await writeAudit({
    action: active ? 'staff.enable' : 'staff.disable',
    actorUid: caller.uid,
    actorRole: caller.role,
    cafeId: target.cafeId,
    targetUid: target.uid,
  });
  return { ok: true };
});

/**
 * Admin-initiated password reset. Returns a reset link (the admin never sees
 * or sets the password); the app also triggers Firebase's reset email.
 */
exports.createPasswordResetLink = onCall(async (request) => {
  const caller = requireCaller(request);
  const target = await loadTargetUser(request.data?.uid);
  if (!canManageUser(caller, target)) {
    throw new HttpsError('permission-denied', 'You are not allowed to reset this password.');
  }

  const link = await auth.generatePasswordResetLink(target.email);
  await writeAudit({
    action: 'staff.passwordReset',
    actorUid: caller.uid,
    actorRole: caller.role,
    cafeId: target.cafeId,
    targetUid: target.uid,
  });
  return { link, email: target.email };
});

/**
 * Called by the app after a successful sign-in. Flips a freshly invited
 * account from "invited" to "active" (only ever for the caller themselves).
 */
exports.confirmFirstSignIn = onCall(async (request) => {
  const caller = requireCaller(request);
  const ref = db.collection('users').doc(caller.uid);
  const snap = await ref.get();
  if (snap.exists && snap.get('status') === 'invited') {
    await ref.update({
      status: 'active',
      activatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  return { ok: true };
});
