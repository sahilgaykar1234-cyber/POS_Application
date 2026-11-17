/**
 * Pure subscription-expiry logic used by the daily scheduled job.
 * Mirrors lib/core/subscription/cafe_access.dart (warning window = 7 days).
 */

const WARNING_DAYS = 7;
/** The POS keeps working this long after expiry (firestore.rules allows 4 days; the app blocks at the end of the business day 3 days after expiry). */
const GRACE_MS = 4 * 24 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

function toMillis(v) {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

/** yyyy-mm-dd in India time (for notification de-duplication keys). */
function istDateKey(ms) {
  return new Date(ms + 5.5 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/**
 * Decides what the daily job should do for one cafe.
 * @returns {null | {type:'expired'|'expiring', setExpired:boolean, daysLeft:number, expiryMs:number, key:string}}
 */
function evaluateSubscription(cafe, nowMs) {
  if (!cafe || cafe.status === 'deleted') return null;
  const sub = cafe.subscription;
  if (!sub || typeof sub !== 'object') return null;
  if (sub.status === 'suspended') return null;

  const expiryMs = toMillis(sub.expiryDate);
  if (expiryMs == null) return null;

  if (expiryMs <= nowMs) {
    // During the grace period the cafe is told to renew but is not blocked;
    // the status becomes "expired" only once the grace period is over.
    const inGrace = nowMs < expiryMs + GRACE_MS;
    return {
      type: 'expired',
      inGrace,
      setExpired: !inGrace && sub.status !== 'expired',
      daysLeft: 0,
      expiryMs,
      key: `expired_${istDateKey(expiryMs)}`,
    };
  }
  const daysLeft = Math.ceil((expiryMs - nowMs) / DAY_MS);
  if (daysLeft <= WARNING_DAYS) {
    return { type: 'expiring', setExpired: false, daysLeft, expiryMs, key: `expiring_${istDateKey(expiryMs)}` };
  }
  return null;
}

module.exports = { evaluateSubscription, istDateKey, toMillis, WARNING_DAYS, GRACE_MS };
