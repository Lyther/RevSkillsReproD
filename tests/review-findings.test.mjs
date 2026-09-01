import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const LIB = join(ROOT, 'scripts', 'lib', 'remote-dir.sh');
const BYTELLM_KEY = join(ROOT, 'scripts', 'lib', 'bytellm-key.sh');
const REMOTE_REPRO = join(ROOT, 'scripts', 'remote-repro.sh');
const PROVE_REMOTE = join(ROOT, 'scripts', 'verify-prove-remote.sh');
const PROVE_HARNESS = join(ROOT, 'scripts', 'verify-prove-rev-skills.mjs');
const REPRO = join(ROOT, 'src', 'repro.mjs');

function bash(script) {
  return spawnSync('bash', ['-c', script], { cwd: ROOT, encoding: 'utf8' });
}

test('tilde REMOTE_DIR expands to remote HOME before quoting', () => {
  const result = bash(`
    set -euo pipefail
    # shellcheck source=scripts/lib/remote-dir.sh
    source "${LIB}"
    expanded="$(remote_dir_expand_home '~/Projects/RevSkillsReproD' '/tmp/rev-home-expand')"
    quoted="$(remote_dir_quote "\${expanded}")"
    printf 'expanded=%s\\nquoted=%s\\n' "\${expanded}" "\${quoted}"
  `);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /expanded=\/tmp\/rev-home-expand\/Projects\/RevSkillsReproD/);
  assert.doesNotMatch(result.stdout, /quoted=\\~/);
  assert.doesNotMatch(result.stdout, /\/tmp\/rev-home-expand\/~/);
  const quoted = remoteReproUsesQuotedTilde();
  assert.equal(quoted, false, 'remote-repro must not ssh mkdir/cd a printf-quoted ~/ path');
});

function remoteReproUsesQuotedTilde() {
  const src = readFileSync(REMOTE_REPRO, 'utf8');
  return /remote_dir_quote "\$\{REMOTE_DIR\}"/.test(src) && !/remote_dir_expand_home/.test(src);
}

test('rev-skills-repro bin entry runs main', () => {
  const dest = mkdtempSync(join(tmpdir(), 'rev-skills-bin-'));
  const bin = join(dest, 'rev-skills-repro');
  symlinkSync(REPRO, bin);
  const result = spawnSync(process.execPath, [bin, 'not-a-cmd'], { encoding: 'utf8' });
  assert.equal(result.status, 2, result.stderr + result.stdout);
  assert.match(`${result.stdout}${result.stderr}`, /usage:/);
});

test('verify-prove-remote fail-closes captured proofs and honors REMOTE_DIR', () => {
  const src = readFileSync(PROVE_REMOTE, 'utf8');
  assert.doesNotMatch(src, /\/home\/lizhao\.1337\/Projects\/RevSkillsReproD/);
  assert.match(src, /REMOTE_DIR/);
  assert.match(src, /PROVE_RC/);
  assert.match(src, /cd -- "\$\{PROJECT_DIR\}"/);
  assert.match(src, /exit "\$\{fail\}"/);
});

test('test:repro stays image-safe without scripts/', () => {
  const pkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8'));
  const docker = readFileSync(join(ROOT, 'Dockerfile'), 'utf8');
  assert.match(pkg.scripts.test, /review-findings\.test\.mjs/);
  assert.doesNotMatch(pkg.scripts['test:repro'], /review-findings\.test\.mjs/);
  assert.match(docker, /npm run test:repro/);
  assert.doesNotMatch(docker, /COPY scripts/);
});

test('bytellm_read_key rejects non-numeric line numbers', () => {
  const dir = mkdtempSync(join(tmpdir(), 'bytellm-line-'));
  const keyFile = join(dir, 'bytellm');
  writeFileSync(keyFile, 'real-test-key\n');
  const inject = bash(`
    set -euo pipefail
    source "${BYTELLM_KEY}"
    bytellm_read_key "${keyFile}" '1s/.*/HACKED/'
    printf '\\nstatus=%s\\n' "\$?"
  `);
  assert.notEqual(inject.status, 0, `sed line_no must fail-close, got stdout=${inject.stdout}`);
  assert.doesNotMatch(inject.stdout, /HACKED/);
  const ok = bash(`
    set -uo pipefail
    source "${BYTELLM_KEY}"
    got="$(bytellm_read_key "${keyFile}" 1)"
    rc=\$?
    printf 'got=%s\\nrc=%s\\n' "\${got}" "\${rc}"
    exit "\${rc}"
  `);
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout, /got=real-test-key/);
  assert.match(ok.stdout, /rc=0/);
});

test('R-parallel-5 launches installer children concurrently', () => {
  const src = readFileSync(PROVE_HARNESS, 'utf8');
  const start = src.indexOf("const homes = Array.from({ length: 5 }");
  const end = src.indexOf('const empty = mkdtempSync');
  assert.ok(start >= 0 && end > start);
  const fn = src.slice(start, end);
  assert.match(fn, /spawnNode\(/);
  assert.doesNotMatch(fn, /\bspawnSync\(/);
  assert.match(fn, /Promise\.all/);
});
