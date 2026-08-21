// Copyright 2026 Alexandre Delisle
// SPDX-License-Identifier: MIT

'use strict';

/**
 * Documentation consistency checks.
 *
 * Run with `make docs-check` or `node docs/scripts/check-docs.js`.
 *
 * 1. Values parity: the value keys helm-docs writes into
 *    charts/github-sts/README.md match the tables in
 *    docs/content/{en,fr}/values.md.
 * 2. Resource parity: the template files under charts/github-sts/templates
 *    match the tables in docs/content/{en,fr}/resources.md.
 * 3. Translation parity: every English page has a French page with the same
 *    translationKey and weight, and vice versa.
 *
 * The chart README is the input for check 1 rather than values.yaml, because
 * helm-docs already resolves which keys are part of the documented surface:
 * a key carrying a `# --` annotation is public, an unannotated one is not.
 * Running helm-docs before this script — which is what the pre-commit hook and
 * the CI job both do — makes README.md a generated view of values.yaml, so
 * checking against it is checking against the chart.
 *
 * Names are checked, not prose, so the check stays robust while the wording
 * stays human-written.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const CHART = 'charts/github-sts';
const LANGS = ['en', 'fr'];

const failures = [];

function fail(message) {
  failures.push(message);
}

/**
 * Read a file the checks depend on. A missing file is a failure to report, not
 * a crash: a page deleted in one language should produce the same readable
 * output as a page whose table drifted.
 */
function read(relPath) {
  try {
    return fs.readFileSync(path.join(ROOT, relPath), 'utf8');
  } catch (err) {
    if (err.code !== 'ENOENT') throw err;
    fail(`${relPath}: file not found`);
    return '';
  }
}

/**
 * Extract the first column of every markdown table between
 * `<!-- name:begin -->` and `<!-- name:end -->`, skipping header and separator
 * rows. The region may hold several tables, so a reference page can group its
 * rows by concern and still be checked as one set. A table that documents
 * something other than the checked identifiers — the fields of a map value,
 * for instance — is skipped by wrapping it in `<!-- name:pause -->` and
 * `<!-- name:resume -->`.
 *
 * `backticked` is false for the helm-docs table, whose keys are bare, and true
 * for the hand-written tables, whose keys are code-formatted.
 */
function tableIdentifiers(source, marker, relPath, backticked = true) {
  const begin = source.indexOf(`<!-- ${marker}:begin -->`);
  const end = source.indexOf(`<!-- ${marker}:end -->`);
  if (begin === -1 || end === -1) {
    fail(`${relPath}: missing '${marker}' markers`);
    return [];
  }

  const names = [];
  let paused = false;
  let inBody = false;

  for (const line of source.slice(begin, end).split('\n')) {
    if (line.includes(`<!-- ${marker}:pause -->`)) {
      paused = true;
      continue;
    }
    if (line.includes(`<!-- ${marker}:resume -->`)) {
      paused = false;
      continue;
    }
    if (!line.startsWith('|')) {
      inBody = false; // anything but a table row ends the table
      continue;
    }
    if (paused) continue;
    // A |---|---| row opens the body of a table; rows above it are the header.
    if (/^\|[\s:|-]+\|$/.test(line)) {
      inBody = true;
      continue;
    }
    if (!inBody) continue;
    const cell = line.split('|')[1].trim();
    if (backticked) {
      const match = /^`([^`]+)`$/.exec(cell);
      if (match) names.push(match[1]);
    } else if (cell) {
      names.push(cell);
    }
  }

  if (names.length === 0) fail(`${relPath}: region '${marker}' has no identifiers`);
  return names;
}

function compare(label, expected, actual, relPath) {
  const missing = expected.filter((n) => !actual.includes(n));
  const extra = actual.filter((n) => !expected.includes(n));
  const duplicate = actual.filter((n, i) => actual.indexOf(n) !== i);
  if (missing.length) fail(`${relPath}: ${label} missing from the docs: ${missing.join(', ')}`);
  if (extra.length) fail(`${relPath}: ${label} documented but not in the chart: ${extra.join(', ')}`);
  if (duplicate.length) fail(`${relPath}: ${label} documented twice: ${[...new Set(duplicate)].join(', ')}`);
}

// --- 1. Values parity -------------------------------------------------------

const chartReadme = `${CHART}/README.md`;
const values = tableIdentifiers(read(chartReadme), 'values', chartReadme, false).sort();

for (const lang of LANGS) {
  const rel = `docs/content/${lang}/values.md`;
  compare('values', values, tableIdentifiers(read(rel), 'values', rel), rel);
}

// --- 2. Resource parity -----------------------------------------------------

/**
 * Every rendering template, as a path relative to the templates directory.
 * `.tpl` files hold named helpers and render nothing on their own, so only
 * `.yaml` files count as resources.
 */
function templates(dir = '', prefix = '') {
  const abs = path.join(ROOT, CHART, 'templates', dir);
  const found = [];
  for (const entry of fs.readdirSync(abs, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      found.push(...templates(path.join(dir, entry.name), `${prefix}${entry.name}/`));
    } else if (entry.name.endsWith('.yaml')) {
      found.push(`${prefix}${entry.name}`);
    }
  }
  return found;
}

const resources = templates().sort();

if (resources.length === 0) fail(`${CHART}/templates: no templates found`);

for (const lang of LANGS) {
  const rel = `docs/content/${lang}/resources.md`;
  compare('templates', resources, tableIdentifiers(read(rel), 'resources', rel), rel);
}

// --- 3. Translation parity --------------------------------------------------

function pages(lang) {
  const dir = path.join(ROOT, 'docs', 'content', lang);
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.md'))
    .sort();
}

function frontMatterField(source, field) {
  const match = new RegExp(`^${field}:\\s*(.+)$`, 'm').exec(source);
  return match ? match[1].trim() : null;
}

const en = pages('en');
const fr = pages('fr');

for (const file of en) {
  if (!fr.includes(file)) fail(`docs/content/fr/${file}: missing French page`);
}
for (const file of fr) {
  if (!en.includes(file)) fail(`docs/content/en/${file}: missing English page`);
}

for (const file of en.filter((f) => fr.includes(f))) {
  const enSource = read(`docs/content/en/${file}`);
  const frSource = read(`docs/content/fr/${file}`);

  for (const field of ['translationKey', 'weight']) {
    const a = frontMatterField(enSource, field);
    const b = frontMatterField(frSource, field);
    if (a === null) fail(`docs/content/en/${file}: missing '${field}' front matter`);
    if (b === null) fail(`docs/content/fr/${file}: missing '${field}' front matter`);
    if (a !== null && b !== null && a !== b) {
      fail(`docs/content/${file}: '${field}' differs between languages (en: ${a}, fr: ${b})`);
    }
  }

  for (const [lang, source] of [['en', enSource], ['fr', frSource]]) {
    for (const field of ['title', 'description']) {
      if (!frontMatterField(source, field)) {
        fail(`docs/content/${lang}/${file}: missing '${field}' front matter`);
      }
    }
  }
}

// --- Report -----------------------------------------------------------------

if (failures.length) {
  for (const message of failures) console.error(`error: ${message}`);
  console.error(`\n${failures.length} documentation check(s) failed.`);
  process.exit(1);
}

console.log(
  `Documentation checks passed: ${values.length} chart values, ` +
  `${resources.length} templates, ${en.length} pages per language.`
);
