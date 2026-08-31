import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, lstatSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { VENDOR, vendorReady } from '../src/repro.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const APPLY = join(ROOT, 'scripts', 'apply-overlay.sh');
const OUT = join(ROOT, 'dist', 'rev-skills');
const SENSITIVE = ['re-cracking', 're-keygen', 're-exploit'];

function skillMd(root, name) {
  return join(root, '.claude', 'skills', name, 'SKILL.md');
}

function hasGuard(text) {
  return /^guard:\s*\{/m.test(text);
}

test('series patches do not use absolute or traversal dest paths', () => {
  const series = readFileSync(join(ROOT, 'patches', 'series'), 'utf8')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'));
  assert.ok(series.length > 0);
  for (const name of series) {
    assert.equal(name.includes('..'), false, name);
    const text = readFileSync(join(ROOT, 'patches', name), 'utf8');
    for (const line of text.split('\n')) {
      if (!/^(---|\+\+\+)\s/.test(line)) continue;
      assert.equal(/^(---|\+\+\+)\s+\//.test(line), false, line);
      assert.equal(/(^|\/)\.\.(\/|$)/.test(line), false, line);
    }
  }
});

test('vendor pin stays clean of overlay guards', () => {
  assert.equal(vendorReady(), true);
  for (const name of SENSITIVE) {
    const body = readFileSync(skillMd(VENDOR, name), 'utf8');
    assert.equal(hasGuard(body), false, `${name} must not carry overlay guards in vendor/`);
  }
});

test('apply-overlay writes 121 skills with sensitive-skill guards and leaves vendor clean', () => {
  const apply = spawnSync('bash', [APPLY], { cwd: ROOT, encoding: 'utf8' });
  assert.equal(apply.status, 0, apply.stderr);
  assert.match(apply.stderr, /overlay ready/);

  const skillsDir = join(OUT, '.claude', 'skills');
  const names = readdirSync(skillsDir, { withFileTypes: true })
    .filter((e) => e.isDirectory() && e.name.startsWith('re-'))
    .map((e) => e.name);
  assert.equal(names.length, 121);

  const validate = spawnSync(process.execPath, ['validate.mjs'], {
    cwd: OUT,
    encoding: 'utf8',
  });
  assert.equal(validate.status, 0, validate.stderr);
  assert.match(validate.stdout, /OK: 121 skills validated/);

  for (const name of SENSITIVE) {
    const body = readFileSync(skillMd(OUT, name), 'utf8');
    assert.equal(hasGuard(body), true, `${name} overlay must add guard`);
    assert.match(body, /"require_authorization": true/);
  }

  const link = lstatSync(join(OUT, 'skills'));
  assert.equal(link.isSymbolicLink(), true);
  assert.equal(existsSync(join(OUT, 'skills', 're-analyze', 'SKILL.md')), true);

  const base = readFileSync(join(OUT, '.overlay-base'), 'utf8').trim();
  const tree = readFileSync(join(OUT, '.overlay-tree'), 'utf8').trim();
  const pin = JSON.parse(readFileSync(join(ROOT, 'pins', 'rev-skills.json'), 'utf8'));
  assert.equal(base, pin.commit);
  assert.equal(tree, pin.treeHash);
  assert.match(pin.treeHash, /^[0-9a-f]{64}$/);

  const vendorHead = spawnSync('git', ['-C', VENDOR, 'rev-parse', 'HEAD'], { encoding: 'utf8' });
  if (vendorHead.status === 0) {
    assert.equal(vendorHead.stdout.trim(), pin.commit);
    const dirty = spawnSync('git', ['-C', VENDOR, 'status', '--porcelain'], { encoding: 'utf8' });
    assert.equal(dirty.status, 0, dirty.stderr);
    assert.equal(dirty.stdout, '', 'vendor/rev-skills must stay a clean pin');
  }
});
