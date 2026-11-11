/**
 * Username logins — MUST stay identical to lib/core/config/app_config.dart.
 * "flammywood" + "123"  ->  Firebase account flammywood@pos.example.com
 * with password "cafepos-123" (Firebase requires 6+ characters).
 */
const USERNAME_DOMAIN = 'pos.example.com';
const PIN_PREFIX = 'cafepos-';

const isUsername = (s) => !String(s).includes('@');
const loginEmail = (input) => {
  const s = String(input).trim().toLowerCase();
  return isUsername(s) ? `${s}@${USERNAME_DOMAIN}` : s;
};
const loginPassword = (identifier, password) => (isUsername(String(identifier).trim()) ? `${PIN_PREFIX}${password}` : password);

module.exports = { USERNAME_DOMAIN, PIN_PREFIX, isUsername, loginEmail, loginPassword };
