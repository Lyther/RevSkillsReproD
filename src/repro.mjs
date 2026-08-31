#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const VENDOR = join(ROOT, 'vendor', 'rev-skills');
export const INSTALLER = join(VENDOR, 'bin', 'install.mjs');

export function vendorReady() {
  return existsSync(join(VENDOR, 'validate.mjs')) && existsSync(INSTALLER);
}

function runNode(script, args, cwd) {
  const result = spawnSync(process.execPath, [script, ...args], {
    cwd,
    stdio: 'inherit',
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function runNpmTest() {
  const result = spawnSync('npm', ['test'], {
    cwd: VENDOR,
    stdio: 'inherit',
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function requireVendor() {
  if (vendorReady()) {
    return;
  }
  console.error('vendor/rev-skills is missing. Run: git submodule update --init --recursive');
  process.exit(1);
}

export function check() {
  requireVendor();
  runNpmTest();
  runNode(INSTALLER, ['--dry-run', '--project', '--target', 'all'], VENDOR);
  console.log('repro check: OK');
}

export function install(destRoot = ROOT) {
  requireVendor();
  runNode(INSTALLER, ['--project', '--target', 'cursor'], destRoot);
  console.log(`repro install: Cursor rules → ${join(destRoot, '.cursor', 'rules')}`);
}

function main() {
  const cmd = process.argv[2] ?? 'check';
  if (cmd === 'check') {
    check();
    return;
  }
  if (cmd === 'install') {
    check();
    install();
    return;
  }
  console.error('usage: node src/repro.mjs [check|install]');
  process.exit(2);
}

if (process.argv[1] && process.argv[1].endsWith('repro.mjs')) {
  main();
}
