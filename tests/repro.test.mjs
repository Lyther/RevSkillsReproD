import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { INSTALLER, VENDOR, vendorReady } from '../src/repro.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

test('vendor pin contains the real upstream entry points', () => {
  assert.equal(vendorReady(), true);
  const pkg = JSON.parse(readFileSync(join(VENDOR, 'package.json'), 'utf8'));
  assert.equal(pkg.name, 'rev-skills');
  assert.equal(pkg.version, '0.0.5');
});

test('upstream validator accepts the pinned 121-skill tree', () => {
  const result = spawnSync(process.execPath, ['validate.mjs'], {
    cwd: VENDOR,
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /OK: 121 skills validated/);
});

test('installer writes Cursor rules into a project directory', () => {
  const dest = mkdtempSync(join(tmpdir(), 'rev-skills-repro-'));
  const result = spawnSync(
    process.execPath,
    [INSTALLER, '--project', '--target', 'cursor'],
    { cwd: dest, encoding: 'utf8' },
  );
  assert.equal(result.status, 0, result.stderr);
  const rule = join(dest, '.cursor', 'rules', 're-analyze.mdc');
  assert.equal(existsSync(rule), true);
  const body = readFileSync(rule, 'utf8');
  assert.match(body, /^---\n/);
  assert.match(body, /description:/);
  assert.equal(existsSync(join(ROOT, 'src', 'repro.mjs')), true);
});
