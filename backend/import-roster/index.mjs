#!/usr/bin/env node
// CLI for the roster importer. See README.md.
//
// Writing is opt-in: every command that changes Firestore requires --apply.
// Without it you get a diff and nothing else.

import { buildPlan, findOrphans, parseRows, resolveColumns, validateIdentity } from './diff.mjs';
import { IDENTITY_COLUMN } from './mapping.mjs';
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

const config = {
  keyFile: option('key', process.env.GOOGLE_APPLICATION_CREDENTIALS ?? './serviceAccountKey.json'),
  projectId: option('project', process.env.FIREBASE_PROJECT_ID),
  spreadsheetId: option('sheet', process.env.SHEET_ID),
  range: option('range', process.env.SHEET_RANGE ?? 'Participants!A1:Z10000'),
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
  if (!config.projectId) fail('No Firebase project id. Pass --project=<id> or set FIREBASE_PROJECT_ID.');
}

// ── commands ───────────────────────────────────────────────────────────────

async function cmdHeaders() {
  requireSheet();
  const { readSheet } = await cloud();
  const { header, rows } = await readSheet(config);
  console.log(`\nSheet "${config.range}" — ${rows.length} populated data rows.\n`);
  console.log('Header row:\n');
  header.forEach((h, i) => console.log(`  [${String(i).padStart(2)}]  ${h}`));
  console.log(`\nPut these column names into mapping.mjs, then run: npm run import\n`);
}

async function cmdImport() {
  requireSheet();
  requireProject();

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

  const app = initAdmin(config);
  const db = app.firestore();
  const existing = await fetchParticipants(db);
  console.log(`Firestore:  ${existing.size} participants already present\n`);

  const plan = buildPlan(usable, existing);
  const orphans = findOrphans(usable, existing);

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
  if (!email || !role) fail('Usage: npm run set-role -- <email> <reception|bar> --apply');

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
  const { initAdmin, seedDrinks, DEFAULT_DRINKS } = await cloud();
  const app = initAdmin(config);
  if (!config.apply) {
    console.log(`\nWould write ${DEFAULT_DRINKS.length} drinks:\n`);
    DEFAULT_DRINKS.forEach((d) =>
      console.log(`  ${d.id.padEnd(10)} ${d.name.padEnd(16)} ${(d.price / 100).toFixed(2)} €`)
    );
    console.log(`\nDry run. Re-run with --apply to commit.\n`);
    return;
  }
  const count = await seedDrinks(app.firestore(), DEFAULT_DRINKS);
  console.log(`\n✔ ${count} drinks written.\n`);
}

function usage() {
  console.log(`
Swing Buzz roster importer

  npm run headers                                 print the Sheet's header row
  npm run import                                  dry run: show the diff
  npm run import -- --apply                       commit it
  npm run set-role -- <email> <reception|bar>      dry run
  npm run set-role -- <email> <role> --apply      commit it
  npm run seed-drinks -- --apply                  write the drinks menu
  npm test                                        unit-test the diff logic

Configuration, as flags or environment variables:
  --sheet=<id>       SHEET_ID                     from the Sheet URL
  --range=<a1>       SHEET_RANGE                  default Participants!A1:Z10000
  --project=<id>     FIREBASE_PROJECT_ID
  --key=<path>       GOOGLE_APPLICATION_CREDENTIALS   default ./serviceAccountKey.json

Nothing is written without --apply.
`);
}

const commands = {
  headers: cmdHeaders,
  import: cmdImport,
  'set-role': cmdSetRole,
  'seed-drinks': cmdSeedDrinks,
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
