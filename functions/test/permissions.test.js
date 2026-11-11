const test = require('node:test');
const assert = require('node:assert');
const { canManageUser, validateInvite } = require('../src/permissions');

const superAdmin = { uid: 'sa', role: 'superAdmin', cafeId: null };
const managerA = { uid: 'mA', role: 'manager', cafeId: 'cafeA' };
const captainA = { uid: 'cA', role: 'captain', cafeId: 'cafeA' };

test('super admin can manage managers and captains in any cafe', () => {
  assert.ok(canManageUser(superAdmin, { role: 'manager', cafeId: 'cafeA' }));
  assert.ok(canManageUser(superAdmin, { role: 'captain', cafeId: 'cafeB' }));
});

test('super admin cannot create/manage another super admin from the app', () => {
  assert.ok(!canManageUser(superAdmin, { role: 'superAdmin', cafeId: 'cafeA' }));
});

test('super admin must target a specific cafe', () => {
  assert.ok(!canManageUser(superAdmin, { role: 'manager', cafeId: '' }));
  assert.ok(!canManageUser(superAdmin, { role: 'manager' }));
});

test('manager can manage captains of their own cafe only', () => {
  assert.ok(canManageUser(managerA, { role: 'captain', cafeId: 'cafeA' }));
  assert.ok(!canManageUser(managerA, { role: 'captain', cafeId: 'cafeB' }), 'other cafe');
  assert.ok(!canManageUser(managerA, { role: 'manager', cafeId: 'cafeA' }), 'other manager');
  assert.ok(!canManageUser(managerA, { role: 'superAdmin', cafeId: 'cafeA' }), 'escalation');
});

test('manager without a cafe claim can do nothing', () => {
  const broken = { uid: 'x', role: 'manager', cafeId: null };
  assert.ok(!canManageUser(broken, { role: 'captain', cafeId: null }));
});

test('captain and unknown roles can manage nobody', () => {
  assert.ok(!canManageUser(captainA, { role: 'captain', cafeId: 'cafeA' }));
  assert.ok(!canManageUser({ uid: 'u', role: null, cafeId: 'cafeA' }, { role: 'captain', cafeId: 'cafeA' }));
  assert.ok(!canManageUser(null, { role: 'captain', cafeId: 'cafeA' }));
});

test('nobody can manage their own account', () => {
  assert.ok(!canManageUser(managerA, { uid: 'mA', role: 'captain', cafeId: 'cafeA' }));
});

test('validateInvite normalises good input', () => {
  const r = validateInvite({ email: '  Ravi@Example.COM ', displayName: ' Ravi ', role: 'captain', cafeId: 'abc123' });
  assert.deepStrictEqual(r, { ok: true, value: { email: 'ravi@example.com', displayName: 'Ravi', role: 'captain', cafeId: 'abc123' } });
});

test('validateInvite rejects bad input', () => {
  assert.ok(!validateInvite({ email: 'nope', displayName: 'Ravi', role: 'captain', cafeId: 'a' }).ok);
  assert.ok(!validateInvite({ email: 'a@b.co', displayName: 'R', role: 'captain', cafeId: 'a' }).ok);
  assert.ok(!validateInvite({ email: 'a@b.co', displayName: 'Ravi', role: 'superAdmin', cafeId: 'a' }).ok);
  assert.ok(!validateInvite({ email: 'a@b.co', displayName: 'Ravi', role: 'captain', cafeId: '../x' }).ok);
  assert.ok(!validateInvite(undefined).ok);
});
