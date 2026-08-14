#!/usr/bin/env node
// CLI for the roster importer. See README.md.
//
// Writing is opt-in: every command that changes Firestore requires --apply.
// Without it you get a diff and nothing else.

import { existsSync, readFileSync } from 'node:fs';

import {
  buildPlan,
  findOrphans,
  findRevoked,
  parseRows,
  partitionByStatus,
  resolveColumns,
  validateIdentity,
} from './diff.mjs';
import {
  COLUMNS,
  IDENTITY_COLUMN,
  IMPORTABLE_STATUSES,
  isCanonicalPassType,
  normaliseStatus,
} from './mapping.mjs';
// `./sheets.mjs` and `./firestore.mjs` are imported lazily inside the commands
// that need them, so `npm test` and the usage text work before `npm install`.
async function cloud() {
  try {
    const [sheets, firestore] = await Promise.all([
      import('./sheets.mjs'),
      import('./firestore.mjs'),
    ]);
    return { ...sheets, ...firestore };
  } catch (error) {
    if (error?.code === 'ERR_MODULE_NOT_FOUND') {
      fail('Dependencies are not installed. Run:\n\n    cd backend/import-roster && npm install');
    }
    throw error;
  }
}

// ── argv ───────────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
const command = argv[0];
const positional = argv.slice(1).filter((a) => !a.startsWith('--'));
const flag = (name) => argv.includes(`--${name}`);
const option = (name, fallback) => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};

/// The Firebase CLI already knows which project this is — it is in
/// ../.firebaserc, which is committed. Read it rather than making every command
/// carry --project.
function projectFromFirebaserc() {
  try {
    const rc = JSON.parse(readFileSync(new URL('../.firebaserc', import.meta.url), 'utf8'));
    return rc?.projects?.default;
  } catch {
    return undefined;
  }
}

const config = {
  keyFile: option('key', process.env.GOOGLE_APPLICATION_CREDENTIALS ?? './serviceAccountKey.json'),
  projectId: option('project', process.env.FIREBASE_PROJECT_ID ?? projectFromFirebaserc()),
  spreadsheetId: option('sheet', process.env.SHEET_ID),
  range: option('range', process.env.SHEET_RANGE ?? 'A1:Z10000'),
  apply: flag('apply'),
};

function fail(message) {
  console.error(`\n✖ ${message}\n`);
  process.exit(1);
}

function requireSheet() {
  if (!config.spreadsheetId) {
    fail('No spreadsheet id. Pass --sheet=<id> or set SHEET_ID.\n  The id is the long string in the Sheet URL between /d/ and /edit.');
  }
}

function requireProject() {
  if (!config.projectId) {
    fail(
      'No Firebase project id.\n' +
        '  Normally read from ../.firebaserc — check that it exists and has projects.default.\n' +
        '  Otherwise pass --project=<id> or set FIREBASE_PROJECT_ID.'
    );
  }
}

/// The Admin SDK fails obscurely on a missing key file; say the useful thing.
function requireKeyFile() {
  if (!existsSync(config.keyFile)) {
    fail(
      `No service-account key at ${config.keyFile}.\n` +
        '  Firebase console → Project settings → Service accounts → Generate new private key,\n' +
        '  save it as backend/import-roster/serviceAccountKey.json (gitignored),\n' +
        '  or point at it with --key=<path>.'
    );
  }
}

// ── commands ───────────────────────────────────────────────────────────────

async function cmdHeaders() {
  requireSheet();
  const { readSheet } = await cloud();
  const { header, rows } = await readSheet(config);
  console.log(`\nSheet "${config.range}" — ${rows.length} populated data rows.\n`);
  console.log('Header row:\n');
  header.forEach((h, i) => console.log(`  [${String(i).padStart(2)}]  ${h}`));
  const statusAt = header.findIndex(
    (h) => String(h).trim().toLowerCase() === String(COLUMNS.status).trim().toLowerCase()
  );
  if (statusAt >= 0) {
    const counts = new Map();
    for (const cells of rows) {
      const value = normaliseStatus(cells[statusAt]);
      counts.set(value || '(blank)', (counts.get(value || '(blank)') ?? 0) + 1);
    }
    console.log(`\nDistinct values in "${COLUMNS.status}" — counts only, no personal data:\n`);
    for (const [value, count] of [...counts].sort((a, b) => b[1] - a[1])) {
      console.log(`  ${String(count).padStart(5)}  ${value}`);
    }
    console.log(`\nOnly ${JSON.stringify(IMPORTABLE_STATUSES)} is imported. Everything else is`);
    console.log(`treated as if the registration does not exist. Read the list above: a value`);
    console.log(`that ought to count as paid, but is not spelled "paid", is a guest missing`);
    console.log(`at the door.`);
  }

  // Same treatment for pass types. The design assumes a short label; a Sheet
  // that also carries the price and the pricing tier in this column is something
  // to see before it reaches a 16pt row on a phone.
  const passAt = header.findIndex(
    (h) => String(h).trim().toLowerCase() === String(COLUMNS.ticketType).trim().toLowerCase()
  );
  if (passAt >= 0) {
    const counts = new Map();
    for (const cells of rows) {
      const value = String(cells[passAt] ?? '').trim() || '(blank)';
      counts.set(value, (counts.get(value) ?? 0) + 1);
    }
    console.log(`\nDistinct values in "${COLUMNS.ticketType}" — counts only:\n`);
    for (const [value, count] of [...counts].sort((a, b) => b[1] - a[1])) {
      console.log(`  ${String(count).padStart(5)}  ${value}`);
    }
  }

  console.log(`\nPut these column names into mapping.mjs, then run: npm run import\n`);
}

async function cmdImport() {
  requireSheet();
  requireProject();

  requireKeyFile();
  const { readSheet, initAdmin, fetchParticipants, applyPlan } = await cloud();
  const { header, rows: cells } = await readSheet(config);
  const resolved = resolveColumns(header);

  const declared = new Set(Object.values(resolved));
  const ignored = header.filter((_, i) => !declared.has(i));

  const { usable, blank, duplicated } = validateIdentity(parseRows(cells, resolved));

  console.log(`\nSheet:      ${cells.length} data rows`);
  console.log(`Identity:   "${IDENTITY_COLUMN}"`);
  if (ignored.length) console.log(`Ignored:    ${ignored.join(', ')}`);

  // A bad key is how a re-import corrupts a balance. Refuse rather than proceed.
  if (blank.length) {
    fail(
      `${blank.length} row(s) have a blank or unusable ${IDENTITY_COLUMN}: sheet rows ${blank.join(', ')}.\n` +
        `  Fill them in — the importer will not invent an id.`
    );
  }
  if (duplicated.length) {
    fail(
      `Duplicate ${IDENTITY_COLUMN} values:\n` +
        duplicated.map((d) => `    "${d.id}" on sheet rows ${d.rows.join(' and ')}`).join('\n') +
        `\n  Two people sharing a key would share a balance.`
    );
  }

  const { importable, excluded, breakdown } = partitionByStatus(usable);

  console.log(`Status:     ${importable.length} paid, ${excluded.length} skipped`);
  if (breakdown.size) {
    // Read this. A value like "Paid (bank transfer)" would be skipped by the
    // Paid-only rule, and that guest would simply be missing at the door.
    for (const [status, count] of [...breakdown].sort((a, b) => b[1] - a[1])) {
      console.log(`              ${String(count).padStart(5)}  ${status}`);
    }
  }
  console.log('');

  const app = initAdmin(config);
  const db = app.firestore();
  const existing = await fetchParticipants(db);
  console.log(`Firestore:  ${existing.size} participants already present\n`);

  const plan = buildPlan(importable, existing);
  const orphans = findOrphans(importable, existing);
  const revoked = findRevoked(excluded, existing);

  // A pass type nobody anticipated would otherwise reach a phone screen as a
  // 46-character invoice line, and group as its own category in any report.
  const unrecognised = new Map();
  for (const op of [...plan.creates, ...plan.updates]) {
    const type = op.data.ticketType;
    if (type && !isCanonicalPassType(type)) {
      unrecognised.set(type, (unrecognised.get(type) ?? 0) + 1);
    }
  }
  if (unrecognised.size) {
    console.log(`  Pass types not recognised — kept verbatim, so they will show as-is:`);
    for (const [type, count] of [...unrecognised].sort((a, b) => b[1] - a[1])) {
      console.log(`      ${String(count).padStart(3)}  ${type}`);
    }
    console.log('');
  }

  console.log(`  create     ${plan.creates.length}`);
  console.log(`  update     ${plan.updates.length}   (roster fields only)`);
  console.log(`  unchanged  ${plan.unchanged.length}`);
  console.log(`  in Firestore but not in the Sheet: ${orphans.length}\n`);

  for (const c of plan.creates.slice(0, 20)) {
    console.log(`  + ${c.id.padEnd(24)} ${c.data.name}  (${c.data.ticketType})`);
  }
  if (plan.creates.length > 20) console.log(`    … and ${plan.creates.length - 20} more`);

  for (const u of plan.updates.slice(0, 20)) {
    console.log(`  ~ ${u.id.padEnd(24)} ${u.changes.join('; ')}`);
  }
  if (plan.updates.length > 20) console.log(`    … and ${plan.updates.length - 20} more`);

  if (revoked.length) {
    console.log(`\n  Status is no longer importable, but they are already in Firestore:`);
    for (const r of revoked.slice(0, 20)) {
      const state = r.checkedIn ? `checked in, ${(r.balance / 100).toFixed(2)} €` : 'not checked in';
      console.log(`  ! ${r.id.padEnd(24)} ${r.name}  [${r.status}]  (${state})`);
    }
    console.log(`    NOT touched. Somebody who paid, checked in and loaded money onto a`);
    console.log(`    bracelet before being refunded still has that money. What happens to`);
    console.log(`    it is an organiser decision, not this script's.`);
  }

  if (orphans.length) {
    console.log(`\n  Present in Firestore, absent from the Sheet — NOT deleted:`);
    for (const o of orphans.slice(0, 20)) {
      const state = o.checkedIn ? `checked in, ${(o.balance / 100).toFixed(2)} €` : 'not checked in';
      console.log(`  ? ${o.id.padEnd(24)} ${o.name}  (${state})`);
    }
    console.log(`    Refunds and cancellations are an organiser decision. Handle them in the`);
    console.log(`    admin panel, not here — some of these people may have money on a bracelet.`);
  }

  if (!plan.creates.length && !plan.updates.length) {
    console.log(`\n✔ Nothing to do.\n`);
    return;
  }

  if (!config.apply) {
    console.log(`\nDry run. Nothing was written. Re-run with --apply to commit.\n`);
    return;
  }

  console.log(`\nApplying…`);
  const written = await applyPlan(db, plan);
  console.log(`\n✔ ${written} document(s) written. Balances and check-in state untouched.\n`);
}

async function cmdSetRole() {
  requireProject();
  const [email, role] = positional;
  if (!email || !role) fail('Usage: npm run set-role -- <email> <reception|bar|admin> --apply');

  requireKeyFile();
  const { initAdmin, setRole, describeUser } = await cloud();
  initAdmin(config);
  if (!config.apply) {
    const before = await describeUser(email);
    console.log(`\n${before.email}\n  uid:            ${before.uid}`);
    console.log(`  current claims: ${JSON.stringify(before.claims)}`);
    console.log(`  would set:      { "role": "${role}" }`);
    console.log(`\nDry run. Re-run with --apply to commit.\n`);
    return;
  }
  const uid = await setRole(email, role);
  const after = await describeUser(email);
  console.log(`\n✔ ${email} (${uid}) → ${JSON.stringify(after.claims)}`);
  console.log(`  They must sign out and back in before the new role takes effect.\n`);
}

async function cmdSeedDrinks() {
  requireProject();
  requireKeyFile();
  const { initAdmin, seedDrinks, DEFAULT_DRINKS } = await cloud();
  const app = initAdmin(config);
  const db = app.firestore();

  if (!config.apply) {
    // Read the live collection even on a dry run: what this replaces matters more
    // than what it writes, and the bar sells from whatever is left active.
    const existing = await db.collection('drinks').get();
    const wanted = new Set(DEFAULT_DRINKS.map((d) => d.id));

    console.log(`\nWould write ${DEFAULT_DRINKS.length} drinks:\n`);
    DEFAULT_DRINKS.forEach((d) => {
      const was = existing.docs.find((doc) => doc.id === d.id)?.data();
      const note = was
        ? was.price === d.price && was.name === d.name
          ? '(unchanged)'
          : `(was ${was.name} ${(was.price / 100).toFixed(2)} €)`
        : '(new)';
      console.log(
        `  ${d.id.padEnd(10)} ${d.name.padEnd(16)} ${(d.price / 100).toFixed(2).padStart(6)} €  ${note}`
      );
    });

    const retiring = existing.docs.filter(
      (doc) => !wanted.has(doc.id) && doc.data().isActive !== false
    );
    if (retiring.length) {
      console.log(`\nWould take ${retiring.length} off the menu (isActive: false, not deleted):\n`);
      retiring.forEach((doc) => console.log(`  ${doc.id.padEnd(10)} ${doc.data().name}`));
    }

    console.log(`\nDry run. Re-run with --apply to commit.\n`);
    return;
  }

  const { written, retired } = await seedDrinks(db, DEFAULT_DRINKS);
  console.log(`\n✔ ${written} drinks written, ${retired} taken off the menu.\n`);
}

async function cmdReset() {
  requireProject();
  requireKeyFile();

  const { initAdmin } = await cloud();
  const { planReset, isNoOp, checkConfirmation, summariseLedger, executeReset } = await import('./reset.mjs');

  const scope = option('scope', 'test-data');
  const deleteDrinks = flag('drinks');
  const app = initAdmin(config);
  const db = app.firestore();

  const [participantSnap, braceletSnap, ledgerSnap] = await Promise.all([
    db.collection('participants').get(),
    db.collection('bracelets').get(),
    db.collectionGroup('transactions').get(),
  ]);

  let plan;
  try {
    plan = planReset({
      participants: participantSnap.docs.map((d) => ({ id: d.id, data: d.data() })),
      braceletIds: braceletSnap.docs.map((d) => d.id),
      ledgerCount: ledgerSnap.size,
      scope,
    });
  } catch (error) {
    fail(error.message);
  }

  const money = summariseLedger(ledgerSnap.docs.map((d) => d.data()));
  const euro = (cents) => (cents / 100).toFixed(2) + ' €';

  console.log(`\nProject: ${config.projectId}    scope: ${plan.scope}`);
  console.log(`\nCurrently in the database:`);
  console.log(`  participants        ${participantSnap.size}`);
  console.log(`  paired bracelets    ${braceletSnap.size}`);
  console.log(`  ledger entries      ${money.count}`);
  if (money.count) {
    console.log(`    topped up         ${euro(money.topUps)}`);
    console.log(`    charged           ${euro(money.charges)}`);
    console.log(`    net on bracelets  ${euro(money.net)}`);
  }

  if (isNoOp(plan) && !deleteDrinks) {
    console.log(`\n✔ Already clean. Nothing to reset.\n`);
    return;
  }

  console.log(`\nWould:`);
  if (plan.deleteParticipants.length) {
    const what = plan.scope === 'all' ? 'participants (every one — re-import afterwards)' : 'door-sold evening tickets';
    console.log(`  delete ${plan.deleteParticipants.length} ${what}`);
  }
  if (plan.resetParticipants.length) {
    console.log(`  reset  ${plan.resetParticipants.length} imported participants to bracelet-less, 0 € balance`);
  }
  if (plan.braceletIds.length) console.log(`  delete ${plan.braceletIds.length} bracelet pairings`);
  if (money.count) console.log(`  delete ${money.count} ledger entries — permanently, append-only does not apply to the Admin SDK`);
  console.log(`  ${deleteDrinks ? 'delete the drinks menu too (--drinks)' : 'keep the drinks menu'}`);
  console.log(`  keep every staff account and role claim`);

  const refusal = checkConfirmation({ apply: config.apply, confirm: option('confirm'), projectId: config.projectId });
  if (refusal) fail(refusal);

  if (!config.apply) {
    console.log(`\nDry run. Nothing was deleted.\n`);
    console.log(`To go ahead:  npm run reset -- --apply --confirm=${config.projectId}\n`);
    return;
  }

  console.log(`\nDeleting…`);
  const counts = await executeReset(db, plan, { deleteDrinks });
  console.log(`\n✔ ${counts.participantsDeleted} participants deleted, ${counts.participantsReset} reset,`);
  console.log(`  ${counts.braceletsDeleted} bracelets deleted, ${counts.drinksDeleted} drinks deleted.`);
  console.log(`\n  Restart the terminals. FirebaseTerminalRepository caches the next`);
  console.log(`  evening-ticket number per run, and that cache now disagrees with the`);
  console.log(`  database.\n`);
}

function usage() {
  console.log(`
Swing Buzz roster importer

  npm run headers                                 print the Sheet's header row
  npm run import                                  dry run: show the diff
  npm run import -- --apply                       commit it
  npm run set-role -- <email> <reception|bar|admin>   dry run
  npm run set-role -- <email> <role> --apply      commit it
  npm run seed-drinks -- --apply                  write the menu's first three
  npm run reset                                   dry run: what a wipe would remove
  npm run reset -- --apply --confirm=<project>    WIPE the operational data
  npm test                                        unit-test the diff logic

Reset scopes (--scope=, default test-data):
  test-data   bracelets, ledger, balances, check-ins, door-sold evening tickets.
              The imported roster stays, so no re-import is needed.
  all         the above plus every participant document. Re-import afterwards.
  Add --drinks to wipe the menu too. Staff accounts are never touched.

Configuration, as flags or environment variables:
  --sheet=<id>       SHEET_ID                     from the Sheet URL
  --range=<a1>       SHEET_RANGE                  default A1:Z10000 (first tab)
  --project=<id>     FIREBASE_PROJECT_ID             defaults to ../.firebaserc
  --key=<path>       GOOGLE_APPLICATION_CREDENTIALS   default ./serviceAccountKey.json

Nothing is written without --apply.
`);
}

const commands = {
  headers: cmdHeaders,
  import: cmdImport,
  'set-role': cmdSetRole,
  'seed-drinks': cmdSeedDrinks,
  reset: cmdReset,
};

const run = commands[command];
if (!run) {
  usage();
  process.exit(command ? 1 : 0);
}

try {
  await run();
} catch (error) {
  fail(error.message ?? String(error));
}
