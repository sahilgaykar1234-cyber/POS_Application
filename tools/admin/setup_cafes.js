#!/usr/bin/env node
/**
 * ONE command to set up both cafes (no Blaze plan / Cloud Functions needed):
 *
 *   1. Backup of the whole database (backups/…)
 *   2. Flammy Wood: create cafe + move existing data into it (same bill numbers)
 *   3. Pizza La Forno: create cafe + import the full menu from the PDF
 *   4. Simple cafe logins: username + password (default flammywood / laforno);
 *      after login the user chooses Manager or Captain view
 *
 * Safe to run again: finished steps are skipped.
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=~/secrets/suratpos-admin.json
 *   node setup_cafes.js --password 123
 *
 * Options: --flammy-login <username> (default flammywood)
 *          --forno-login  <username> (default laforno)
 *          --password <pw>   (required; used for both logins)
 *          --flammy-manager/--flammy-captain/--forno-manager/--forno-captain <email>
 *              optional extra personal email logins
 */

const { spawnSync } = require('child_process');
const path = require('path');
const { createCafe, createStaff, createCafeLogin, findCafeByName, db } = require('./admin');

const FLAMMY = 'Flammy Wood';
const FORNO = 'Pizza La Forno';
const FORNO_MENU = path.join(__dirname, 'data', 'pizza_la_forno_menu.js');

const args = process.argv.slice(2);
const opt = (n) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : undefined;
};

function run(script, scriptArgs) {
  const r = spawnSync(process.execPath, [path.join(__dirname, script), ...scriptArgs], { stdio: 'inherit', env: process.env });
  if (r.status !== 0) throw new Error(`${script} failed (exit ${r.status}). Nothing after this step was done.`);
}

function step(n, text) {
  console.log(`\n━━━━━━━━ Step ${n}: ${text} ━━━━━━━━`);
}

async function main() {
  if (!opt('--password')) throw new Error('Give a password for the cafe logins, e.g. --password 123');

  // 1. Backup
  step(1, 'Backup');
  run('backup.js', []);

  // 2. Flammy Wood
  step(2, `${FLAMMY}: move existing data`);
  const found = (await findCafeByName(FLAMMY)) || (await findCafeByName('Flamy Wood'));
  let flammyId = found?.id;
  if (!flammyId) {
    const legacy = await db.collection('cafes').where('legacyData', '==', true).limit(1).get();
    flammyId = legacy.empty ? await createCafe(FLAMMY, true) : legacy.docs[0].id;
  }
  const flammyIsLegacy = (await db.collection('cafes').doc(flammyId).get()).get('legacyData') === true;
  if (flammyIsLegacy) {
    run('migrate_legacy.js', ['--cafe', flammyId]);
  } else {
    console.log(`${FLAMMY} already migrated — copying only orders placed since then.`);
    run('migrate_legacy.js', ['--cafe', flammyId, '--delta']);
  }

  // 3. Pizza La Forno
  step(3, `${FORNO}: cafe + menu`);
  const forno = await findCafeByName(FORNO);
  const fornoId = forno ? forno.id : await createCafe(FORNO, false, { contactNumber: '8799243930', tagline: 'Authentic Wood-Fired Taste' });
  const items = await db.collection('cafes').doc(fornoId).collection('menuItems').limit(1).get();
  if (items.empty) {
    run('import_menu.js', ['--cafe', fornoId, '--menu', FORNO_MENU]);
  } else {
    console.log(`${FORNO} already has a menu — skipped. (To re-import: node import_menu.js --cafe ${fornoId} --menu data/pizza_la_forno_menu.js --replace)`);
  }

  // 4. Logins
  step(4, 'Logins');
  const password = opt('--password');
  if (!password) throw new Error('Give a password for the cafe logins, e.g. --password 123');
  const logins = [
    await createCafeLogin(opt('--flammy-login') || 'flammywood', password, flammyId),
    await createCafeLogin(opt('--forno-login') || 'laforno', password, fornoId),
  ];
  const wanted = [
    [opt('--flammy-manager'), 'manager', flammyId],
    [opt('--flammy-captain'), 'captain', flammyId],
    [opt('--forno-manager'), 'manager', fornoId],
    [opt('--forno-captain'), 'captain', fornoId],
  ].filter(([email]) => email);
  const links = [];
  for (const [email, role, cafeId] of wanted) links.push(await createStaff(email, '', role, cafeId));

  // Summary
  console.log('\n══════════════════════ DONE ══════════════════════');
  console.log(`${FLAMMY.padEnd(16)} cafe ID: ${flammyId}`);
  console.log(`${FORNO.padEnd(16)} cafe ID: ${fornoId}`);
  console.log('\nLogins (choose Manager or Captain after signing in):');
  for (const l of logins) console.log(`  ${l.cafeName.padEnd(16)} username: ${l.username}   password: (the one you gave)`);
  if (links.length) {
    console.log('\nOpen each link ONCE to set that person\'s password (links expire in ~1 hour;');
    console.log('after that use "Forgot password?" on the login screen):\n');
    for (const l of links) console.log(`• ${l.cafeName} ${l.role.toUpperCase()} — ${l.email}\n  ${l.link}\n`);
  }
  console.log('Next: flutter build web --release && firebase deploy --only hosting');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('\nFAILED:', err.message);
    process.exit(1);
  });
