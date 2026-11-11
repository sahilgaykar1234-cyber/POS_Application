const test = require('node:test');
const assert = require('node:assert');
const { loginEmail, loginPassword } = require('../lib/login');

// Must match lib/core/config/app_config.dart (see test/auth_test.dart).
test('username login mapping', () => {
  assert.strictEqual(loginEmail(' FlammyWood '), 'flammywood@pos.example.com');
  assert.strictEqual(loginPassword('flammywood', '123'), 'cafepos-123');
  assert.ok(loginPassword('x', '123').length >= 6, 'Firebase needs 6+ chars');
});

test('email logins pass through unchanged', () => {
  assert.strictEqual(loginEmail('Owner@Gmail.com'), 'owner@gmail.com');
  assert.strictEqual(loginPassword('owner@gmail.com', 'secret12'), 'secret12');
});
