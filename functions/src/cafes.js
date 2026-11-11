/**
 * Validation for cafe creation (pure; tested in test/cafes.test.js).
 */

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const SUB_STATUSES = ['trial', 'active', 'pending', 'expired', 'suspended'];
const PAYMENT_METHODS = ['Cash', 'UPI', 'Bank Transfer', 'Card', 'Cheque', 'Other'];

const str = (v, max) => String(v ?? '').trim().slice(0, max);
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)) ? Number(v) : null);

/**
 * @returns {{ok:true, value:object} | {ok:false, error:string}}
 */
function validateCafeInput(input) {
  const d = input || {};
  const name = str(d.name, 80);
  if (name.length < 2) return { ok: false, error: 'Cafe name must be at least 2 characters.' };

  const ownerEmail = str(d.ownerEmail, 254).toLowerCase();
  if (ownerEmail && !EMAIL_RE.test(ownerEmail)) return { ok: false, error: 'Owner email is not valid.' };

  const contactNumber = str(d.contactNumber, 20);
  if (contactNumber && !/^[0-9+\-\s()]{6,20}$/.test(contactNumber)) return { ok: false, error: 'Contact number is not valid.' };

  const gstNumber = str(d.gstNumber, 20).toUpperCase();
  if (gstNumber && !/^[0-9A-Z]{15}$/.test(gstNumber)) return { ok: false, error: 'GST number must be 15 letters/digits.' };

  const logoBase64 = typeof d.logoBase64 === 'string' ? d.logoBase64 : null;
  if (logoBase64 && logoBase64.length > 400 * 1024) return { ok: false, error: 'Logo is too large (max ~300 KB).' };

  // Subscription
  const s = d.subscription || {};
  const status = SUB_STATUSES.includes(s.status) ? s.status : 'trial';
  const startMs = num(s.startDate);
  const expiryMs = num(s.expiryDate);
  if (expiryMs != null && startMs != null && expiryMs <= startMs) {
    return { ok: false, error: 'Subscription expiry must be after the start date.' };
  }
  const amount = num(s.amount) ?? 0;
  if (amount < 0 || amount > 10000000) return { ok: false, error: 'Subscription amount is not valid.' };
  const paymentStatus = ['paid', 'pending'].includes(s.paymentStatus) ? s.paymentStatus : 'pending';

  // Optional first payment
  let payment = null;
  if (d.payment && d.payment.record) {
    const pAmount = num(d.payment.amount);
    if (pAmount == null || pAmount <= 0) return { ok: false, error: 'Payment amount must be more than 0.' };
    payment = {
      amount: pAmount,
      method: PAYMENT_METHODS.includes(d.payment.method) ? d.payment.method : 'Other',
      referenceId: str(d.payment.referenceId, 80),
      paidAtMs: num(d.payment.paidAt) ?? Date.now(),
      notes: str(d.payment.notes, 300),
    };
  }

  // Optional first manager
  let manager = null;
  if (d.manager && (d.manager.email || d.manager.name)) {
    const mEmail = str(d.manager.email, 254).toLowerCase();
    const mName = str(d.manager.name, 80);
    if (!EMAIL_RE.test(mEmail)) return { ok: false, error: 'Manager email is not valid.' };
    if (mName.length < 2) return { ok: false, error: 'Manager name must be at least 2 characters.' };
    manager = { email: mEmail, displayName: mName };
  }

  return {
    ok: true,
    value: {
      name,
      ownerName: str(d.ownerName, 80),
      ownerEmail,
      contactNumber,
      address: str(d.address, 300),
      gstNumber,
      logoBase64,
      subscription: {
        planId: str(s.planId, 128) || null,
        planName: str(s.planName, 80) || null,
        billingCycle: str(s.billingCycle, 20) || null,
        status,
        startMs,
        expiryMs,
        amount,
        paymentStatus,
      },
      payment,
      manager,
    },
  };
}

module.exports = { validateCafeInput, PAYMENT_METHODS, SUB_STATUSES };
