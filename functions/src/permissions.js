/**
 * Pure authorization rules for staff management. No Firebase imports here so
 * they can be unit-tested directly (see test/permissions.test.js).
 *
 * Roles live in Firebase Auth custom claims: { role, cafeId }.
 * Claims can ONLY be written by the Admin SDK (these Cloud Functions or the
 * local admin script), so a user can never change their own role or cafe.
 */

const ROLES = Object.freeze({
  SUPER_ADMIN: 'superAdmin',
  MANAGER: 'manager',
  CAPTAIN: 'captain',
});

/** Roles that can be created/managed from inside the app. */
const STAFF_ROLES = Object.freeze([ROLES.MANAGER, ROLES.CAPTAIN]);

/**
 * Can `caller` create or manage a user with `target` {role, cafeId, uid?}?
 *
 * - Super Admin: any manager/captain in any cafe.
 * - Manager:     captains in their own cafe only.
 * - Captain:     nobody.
 * - Nobody can manage a Super Admin from the app (only the local admin script).
 * - Nobody can manage their own account (no self-disable / self-promotion).
 */
function canManageUser(caller, target) {
  if (!caller || !target) return false;
  if (!STAFF_ROLES.includes(target.role)) return false;
  if (target.uid && target.uid === caller.uid) return false;

  if (caller.role === ROLES.SUPER_ADMIN) {
    return typeof target.cafeId === 'string' && target.cafeId.length > 0;
  }
  if (caller.role === ROLES.MANAGER) {
    return (
      target.role === ROLES.CAPTAIN &&
      typeof caller.cafeId === 'string' &&
      caller.cafeId.length > 0 &&
      target.cafeId === caller.cafeId
    );
  }
  return false;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Validates and normalises invite input. Returns {ok, value?, error?}. */
function validateInvite(input) {
  const email = String(input?.email ?? '').trim().toLowerCase();
  const displayName = String(input?.displayName ?? '').trim();
  const role = String(input?.role ?? '');
  const cafeId = String(input?.cafeId ?? '').trim();

  if (!EMAIL_RE.test(email) || email.length > 254) return { ok: false, error: 'Enter a valid email address.' };
  if (displayName.length < 2 || displayName.length > 80) return { ok: false, error: 'Name must be 2–80 characters.' };
  if (!STAFF_ROLES.includes(role)) return { ok: false, error: 'Role must be manager or captain.' };
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(cafeId)) return { ok: false, error: 'Invalid cafe.' };

  return { ok: true, value: { email, displayName, role, cafeId } };
}

module.exports = { ROLES, STAFF_ROLES, canManageUser, validateInvite };
