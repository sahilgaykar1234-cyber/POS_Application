const test = require('node:test');
const assert = require('node:assert');
const { validateCafeInput } = require('../src/cafes');

test('minimal cafe is valid with trial defaults', () => {
  const r = validateCafeInput({ name: ' Pizza La Forno ' });
  assert.ok(r.ok);
  assert.strictEqual(r.value.name, 'Pizza La Forno');
  assert.strictEqual(r.value.subscription.status, 'trial');
  assert.strictEqual(r.value.manager, null);
  assert.strictEqual(r.value.payment, null);
});

test('full cafe with manager and payment', () => {
  const r = validateCafeInput({
    name: 'Pizza La Forno',
    ownerEmail: 'Owner@Example.com',
    contactNumber: '8799243930',
    gstNumber: '24abcde1234f1z5',
    subscription: { status: 'active', startDate: 1000, expiryDate: 2000, amount: 4999, paymentStatus: 'paid' },
    payment: { record: true, amount: 4999, method: 'UPI', referenceId: 'UTR123' },
    manager: { name: 'Manish', email: 'manager@example.com' },
  });
  assert.ok(r.ok, r.error);
  assert.strictEqual(r.value.ownerEmail, 'owner@example.com');
  assert.strictEqual(r.value.gstNumber, '24ABCDE1234F1Z5');
  assert.strictEqual(r.value.payment.method, 'UPI');
  assert.strictEqual(r.value.manager.email, 'manager@example.com');
});

test('rejects bad input', () => {
  assert.ok(!validateCafeInput({ name: 'X' }).ok);
  assert.ok(!validateCafeInput({ name: 'Cafe', ownerEmail: 'nope' }).ok);
  assert.ok(!validateCafeInput({ name: 'Cafe', gstNumber: '123' }).ok);
  assert.ok(!validateCafeInput({ name: 'Cafe', contactNumber: 'call me' }).ok);
  assert.ok(!validateCafeInput({ name: 'Cafe', subscription: { startDate: 5, expiryDate: 1 } }).ok);
  assert.ok(!validateCafeInput({ name: 'Cafe', payment: { record: true, amount: 0 } }).ok);
  assert.ok(!validateCafeInput({ name: 'Cafe', manager: { name: 'M', email: 'bad' } }).ok);
  assert.ok(!validateCafeInput({ name: 'Cafe', logoBase64: 'x'.repeat(500 * 1024) }).ok);
});
