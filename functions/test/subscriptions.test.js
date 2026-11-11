const test = require('node:test');
const assert = require('node:assert');
const { evaluateSubscription } = require('../src/subscriptions');

const DAY = 24 * 60 * 60 * 1000;
const now = Date.UTC(2026, 10, 11, 6, 0, 0);
const cafe = (sub, status = 'active') => ({ status, subscription: sub });

test('no subscription or no expiry -> nothing to do', () => {
  assert.strictEqual(evaluateSubscription({ status: 'active' }, now), null);
  assert.strictEqual(evaluateSubscription(cafe({ status: 'active' }), now), null);
});

test('far from expiry -> nothing', () => {
  assert.strictEqual(evaluateSubscription(cafe({ status: 'active', expiryDate: now + 30 * DAY }), now), null);
});

test('within 7 days -> expiring reminder (deduplicated per expiry date)', () => {
  const r = evaluateSubscription(cafe({ status: 'active', expiryDate: now + 3 * DAY }), now);
  assert.strictEqual(r.type, 'expiring');
  assert.strictEqual(r.daysLeft, 3);
  assert.strictEqual(r.setExpired, false);
  const r2 = evaluateSubscription(cafe({ status: 'active', expiryDate: now + 3 * DAY }), now + DAY);
  assert.strictEqual(r.key, r2.key, 'same key on the next day -> no duplicate notice');
});

test('past expiry -> mark expired once', () => {
  const r = evaluateSubscription(cafe({ status: 'active', expiryDate: now - DAY }), now);
  assert.strictEqual(r.type, 'expired');
  assert.strictEqual(r.setExpired, true);
  const again = evaluateSubscription(cafe({ status: 'expired', expiryDate: now - DAY }), now);
  assert.strictEqual(again.setExpired, false);
});

test('works with Firestore Timestamp-like values', () => {
  const ts = { toMillis: () => now - 1 };
  assert.strictEqual(evaluateSubscription(cafe({ status: 'trial', expiryDate: ts }), now).type, 'expired');
});

test('deleted cafes and suspended subscriptions are ignored', () => {
  assert.strictEqual(evaluateSubscription(cafe({ status: 'active', expiryDate: now - DAY }, 'deleted'), now), null);
  assert.strictEqual(evaluateSubscription(cafe({ status: 'suspended', expiryDate: now - DAY }), now), null);
});
