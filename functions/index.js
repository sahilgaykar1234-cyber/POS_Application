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
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { ROLES, canManageUser, validateInvite } = require('./src/permissions');
const { validateCafeInput } = require('./src/cafes');
const { evaluateSubscription } = require('./src/subscriptions');

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
 * Creates a Manager/Captain account WITHOUT a password, sets role claims,
 * writes the profile, and returns a one-time "set your password" link.
 * Callers must have already checked permissions.
 */
async function createStaffAccount(caller, target) {
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
}

/** Invite a Manager or Captain (the app also emails the link). */
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

  return createStaffAccount(caller, target);
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

// =============================================================================
// Cafes (Super Admin)
// =============================================================================

function requireSuperAdmin(request) {
  const caller = requireCaller(request);
  if (caller.role !== ROLES.SUPER_ADMIN) throw new HttpsError('permission-denied', 'Super Admin only.');
  return caller;
}

const ts = (ms) => (ms == null ? null : admin.firestore.Timestamp.fromMillis(ms));

/** Next sequential subscription receipt number, e.g. RCPT-0007 (inside a transaction). */
async function nextReceiptNo(tx) {
  const ref = db.collection('counters').doc('subscriptionReceipts');
  const snap = await tx.get(ref);
  const next = (snap.exists ? Number(snap.get('next')) || 1 : 1);
  tx.set(ref, { next: next + 1 }, { merge: true });
  return `RCPT-${String(next).padStart(4, '0')}`;
}

/**
 * Create a cafe with a unique auto-generated ID, seed its settings, optionally
 * record the first subscription payment and invite the first Manager.
 */
exports.createCafe = onCall(async (request) => {
  const caller = requireSuperAdmin(request);
  const parsed = validateCafeInput(request.data);
  if (!parsed.ok) throw new HttpsError('invalid-argument', parsed.error);
  const v = parsed.value;

  const dup = await db.collection('cafes').where('name', '==', v.name).limit(1).get();
  if (!dup.empty && dup.docs[0].get('status') !== 'deleted') {
    throw new HttpsError('already-exists', `A cafe named "${v.name}" already exists.`);
  }

  const cafeRef = db.collection('cafes').doc();
  const now = admin.firestore.FieldValue.serverTimestamp();
  let receiptNo = null;

  await db.runTransaction(async (tx) => {
    if (v.payment) receiptNo = await nextReceiptNo(tx);

    tx.set(cafeRef, {
      name: v.name,
      ownerName: v.ownerName,
      ownerEmail: v.ownerEmail,
      contactNumber: v.contactNumber,
      address: v.address,
      gstNumber: v.gstNumber,
      status: 'active',
      legacyData: false,
      subscription: {
        planId: v.subscription.planId,
        planName: v.subscription.planName,
        billingCycle: v.subscription.billingCycle,
        status: v.subscription.status,
        startDate: ts(v.subscription.startMs),
        expiryDate: ts(v.subscription.expiryMs),
        amount: v.subscription.amount,
        paymentStatus: v.payment ? 'paid' : v.subscription.paymentStatus,
        lastPaymentAt: v.payment ? ts(v.payment.paidAtMs) : null,
      },
      createdAt: now,
      createdBy: caller.uid,
    });

    // Business/receipt settings the POS reads (same fields as before).
    tx.set(cafeRef.collection('settings').doc('business'), {
      shopName: v.name,
      tagline: '',
      ownerName: v.ownerName,
      mobileNumber: v.contactNumber,
      email: v.ownerEmail,
      gstNumber: v.gstNumber,
      address: v.address,
      shopLogoBase64: v.logoBase64,
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
      updatedAt: now,
    });

    if (v.payment) {
      tx.set(db.collection('subscriptionPayments').doc(), {
        cafeId: cafeRef.id,
        cafeName: v.name,
        receiptNo,
        amount: v.payment.amount,
        method: v.payment.method,
        referenceId: v.payment.referenceId,
        notes: v.payment.notes,
        planName: v.subscription.planName,
        periodStart: ts(v.subscription.startMs),
        periodEnd: ts(v.subscription.expiryMs),
        paidAt: ts(v.payment.paidAtMs),
        recordedBy: caller.uid,
        createdAt: now,
      });
    }
  });

  await writeAudit({
    action: 'cafe.create',
    actorUid: caller.uid,
    actorRole: caller.role,
    cafeId: cafeRef.id,
    details: { name: v.name, payment: v.payment ? v.payment.amount : null },
  });

  let managerSetupLink = null;
  let managerError = null;
  if (v.manager) {
    try {
      const res = await createStaffAccount(caller, { ...v.manager, role: ROLES.MANAGER, cafeId: cafeRef.id });
      managerSetupLink = res.setupLink;
    } catch (err) {
      // The cafe is created either way; the manager can be invited again later.
      managerError = err instanceof HttpsError ? err.message : 'Could not create the manager account.';
    }
  }

  return { cafeId: cafeRef.id, receiptNo, managerEmail: v.manager ? v.manager.email : null, managerSetupLink, managerError };
});

/**
 * Soft-delete a cafe: status "deleted", all its staff disabled and signed out.
 * No data is removed, so it can be restored. Requires typing the cafe name.
 */
exports.deleteCafe = onCall(async (request) => {
  const caller = requireSuperAdmin(request);
  const cafeId = String(request.data?.cafeId ?? '');
  const confirmName = String(request.data?.confirmName ?? '').trim();
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(cafeId)) throw new HttpsError('invalid-argument', 'Invalid cafe.');

  const ref = db.collection('cafes').doc(cafeId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Cafe not found.');
  if (confirmName !== snap.get('name')) throw new HttpsError('failed-precondition', 'The cafe name you typed does not match.');

  const staff = await db.collection('users').where('cafeId', '==', cafeId).get();
  for (const u of staff.docs) {
    await auth.updateUser(u.id, { disabled: true }).catch(() => {});
    await auth.revokeRefreshTokens(u.id).catch(() => {});
    await u.ref.update({ status: 'disabled', updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  await ref.update({
    status: 'deleted',
    statusBeforeDelete: snap.get('status') ?? 'active',
    deletedAt: admin.firestore.FieldValue.serverTimestamp(),
    deletedBy: caller.uid,
  });
  await writeAudit({
    action: 'cafe.delete',
    actorUid: caller.uid,
    actorRole: caller.role,
    cafeId,
    details: { name: snap.get('name'), staffDisabled: staff.size },
  });
  return { ok: true, staffDisabled: staff.size };
});

// =============================================================================
// Daily subscription check (06:00 India time)
// =============================================================================

async function notify(cafeId, cafeName, key, audience, payload) {
  // Deterministic id = one notice per cafe/event/audience (no duplicates).
  const id = `${cafeId}_${key}_${audience}`;
  const ref = db.collection('notifications').doc(id);
  const exists = (await ref.get()).exists;
  if (exists) return false;
  await ref.set({
    ...payload,
    audience,
    cafeId,
    cafeName,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return true;
}

exports.checkSubscriptions = onSchedule({ schedule: 'every day 06:00', timeZone: 'Asia/Kolkata' }, async () => {
  const nowMs = Date.now();
  const cafes = await db.collection('cafes').get();
  let expired = 0;
  let reminders = 0;

  for (const doc of cafes.docs) {
    const cafe = doc.data();
    const action = evaluateSubscription(cafe, nowMs);
    if (!action) continue;
    const name = cafe.name || doc.id;
    const dateStr = new Date(action.expiryMs).toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'short', year: 'numeric' });

    if (action.type === 'expired') {
      if (action.setExpired) {
        await doc.ref.update({ 'subscription.status': 'expired', 'subscription.expiredAt': admin.firestore.FieldValue.serverTimestamp() });
        await writeAudit({ action: 'subscription.expired', actorUid: 'system', cafeId: doc.id, details: { expiry: dateStr } });
        expired++;
      }
      await notify(doc.id, name, action.key, 'superAdmin', {
        type: 'subscription_expired',
        title: `${name}: subscription expired`,
        message: `Expired on ${dateStr}. POS access is paused until renewal. No data was deleted.`,
      });
      await notify(doc.id, name, action.key, 'cafe', {
        type: 'subscription_expired',
        title: 'Subscription expired',
        message: `Your POS subscription expired on ${dateStr}. Please renew to continue. Your data is safe.`,
      });
    } else {
      const sent = await notify(doc.id, name, action.key, 'superAdmin', {
        type: 'subscription_expiring',
        title: `${name}: subscription expiring`,
        message: `Expires on ${dateStr} (${action.daysLeft} day${action.daysLeft === 1 ? '' : 's'} left).`,
      });
      await notify(doc.id, name, action.key, 'cafe', {
        type: 'subscription_expiring',
        title: 'Subscription expiring soon',
        message: `Your POS subscription expires on ${dateStr}. Please renew to avoid interruption.`,
      });
      if (sent) reminders++;
    }
  }
  console.log(`checkSubscriptions: ${cafes.size} cafes, ${expired} newly expired, ${reminders} reminders`);
});
