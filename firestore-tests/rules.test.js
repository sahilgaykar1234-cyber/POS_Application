/**
 * Tenant-isolation tests for firestore.rules (run: npm test).
 * Two cafes (A, B); users of each role try to reach things they must not.
 */
const test = require('node:test');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, addDoc, collection, query, where, Timestamp, writeBatch, serverTimestamp } = require('firebase/firestore');

let env;

const day = 24 * 60 * 60 * 1000;
const future = () => Timestamp.fromMillis(Date.now() + 30 * day);
const past = () => Timestamp.fromMillis(Date.now() - day);

const ctx = {
  superAdmin: () => env.authenticatedContext('sa', { role: 'superAdmin' }).firestore(),
  managerA: () => env.authenticatedContext('mA', { role: 'manager', cafeId: 'A' }).firestore(),
  captainA: () => env.authenticatedContext('cA', { role: 'captain', cafeId: 'A' }).firestore(),
  managerB: () => env.authenticatedContext('mB', { role: 'manager', cafeId: 'B' }).firestore(),
  noRole: () => env.authenticatedContext('x', {}).firestore(),
  anon: () => env.unauthenticatedContext().firestore(),
};

async function seed(extraCafe = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'cafes/A'), { name: 'Cafe A', status: 'active', ...extraCafe });
    await setDoc(doc(db, 'cafes/B'), { name: 'Cafe B', status: 'active' });
    await setDoc(doc(db, 'cafes/A/orders/o1'), { customerName: 'T1', status: 'pending', kitchenStatus: 'pending', totalPrice: 100 });
    await setDoc(doc(db, 'cafes/B/orders/o1'), { customerName: 'B1', status: 'pending', totalPrice: 50 });
    await setDoc(doc(db, 'cafes/A/menuItems/i1'), { name: 'Pizza', categoryId: 'c1' });
    await setDoc(doc(db, 'cafes/A/settings/business'), { shopName: 'Cafe A' });
    await setDoc(doc(db, 'users/mA'), { role: 'manager', cafeId: 'A' });
    await setDoc(doc(db, 'users/cA'), { role: 'captain', cafeId: 'A' });
    await setDoc(doc(db, 'users/mB'), { role: 'manager', cafeId: 'B' });
    await setDoc(doc(db, 'orders/legacy1'), { customerName: 'old', totalPrice: 10 });
    await setDoc(doc(db, 'subscriptionPayments/p1'), { cafeId: 'A', amount: 999 });
    await setDoc(doc(db, 'subscriptionPayments/p2'), { cafeId: 'B', amount: 999 });
  });
}

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-cafe-pos',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
test.after(async () => env && env.cleanup());

test('tenant isolation: a manager can only see their own cafe', async () => {
  await seed();
  const db = ctx.managerA();
  await assertSucceeds(getDoc(doc(db, 'cafes/A')));
  await assertSucceeds(getDoc(doc(db, 'cafes/A/orders/o1')));
  await assertSucceeds(getDocs(collection(db, 'cafes/A/orders')));
  await assertFails(getDoc(doc(db, 'cafes/B')));
  await assertFails(getDoc(doc(db, 'cafes/B/orders/o1')));
  await assertFails(getDocs(collection(db, 'cafes/B/orders')));
  await assertFails(setDoc(doc(db, 'cafes/B/orders/x'), { totalPrice: 1 }));
  await assertFails(getDocs(collection(db, 'cafes')), 'cannot list all cafes');
});

test('manager runs the POS in their cafe', async () => {
  await seed();
  const db = ctx.managerA();
  await assertSucceeds(addDoc(collection(db, 'cafes/A/orders'), { totalPrice: 10, status: 'pending' }));
  await assertSucceeds(updateDoc(doc(db, 'cafes/A/orders/o1'), { paymentStatus: 'paid', totalPrice: 120 }));
  await assertFails(deleteDoc(doc(db, 'cafes/A/orders/o1')), 'bills are cancelled, never deleted');
  await assertSucceeds(setDoc(doc(db, 'cafes/A/menuItems/i2'), { name: 'New' }));
  await assertSucceeds(setDoc(doc(db, 'cafes/A/settings/business'), { shopName: 'X' }));
});

test('manager cannot change cafe profile/subscription or escalate', async () => {
  await seed();
  const db = ctx.managerA();
  await assertFails(updateDoc(doc(db, 'cafes/A'), { status: 'active', 'subscription.expiryDate': future() }));
  await assertFails(setDoc(doc(db, 'users/mA'), { role: 'superAdmin', cafeId: 'A' }));
  await assertFails(updateDoc(doc(db, 'users/cA'), { cafeId: 'B' }));
  await assertFails(setDoc(doc(db, 'subscriptionPayments/x'), { cafeId: 'A', amount: 1 }));
});

test('captain: kitchen status only (no new orders, no billing, no delete)', async () => {
  await seed();
  const db = ctx.captainA();
  await assertSucceeds(getDoc(doc(db, 'cafes/A/orders/o1')));
  await assertSucceeds(updateDoc(doc(db, 'cafes/A/orders/o1'), { status: 'preparing', kitchenStatus: 'preparing' }));
  await assertSucceeds(updateDoc(doc(db, 'cafes/A/orders/o1'), { status: 'ready', kitchenStatus: 'ready' }));
  await assertFails(updateDoc(doc(db, 'cafes/A/orders/o1'), { totalPrice: 0 }), 'cannot change bill');
  await assertFails(updateDoc(doc(db, 'cafes/A/orders/o1'), { paymentStatus: 'paid_cash' }), 'cannot settle');
  await assertFails(updateDoc(doc(db, 'cafes/A/orders/o1'), { status: 'completed', kitchenStatus: 'completed' }));
  await assertFails(addDoc(collection(db, 'cafes/A/orders'), { totalPrice: 1 }), 'cannot create orders');
  await assertFails(deleteDoc(doc(db, 'cafes/A/orders/o1')));
  await assertFails(setDoc(doc(db, 'cafes/A/menuItems/i9'), { name: 'x' }));
  await assertFails(getDoc(doc(db, 'cafes/B/orders/o1')));
});

test('takeaway token counter: own cafe manager only', async () => {
  await seed();
  await assertSucceeds(setDoc(doc(ctx.managerA(), 'cafes/A/counters/takeaway_20261111'), { next: 2 }));
  await assertSucceeds(getDoc(doc(ctx.captainA(), 'cafes/A/counters/takeaway_20261111')));
  await assertFails(setDoc(doc(ctx.captainA(), 'cafes/A/counters/takeaway_20261111'), { next: 99 }));
  await assertFails(setDoc(doc(ctx.managerB(), 'cafes/A/counters/takeaway_20261111'), { next: 99 }));
});

test('users collection: managers see only their cafe staff; nobody writes', async () => {
  await seed();
  const db = ctx.managerA();
  await assertSucceeds(getDocs(query(collection(db, 'users'), where('cafeId', '==', 'A'))));
  await assertFails(getDocs(query(collection(db, 'users'), where('cafeId', '==', 'B'))));
  await assertFails(getDocs(collection(db, 'users')));
  await assertSucceeds(getDoc(doc(ctx.captainA(), 'users/cA')), 'own profile');
  await assertFails(getDoc(doc(ctx.captainA(), 'users/mA')));
  await assertFails(setDoc(doc(ctx.superAdmin(), 'users/new'), { role: 'manager' }), 'even super admin uses functions');
});

test('unauthenticated and role-less users get nothing', async () => {
  await seed();
  for (const db of [ctx.anon(), ctx.noRole()]) {
    await assertFails(getDoc(doc(db, 'cafes/A')));
    await assertFails(getDoc(doc(db, 'cafes/A/orders/o1')));
    await assertFails(getDoc(doc(db, 'orders/legacy1')));
    await assertFails(setDoc(doc(db, 'cafes/A/orders/z'), { totalPrice: 1 }));
  }
});

test('super admin reaches every cafe and platform data', async () => {
  await seed();
  const db = ctx.superAdmin();
  await assertSucceeds(getDocs(collection(db, 'cafes')));
  await assertSucceeds(getDoc(doc(db, 'cafes/B/orders/o1')));
  await assertSucceeds(updateDoc(doc(db, 'cafes/B'), { status: 'suspended' }));
  await assertSucceeds(setDoc(doc(db, 'plans/basic'), { name: 'Basic', price: 499 }));
  await assertSucceeds(setDoc(doc(db, 'subscriptionPayments/p3'), { cafeId: 'A', amount: 1 }));
  await assertSucceeds(getDoc(doc(db, 'orders/legacy1')), 'can read legacy backup');
  await assertFails(setDoc(doc(db, 'orders/legacy1'), { x: 1 }), 'legacy is read-only');
});

test('super admin panel: platform settings, subscription history, new cafes', async () => {
  await seed();
  const sa = ctx.superAdmin();
  await assertSucceeds(setDoc(doc(sa, 'platform/settings'), { trialDays: 14 }));
  await assertSucceeds(getDoc(doc(sa, 'platform/settings')));
  await assertSucceeds(setDoc(doc(sa, 'cafes/C'), { name: 'Cafe C', status: 'active' }));
  await assertSucceeds(setDoc(doc(sa, 'cafes/C/settings/business'), { shopName: 'Cafe C', dayEndsAt: '05:00' }));
  await assertSucceeds(addDoc(collection(sa, 'cafes/A/subscriptionHistory'), { action: 'assigned' }));
  await assertSucceeds(getDocs(collection(sa, 'cafes/A/subscriptionHistory')));
  await assertSucceeds(getDocs(collection(sa, 'users')), 'staff list');

  const m = ctx.managerA();
  await assertFails(getDoc(doc(m, 'platform/settings')), 'managers cannot read platform settings');
  await assertFails(setDoc(doc(m, 'platform/settings'), { trialDays: 999 }));
  await assertFails(getDocs(collection(m, 'cafes/A/subscriptionHistory')), 'history is Super Admin only');
  await assertFails(setDoc(doc(m, 'cafes/D'), { name: 'Mine', status: 'active' }), 'managers cannot create cafes');
  await assertFails(getDoc(doc(ctx.captainA(), 'platform/settings')));
  await assertFails(getDoc(doc(ctx.anon(), 'platform/settings')));
});

test('logins created in the Super Admin panel (role in users/{uid}, no claims)', async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'users/pm'), { role: 'manager', cafeId: 'A', status: 'active' });
    await setDoc(doc(db, 'users/pc'), { role: 'captain', cafeId: 'A', status: 'active' });
    await setDoc(doc(db, 'users/fake'), { role: 'superAdmin', cafeId: 'A' });
    await setDoc(doc(db, 'users/off'), { role: 'manager', cafeId: 'A', status: 'disabled' });
  });
  const pm = env.authenticatedContext('pm', {}).firestore();
  await assertSucceeds(getDoc(doc(pm, 'cafes/A/orders/o1')), 'panel manager reads own cafe');
  await assertSucceeds(setDoc(doc(pm, 'cafes/A/orders/new'), { status: 'pending', totalPrice: 10 }), 'and takes orders');
  await assertFails(getDoc(doc(pm, 'cafes/B/orders/o1')), 'never another cafe');
  await assertFails(getDoc(doc(pm, 'platform/settings')));
  await assertFails(setDoc(doc(pm, 'users/pm'), { role: 'manager', cafeId: 'B', status: 'active' }), 'cannot move itself to another cafe');

  const pc = env.authenticatedContext('pc', {}).firestore();
  await assertSucceeds(updateDoc(doc(pc, 'cafes/A/orders/o1'), { status: 'preparing', kitchenStatus: 'preparing' }));
  await assertFails(updateDoc(doc(pc, 'cafes/A/orders/o1'), { totalPrice: 1 }), 'captain: status only');

  const fake = env.authenticatedContext('fake', {}).firestore();
  await assertFails(getDoc(doc(fake, 'platform/settings')), 'a document can never grant Super Admin');
  await assertFails(getDoc(doc(fake, 'cafes/B')));
  await assertFails(getDoc(doc(fake, 'cafes/A/orders/o1')), 'superAdmin in a doc is not a cafe role either');

  const off = env.authenticatedContext('off', {}).firestore();
  await assertFails(getDoc(doc(off, 'cafes/A/orders/o1')), 'turned-off login loses access');
});

test('turning a login off also works for claim-based logins', async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'users/mA'), { role: 'manager', cafeId: 'A', status: 'disabled' });
  });
  await assertFails(getDoc(doc(ctx.managerA(), 'cafes/A/orders/o1')));
  await assertFails(setDoc(doc(ctx.managerA(), 'cafes/A/orders/x'), { status: 'pending' }));
});

test('only the Super Admin writes users, and never a Super Admin role', async () => {
  await seed();
  const sa = ctx.superAdmin();
  await assertSucceeds(setDoc(doc(sa, 'users/n1'), { role: 'manager', cafeId: 'A', status: 'active', email: 'n1@pos.example.com' }));
  await assertSucceeds(updateDoc(doc(sa, 'users/n1'), { status: 'disabled' }));
  await assertSucceeds(setDoc(doc(sa, 'users/n2'), { role: 'captain', cafeId: 'B', status: 'active' }));
  await assertFails(setDoc(doc(sa, 'users/n3'), { role: 'superAdmin', cafeId: 'A' }), 'no Super Admin from the panel');
  await assertFails(setDoc(doc(sa, 'users/n4'), { role: 'manager', cafeId: 'ZZZ' }), 'cafe must exist');
  await assertFails(setDoc(doc(sa, 'users/sa'), { role: 'manager', cafeId: 'A' }), 'not its own document');
  await assertFails(setDoc(doc(ctx.managerA(), 'users/n5'), { role: 'manager', cafeId: 'A' }), 'managers cannot create logins');
  await assertFails(updateDoc(doc(ctx.managerA(), 'users/mA'), { status: 'active' }), 'nobody edits their own login');
});

test('bill integrity: no delete, number and token fixed, cancelled is final, series only forward', async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'cafes/A/orders/b1'), { status: 'completed', billNo: '26-27/0007', billSeq: 7, tokenNo: 3, totalPrice: 200, paymentStatus: 'paid_cash' });
    await setDoc(doc(db, 'cafes/A/orders/v1'), { status: 'cancelled', billNo: '26-27/0008', totalPrice: 100, voidReason: 'Test' });
    await setDoc(doc(db, 'cafes/A/counters/bills_2026-27'), { next: 9 });
  });
  const m = ctx.managerA();
  await assertSucceeds(updateDoc(doc(m, 'cafes/A/orders/o1'), { status: 'cancelled', kitchenStatus: 'cancelled', voidReason: 'Customer left' }), 'cancel with a reason');
  await assertFails(deleteDoc(doc(m, 'cafes/A/orders/b1')), 'no delete');
  await assertFails(updateDoc(doc(m, 'cafes/A/orders/b1'), { billNo: '26-27/0001' }), 'bill number fixed');
  await assertFails(updateDoc(doc(m, 'cafes/A/orders/b1'), { billSeq: 1 }));
  await assertFails(updateDoc(doc(m, 'cafes/A/orders/b1'), { tokenNo: 1 }));
  await assertSucceeds(updateDoc(doc(m, 'cafes/A/orders/b1'), { totalPrice: 220 }), 'correcting a bill is allowed (and audit-logged by the app)');
  await assertFails(updateDoc(doc(m, 'cafes/A/orders/b1'), { totalPrice: -5 }), 'no negative totals');
  await assertFails(updateDoc(doc(m, 'cafes/A/orders/b1'), { status: 'deleted' }), 'unknown status');
  await assertFails(updateDoc(doc(m, 'cafes/A/orders/v1'), { status: 'completed' }), 'cancelled is final');
  await assertSucceeds(updateDoc(doc(m, 'cafes/A/orders/v1'), { customerPhone: '', customerName: 'Guest' }), 'but personal data can be removed');
  await assertFails(updateDoc(doc(m, 'cafes/A/orders/v1'), { customerPhone: '', totalPrice: 1 }));
  await assertFails(updateDoc(doc(m, 'cafes/A/counters/bills_2026-27'), { next: 8 }), 'series never goes back');
  await assertSucceeds(updateDoc(doc(m, 'cafes/A/counters/bills_2026-27'), { next: 10 }));
  await assertSucceeds(deleteDoc(doc(ctx.superAdmin(), 'cafes/A/orders/v1')), 'only the Super Admin can remove a bill');
});

test('subscription payments: manager sees only own cafe', async () => {
  await seed();
  const db = ctx.managerA();
  await assertSucceeds(getDocs(query(collection(db, 'subscriptionPayments'), where('cafeId', '==', 'A'))));
  await assertFails(getDocs(query(collection(db, 'subscriptionPayments'), where('cafeId', '==', 'B'))));
});

test('expired / suspended / inactive / migrating cafes cannot write (data stays readable)', async () => {
  const cases = [
    { subscription: { status: 'active', expiryDate: Timestamp.fromMillis(Date.now() - 5 * day) } },
    { subscription: { status: 'expired' } },
    { subscription: { status: 'suspended', expiryDate: future() } },
    { status: 'suspended' },
    { status: 'inactive' },
    { legacyData: true },
  ];
  for (const extra of cases) {
    await seed(extra);
    const m = ctx.managerA();
    await assertSucceeds(getDoc(doc(m, 'cafes/A/orders/o1')));
    await assertFails(addDoc(collection(m, 'cafes/A/orders'), { totalPrice: 1 }), JSON.stringify(extra));
    await assertFails(setDoc(doc(m, 'cafes/A/menuItems/i3'), { name: 'x' }));
    await assertFails(updateDoc(doc(ctx.captainA(), 'cafes/A/orders/o1'), { status: 'ready', kitchenStatus: 'ready' }));
  }
  // Trial/pending within the period still works.
  await seed({ subscription: { status: 'pending', expiryDate: future() } });
  await assertSucceeds(addDoc(collection(ctx.managerA(), 'cafes/A/orders'), { totalPrice: 1 }));
  await seed({ subscription: { status: 'trial', expiryDate: future() } });
  await assertSucceeds(addDoc(collection(ctx.managerA(), 'cafes/A/orders'), { totalPrice: 1 }));
});

test('audit logs are append-only and in your own name', async () => {
  await seed();
  const m = ctx.managerA();
  await assertSucceeds(addDoc(collection(m, 'auditLogs'), { actorUid: 'mA', cafeId: 'A', action: 'x' }));
  await assertFails(addDoc(collection(m, 'auditLogs'), { actorUid: 'someoneElse', cafeId: 'A', action: 'x' }));
  await assertFails(addDoc(collection(m, 'auditLogs'), { actorUid: 'mA', cafeId: 'B', action: 'x' }));
});

test('grace period: the POS keeps working for up to 4 days after expiry', async () => {
  await seed({ subscription: { status: 'active', expiryDate: past() } });
  await assertSucceeds(addDoc(collection(ctx.managerA(), 'cafes/A/orders'), { totalPrice: 1 }));
  await seed({ subscription: { status: 'active', expiryDate: Timestamp.fromMillis(Date.now() - 3.5 * day) } });
  await assertSucceeds(addDoc(collection(ctx.managerA(), 'cafes/A/orders'), { totalPrice: 1 }));
  await seed({ subscription: { status: 'active', expiryDate: Timestamp.fromMillis(Date.now() - 4 * day - 60000) } });
  await assertFails(addDoc(collection(ctx.managerA(), 'cafes/A/orders'), { totalPrice: 1 }));
});

function claimBatch(db, cafeId, utr, extra = {}, uid = 'mA') {
  const b = writeBatch(db);
  b.set(doc(db, `paymentClaims/${cafeId}`), {
    cafeId, cafeName: 'Cafe', utr, amount: 899, planId: 'std', planName: 'Standard', cycle: 'monthly',
    status: 'pending', submittedBy: uid, submittedAt: serverTimestamp(), ...extra,
  });
  b.set(doc(db, `paymentRefs/${utr}`), { cafeId, createdAt: serverTimestamp() });
  return b.commit();
}

test('pay now: a manager can send a claim, even while blocked, but never renew', async () => {
  await seed({ subscription: { status: 'expired', expiryDate: past() } });
  const m = ctx.managerA();
  await assertSucceeds(claimBatch(m, 'A', '123456789012'));
  // Only one open claim at a time.
  await assertFails(claimBatch(m, 'A', '123456789013'));
  // The cafe can't approve itself or touch its subscription.
  await assertFails(updateDoc(doc(m, 'paymentClaims/A'), { status: 'approved' }));
  await assertFails(updateDoc(doc(m, 'cafes/A'), { 'subscription.status': 'active' }));
  // Super Admin approves; the UTR stays used.
  await assertSucceeds(updateDoc(doc(ctx.superAdmin(), 'paymentClaims/A'), { status: 'approved' }));
  await assertFails(claimBatch(m, 'A', '123456789012'), 'same UTR again');
  await assertSucceeds(claimBatch(m, 'A', '123456789014'), 'new claim after approval');
});

test('pay now: claims are checked and private to the cafe', async () => {
  await seed();
  const m = ctx.managerA();
  await assertFails(claimBatch(m, 'A', '12345'), 'UTR must be 12 digits');
  await assertFails(claimBatch(m, 'A', '123456789012', { status: 'approved' }));
  await assertFails(claimBatch(m, 'A', '123456789012', { amount: -1 }));
  await assertFails(claimBatch(m, 'B', '123456789012'), 'not your cafe');
  await assertFails(claimBatch(ctx.captainA(), 'A', '123456789012', {}, 'cA'), 'captains cannot pay');
  // A UTR used by another cafe is refused.
  await assertSucceeds(claimBatch(ctx.managerB(), 'B', '999999999999', {}, 'mB'));
  await assertFails(claimBatch(m, 'A', '999999999999'));
  await assertFails(getDoc(doc(m, 'paymentClaims/B')));
  await assertFails(getDoc(doc(m, 'paymentRefs/999999999999')));
  // A ref can't be written without its claim.
  await assertFails(setDoc(doc(m, 'paymentRefs/111111111111'), { cafeId: 'A' }));
});

test('platform payee: readable by signed-in users, written by the Super Admin only', async () => {
  await seed();
  await assertSucceeds(setDoc(doc(ctx.superAdmin(), 'platform/payee'), { upiId: 'owner@okaxis' }));
  await assertSucceeds(getDoc(doc(ctx.managerA(), 'platform/payee')));
  await assertFails(getDoc(doc(ctx.anon(), 'platform/payee')));
  await assertFails(setDoc(doc(ctx.managerA(), 'platform/payee'), { upiId: 'thief@okaxis' }));
  await assertFails(getDoc(doc(ctx.managerA(), 'platform/settings')));
});
