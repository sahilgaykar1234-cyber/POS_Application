#!/usr/bin/env node
/**
 * READ-ONLY Firestore backup for the POS app.
 *
 * Exports every collection (and all nested subcollections) of the project to
 * local JSON files, preserving document IDs and Firestore types (Timestamps,
 * references, geopoints, bytes) so the data can be restored exactly.
 *
 * It never writes, updates, or deletes anything in Firestore.
 *
 * Usage (from this folder):
 *   npm install
 *   GOOGLE_APPLICATION_CREDENTIALS=/secure/path/service-account.json node backup.js
 *
 * Output: <repo>/backups/<project>_<UTC timestamp>/
 *   <collectionPath>.json   one file per collection (path "/" replaced by "__")
 *   manifest.json           document counts + SHA-256 of every file
 *
 * The service-account key gives FULL admin access to your Firebase project.
 * Keep it outside the repo, never commit it, never put it in the Flutter app.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const admin = require('firebase-admin');

const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!credPath || !fs.existsSync(credPath)) {
  console.error('ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON file.');
  console.error('Firebase Console > Project settings > Service accounts > Generate new private key.');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();
const { encode } = require('./lib/firestore_json');

async function exportCollection(colRef, outDir, manifest) {
  const snap = await colRef.get();
  const docs = [];

  for (const doc of snap.docs) {
    docs.push({ id: doc.id, data: encode(doc.data()) });
    // Recurse into subcollections (none exist today, but future-proof).
    const subs = await doc.ref.listCollections();
    for (const sub of subs) await exportCollection(sub, outDir, manifest);
  }

  const fileName = colRef.path.replace(/\//g, '__') + '.json';
  const json = JSON.stringify({ path: colRef.path, count: docs.length, docs }, null, 2);
  fs.writeFileSync(path.join(outDir, fileName), json);

  manifest.collections.push({
    path: colRef.path,
    file: fileName,
    count: docs.length,
    sha256: crypto.createHash('sha256').update(json).digest('hex'),
  });
  console.log(`  ${colRef.path.padEnd(40)} ${docs.length} docs`);
}

async function main() {
  const projectId = JSON.parse(fs.readFileSync(credPath, 'utf8')).project_id;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outDir = path.resolve(__dirname, '..', '..', 'backups', `${projectId}_${stamp}`);
  fs.mkdirSync(outDir, { recursive: true });

  console.log(`Backing up Firestore project "${projectId}" (read-only) to:\n  ${outDir}\n`);

  const manifest = { projectId, createdAt: new Date().toISOString(), collections: [] };
  const roots = await db.listCollections();
  for (const col of roots) await exportCollection(col, outDir, manifest);

  manifest.totalDocuments = manifest.collections.reduce((n, c) => n + c.count, 0);
  fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));

  console.log(`\nDone. ${manifest.collections.length} collections, ${manifest.totalDocuments} documents.`);
  console.log('Keep a copy of this folder somewhere safe (e.g. Google Drive) as well.');
}

main().catch((err) => {
  console.error('Backup FAILED:', err.message);
  process.exit(1);
});
