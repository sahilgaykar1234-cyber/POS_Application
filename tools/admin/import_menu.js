#!/usr/bin/env node
/**
 * Imports a menu data file into ONE cafe: cafes/{cafeId}/categories,
 * subcategories, menuItems.
 *
 *   node import_menu.js --menu data/pizza_la_forno_menu.js --print
 *        Print the menu for checking against the PDF (no Firebase needed).
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/suratpos-admin.json
 *   node import_menu.js --cafe <cafeId> --menu data/pizza_la_forno_menu.js --dry-run
 *   node import_menu.js --cafe <cafeId> --menu data/pizza_la_forno_menu.js
 *
 * SAFETY
 *  - Refuses if the cafe's name does not match the menu's cafeName (so the
 *    Pizza La Forno menu can never land in Flamy Wood by a wrong ID).
 *  - Refuses a cafe that still has legacy (un-migrated) data.
 *  - Refuses if the cafe already has a menu, unless --replace is given;
 *    --replace removes only THAT cafe's menu documents first.
 *  - Never touches orders, settings or any other cafe.
 */

const fs = require('fs');
const path = require('path');
const { buildMenuDocs, formatMenu } = require('./lib/menu_import');

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : undefined;
};

const menuPath = opt('--menu');
const cafeId = opt('--cafe');
if (!menuPath) {
  console.error('Usage: node import_menu.js --menu <file.js> [--print] | --cafe <cafeId> [--dry-run] [--replace]');
  process.exit(1);
}

const menu = require(path.resolve(menuPath));
const docs = buildMenuDocs(menu);
if (docs.errors.length) {
  console.error('Menu file has errors:');
  docs.errors.forEach((e) => console.error('  - ' + e));
  process.exit(1);
}

if (flag('--print') || !cafeId) {
  console.log(`${menu.cafeName} — ${menu.source}`);
  console.log(formatMenu(menu, docs));
  if (!cafeId) process.exit(0);
}

const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');

async function main() {
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credPath || !fs.existsSync(credPath)) throw new Error('Set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON file.');
  const admin = require('firebase-admin');
  admin.initializeApp({ credential: admin.credential.applicationDefault() });
  const db = admin.firestore();
  const { FieldValue } = admin.firestore;
  const DRY = flag('--dry-run');

  const cafeRef = db.collection('cafes').doc(cafeId);
  const cafe = await cafeRef.get();
  if (!cafe.exists) throw new Error(`Cafe ${cafeId} not found.`);
  const name = cafe.get('name');
  console.log(`\nTarget cafe: ${name} (${cafeId})${DRY ? '   [DRY RUN]' : ''}`);

  if (norm(name) !== norm(menu.cafeName)) {
    throw new Error(`Cafe name "${name}" does not match menu "${menu.cafeName}". Refusing to import into the wrong cafe.`);
  }
  if (cafe.get('legacyData') === true) throw new Error('This cafe still has legacy data. Run the migration first.');

  const cols = ['categories', 'subcategories', 'menuItems'];
  const existing = {};
  for (const c of cols) existing[c] = await cafeRef.collection(c).get();
  const existingCount = cols.reduce((n, c) => n + existing[c].size, 0);

  if (existingCount > 0 && !flag('--replace')) {
    throw new Error(`Cafe already has a menu (${existing.menuItems.size} items). Use --replace to overwrite this cafe's menu only.`);
  }

  console.log(`Will write ${docs.categories.length} categories, ${docs.subcategories.length} subcategories, ${docs.items.length} items.`);
  if (existingCount > 0) console.log(`Will first remove this cafe's existing ${existingCount} menu documents (--replace).`);
  if (DRY) return console.log('Dry run: nothing written.');

  const ops = [];
  if (flag('--replace')) for (const c of cols) for (const d of existing[c].docs) ops.push({ del: d.ref });
  const now = FieldValue.serverTimestamp();
  for (const c of docs.categories) ops.push({ ref: cafeRef.collection('categories').doc(c.id), data: { ...c.data, createdAt: now, importedFrom: menu.source } });
  for (const s of docs.subcategories) ops.push({ ref: cafeRef.collection('subcategories').doc(s.id), data: { ...s.data, createdAt: now } });
  for (const i of docs.items) ops.push({ ref: cafeRef.collection('menuItems').doc(i.id), data: { ...i.data, createdAt: now, importedFrom: menu.source } });

  for (let i = 0; i < ops.length; i += 400) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + 400)) op.del ? batch.delete(op.del) : batch.set(op.ref, op.data);
    await batch.commit();
  }

  // Verify by reading back.
  const after = await cafeRef.collection('menuItems').get();
  const byId = new Map(after.docs.map((d) => [d.id, d.data()]));
  const problems = [];
  for (const i of docs.items) {
    const got = byId.get(i.id);
    if (!got) problems.push(`missing ${i.data.name}`);
    else if (JSON.stringify(got.variants) !== JSON.stringify(i.data.variants)) problems.push(`price mismatch ${i.data.name}`);
  }
  if (after.size !== docs.items.length) problems.push(`item count ${after.size} != ${docs.items.length}`);
  if (problems.length) {
    console.error('VERIFY FAILED:\n  ' + problems.join('\n  '));
    process.exit(2);
  }

  await db.collection('auditLogs').add({
    action: 'menu.import',
    actorUid: 'local-admin-script',
    cafeId,
    details: { source: menu.source, items: docs.items.length },
    at: FieldValue.serverTimestamp(),
  });
  console.log(`✔ Imported and verified ${docs.items.length} items for ${name}.`);
}

main().catch((e) => {
  console.error('FAILED:', e.message);
  process.exit(1);
});
