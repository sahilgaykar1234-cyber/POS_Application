#!/usr/bin/env node
/**
 * Moves the existing single-cafe data (Flamy Wood) from the old global
 * collections into its own cafe:  cafes/{cafeId}/...
 *
 *   orders/{id}                   -> cafes/{cafeId}/orders/{SAME id}  (bill numbers unchanged)
 *   settings/business_settings    -> cafes/{cafeId}/settings/business
 *   menu_categories/{id}.items[]  -> cafes/{cafeId}/categories/{id} + menuItems/{id_NNN}
 *
 * SAFETY
 *  - The old collections are only READ. Nothing is modified or deleted there.
 *  - Re-running is safe (same target IDs are overwritten with the same data).
 *  - Every copied order is compared field-by-field with the original.
 *  - The cafe is switched to the new data (legacyData=false) only if all
 *    checks pass. Use --dry-run first.
 *
 * USAGE
 *   export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/suratpos-admin.json
 *   node migrate_legacy.js --cafe <cafeId> --dry-run    # report only, writes nothing
 *   node migrate_legacy.js --cafe <cafeId>              # migrate + verify + switch over
 *   node migrate_legacy.js --cafe <cafeId> --delta      # later: copy only NEW legacy orders
 *
 * --delta never touches menu/settings and never overwrites an order that
 * already exists in the new location (so edits made in the new app are kept).
 */

const fs = require('fs');
const admin = require('firebase-admin');
const { stableJson } = require('./lib/firestore_json');
const { convertLegacyMenu } = require('./lib/legacy_menu');

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : undefined;
};

const cafeId = opt('--cafe');
const DRY = flag('--dry-run');
const DELTA = flag('--delta');

if (!cafeId) {
  console.error('Usage: node migrate_legacy.js --cafe <cafeId> [--dry-run] [--delta]');
  process.exit(1);
}
const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!credPath || !fs.existsSync(credPath)) {
  console.error('ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON file.');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();
const { FieldValue } = admin.firestore;

const cafeRef = db.collection('cafes').doc(cafeId);

/** Writes in batches of 400 (Firestore limit is 500). */
async function writeAll(ops) {
  if (DRY) return;
  for (let i = 0; i < ops.length; i += 400) {
    const batch = db.batch();
    for (const { ref, data } of ops.slice(i, i + 400)) batch.set(ref, data);
    await batch.commit();
    process.stdout.write(`    wrote ${Math.min(i + 400, ops.length)}/${ops.length}\r`);
  }
  if (ops.length) process.stdout.write('\n');
}

function sumTotals(docs) {
  return docs.reduce((s, d) => s + (Number(d.data().totalPrice) || 0), 0);
}

async function main() {
  const cafeSnap = await cafeRef.get();
  if (!cafeSnap.exists) throw new Error(`Cafe ${cafeId} not found. Create it first: node admin.js create-cafe "Flamy Wood" --legacy`);
  const cafe = cafeSnap.data();
  console.log(`Cafe: ${cafe.name} (${cafeId})  legacyData=${cafe.legacyData === true}${DRY ? '   [DRY RUN]' : ''}${DELTA ? '   [DELTA]' : ''}\n`);

  if (!DELTA && cafe.legacyData !== true) {
    throw new Error('This cafe is already migrated. Use --delta to copy orders created since then.');
  }
  if (DELTA && cafe.legacyData === true) {
    throw new Error('Run the full migration first (without --delta).');
  }

  // ------------------------------------------------------------------ orders
  const legacyOrders = await db.collection('orders').get();
  const target = cafeRef.collection('orders');
  const existing = await target.get();
  const existingIds = new Set(existing.docs.map((d) => d.id));

  const orderOps = [];
  for (const d of legacyOrders.docs) {
    if (DELTA && existingIds.has(d.id)) continue; // never overwrite in delta mode
    orderOps.push({ ref: target.doc(d.id), data: d.data() });
  }
  console.log(`Orders: ${legacyOrders.size} in legacy, ${existing.size} already in cafe, ${orderOps.length} to copy`);
  await writeAll(orderOps);

  let settingsCopied = false;
  let menu = { categories: [], items: [], warnings: [] };

  if (!DELTA) {
    // ---------------------------------------------------------------- settings
    const legacySettings = await db.collection('settings').doc('business_settings').get();
    if (legacySettings.exists) {
      console.log('Settings: copying settings/business_settings');
      if (!DRY) await cafeRef.collection('settings').doc('business').set(legacySettings.data());
      settingsCopied = true;
    } else {
      console.log('Settings: none found in legacy (cafe will use defaults)');
    }

    // -------------------------------------------------------------------- menu
    const legacyMenu = await db.collection('menu_categories').get();
    menu = convertLegacyMenu(legacyMenu.docs.map((d) => ({ id: d.id, data: d.data() })));
    const sourceItems = legacyMenu.docs.reduce((n, d) => n + (Array.isArray(d.get('items')) ? d.get('items').length : 0), 0);
    console.log(`Menu: ${legacyMenu.size} categories, ${sourceItems} items -> ${menu.categories.length} categories, ${menu.items.length} items`);
    menu.warnings.forEach((w) => console.log(`  ! ${w}`));

    const now = FieldValue.serverTimestamp();
    await writeAll([
      ...menu.categories.map((c) => ({ ref: cafeRef.collection('categories').doc(c.id), data: { ...c.data, createdAt: now, migratedFromLegacy: true } })),
      ...menu.items.map((i) => ({ ref: cafeRef.collection('menuItems').doc(i.id), data: { ...i.data, createdAt: now, migratedFromLegacy: true } })),
    ]);
  }

  if (DRY) {
    console.log('\nDry run complete. Nothing was written.');
    return;
  }

  // ------------------------------------------------------------------ verify
  console.log('\nVerifying…');
  const problems = [];
  const after = await target.get();
  const afterById = new Map(after.docs.map((d) => [d.id, d]));

  let checked = 0;
  for (const d of legacyOrders.docs) {
    const copy = afterById.get(d.id);
    if (!copy) {
      problems.push(`order ${d.id} missing in cafe`);
      continue;
    }
    // In delta mode, pre-existing orders may legitimately have been edited.
    if (DELTA && existingIds.has(d.id)) continue;
    if (stableJson(copy.data()) !== stableJson(d.data())) problems.push(`order ${d.id} differs from original`);
    checked++;
  }
  console.log(`  orders compared field-by-field: ${checked}`);
  if (!DELTA) {
    const legacyTotal = sumTotals(legacyOrders.docs);
    const legacyIds = new Set(legacyOrders.docs.map((l) => l.id));
    const cafeTotal = sumTotals(after.docs.filter((d) => legacyIds.has(d.id)));
    console.log(`  sum of totalPrice: legacy ₹${legacyTotal.toFixed(2)}  cafe ₹${cafeTotal.toFixed(2)}`);
    if (Math.abs(legacyTotal - cafeTotal) > 0.001) problems.push('order totals do not match');

    const itemsAfter = await cafeRef.collection('menuItems').where('migratedFromLegacy', '==', true).get();
    console.log(`  menu items in cafe: ${itemsAfter.size} (expected ${menu.items.length})`);
    if (itemsAfter.size !== menu.items.length) problems.push('menu item count mismatch');
  }

  if (problems.length) {
    console.error('\nVERIFICATION FAILED — cafe NOT switched over. Legacy data untouched.');
    problems.slice(0, 50).forEach((p) => console.error('  - ' + p));
    process.exit(2);
  }

  if (!DELTA) {
    await cafeRef.update({
      legacyData: false,
      migratedAt: FieldValue.serverTimestamp(),
      migration: {
        orders: legacyOrders.size,
        categories: menu.categories.length,
        menuItems: menu.items.length,
        settings: settingsCopied,
        menuWarnings: menu.warnings.length,
      },
    });
  }
  await db.collection('auditLogs').add({
    action: DELTA ? 'migration.delta' : 'migration.full',
    actorUid: 'local-admin-script',
    cafeId,
    details: { ordersCopied: orderOps.length },
    at: FieldValue.serverTimestamp(),
  });

  console.log(`\n✔ ${DELTA ? 'Delta copy' : 'Migration'} verified${DELTA ? '' : ' — cafe switched to its own data (legacyData=false)'}.`);
  console.log('  The old collections (orders, menu_categories, settings) were not modified.');
}

main().catch((err) => {
  console.error('FAILED:', err.message);
  process.exit(1);
});
