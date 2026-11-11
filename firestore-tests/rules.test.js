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
const { doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, addDoc, collection, query, where, Timestamp } = require('firebase/firestore');

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
  await assertSucceeds(deleteDoc(doc(db, 'cafes/A/orders/o1')));
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

test('captain: takes orders and settles, but cannot delete or touch menu/expenses', async () => {
  await seed();
  const db = ctx.captainA();
  await assertSucceeds(getDoc(doc(db, 'cafes/A/orders/o1')));
  await assertSucceeds(updateDoc(doc(db, 'cafes/A/orders/o1'), { status: 'preparing', kitchenStatus: 'preparing' }));
  await assertSucceeds(addDoc(collection(db, 'cafes/A/orders'), { totalPrice: 1, status: 'pending' }));
  await assertSucceeds(updateDoc(doc(db, 'cafes/A/orders/o1'), { paymentStatus: 'paid_cash', status: 'completed' }));
  await assertFails(deleteDoc(doc(db, 'cafes/A/orders/o1')));
  await assertFails(setDoc(doc(db, 'cafes/A/menuItems/i9'), { name: 'x' }));
  await assertFails(getDocs(collection(db, 'cafes/A/expenses')));
  await assertFails(addDoc(collection(db, 'cafes/A/expenses'), { amount: 1 }));
  await assertFails(getDoc(doc(db, 'cafes/B/orders/o1')));
  await assertFails(addDoc(collection(db, 'cafes/B/orders'), { totalPrice: 1 }));
});

test('expenses: manager of the cafe only', async () => {
  await seed();
  const m = ctx.managerA();
  await assertSucceeds(addDoc(collection(m, 'cafes/A/expenses'), { amount: 500, category: 'Rent' }));
  await assertSucceeds(getDocs(collection(m, 'cafes/A/expenses')));
  await assertFails(getDocs(collection(ctx.managerB(), 'cafes/A/expenses')));
  await assertFails(addDoc(collection(ctx.managerB(), 'cafes/A/expenses'), { amount: 1 }));
  await assertSucceeds(getDocs(collection(ctx.superAdmin(), 'cafes/A/expenses')));
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

test('subscription payments: manager sees only own cafe', async () => {
  await seed();
  const db = ctx.managerA();
  await assertSucceeds(getDocs(query(collection(db, 'subscriptionPayments'), where('cafeId', '==', 'A'))));
  await assertFails(getDocs(query(collection(db, 'subscriptionPayments'), where('cafeId', '==', 'B'))));
});

test('expired / suspended / inactive / migrating cafes cannot write (data stays readable)', async () => {
  const cases = [
    { subscription: { status: 'active', expiryDate: past() } },
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
