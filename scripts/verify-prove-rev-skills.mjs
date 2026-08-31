#!/usr/bin/env node
// Clean-room prove harness for shipped rev-skills bits. Not a product substitute.
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

const ROOT = process.env.REV_SKILLS_ROOT;
if (!ROOT || !existsSync(join(ROOT, 'package.json'))) {
  console.error('REV_SKILLS_ROOT must point at an extracted rev-skills package');
  process.exit(2);
}

const INSTALLER = join(ROOT, 'bin', 'install.mjs');
const VALIDATOR = join(ROOT, 'validate.mjs');
const CONVERT = join(ROOT, 'bin', 'convert.mjs');
const WXSOURCE = join(ROOT, 'bin', 'wxsource.mjs');
const SKILLS = join(ROOT, '.claude', 'skills');
const findings = [];

function record(id, claim, verdict, evidence) {
  findings.push({ id, claim, verdict, evidence });
  console.log(`${verdict}\t${id}\t${claim}\t${evidence.replaceAll('\n', ' | ')}`);
}

function runNode(script, args, opts = {}) {
  return spawnSync(process.execPath, [script, ...args], {
    encoding: 'utf8',
    timeout: opts.timeout ?? 30000,
    cwd: opts.cwd ?? ROOT,
    env: { ...process.env, ...(opts.env ?? {}) },
    input: opts.input,
    stdio: opts.input === undefined ? ['ignore', 'pipe', 'pipe'] : ['pipe', 'pipe', 'pipe'],
  });
}

function parseFrontmatter(md) {
  const m = md.match(/^---\n([\s\S]*?)\n---\n*([\s\S]*)$/);
  if (!m) return { body: md };
  const fm = {};
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^(\w+):\s*(.*)$/);
    if (kv) fm[kv[1]] = kv[2];
  }
  return { ...fm, body: m[2] };
}

function listSkillDirs() {
  return readdirSync(SKILLS, { withFileTypes: true })
    .filter((e) => e.isDirectory() && e.name.startsWith('re-'))
    .map((e) => e.name)
    .sort();
}

function proveStructure() {
  const pkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8'));
  record('C-version', 'package name/version is rev-skills 0.0.5', pkg.name === 'rev-skills' && pkg.version === '0.0.5' ? 'PASS' : 'FAIL', `${pkg.name}@${pkg.version}`);

  const names = listSkillDirs();
  record('C-121', '121 skill directories', names.length === 121 ? 'PASS' : 'FAIL', `count=${names.length}`);

  const byType = { entry: [], gateway: [], atomic: [], other: [] };
  const missingPrep = [];
  const weakOs = [];
  const badName = [];
  const slashNames = [];
  for (const name of names) {
    if (name.includes('..') || name.includes('/') || name.includes('\\')) slashNames.push(name);
    const md = readFileSync(join(SKILLS, name, 'SKILL.md'), 'utf8');
    const fm = parseFrontmatter(md);
    if (fm.name !== name) badName.push(`${name}!=${fm.name}`);
    const type = fm.type ?? 'atomic';
    if (byType[type]) byType[type].push(name);
    else byType.other.push(`${name}:${type}`);
    if (type === 'atomic' && !md.includes('## 工具准备')) missingPrep.push(name);
    if (type === 'atomic') {
      const prep = md.split('## 工具准备')[1]?.split('## ')[0] ?? '';
      const hasUnix = /apt-get|apt |dnf |pacman |brew /.test(prep);
      const hasWin = /choco |winget |scoop |windows|WSL/i.test(prep);
      if (!hasUnix || !hasWin) weakOs.push(name);
    }
  }
  record('C-entry', 'exactly one entry skill re-analyze', byType.entry.length === 1 && byType.entry[0] === 're-analyze' ? 'PASS' : 'FAIL', `entry=${byType.entry.join(',')}`);
  const claimedGateways = [
    're-binary-core', 're-malware', 're-firmware', 're-protocol', 're-mobile',
    're-anti-analysis', 're-cracking', 're-vuln', 're-ctf', 're-managed',
    're-forensics', 're-feedback',
  ];
  const gwOk = claimedGateways.every((n) => byType.gateway.includes(n)) && byType.gateway.length === 12;
  record('C-12-gw', '12 claimed category gateways', gwOk ? 'PASS' : 'FAIL', `gateways=${byType.gateway.length} ${byType.gateway.join(',')}`);
  record('C-108-atomic', '108 atomic skills', byType.atomic.length === 108 ? 'PASS' : 'FAIL', `atomic=${byType.atomic.length} other=${byType.other.join(',')}`);
  record('C-tool-prep', 'every atomic has ## 工具准备', missingPrep.length === 0 ? 'PASS' : 'FAIL', `missing=${missingPrep.length} ${missingPrep.slice(0, 8).join(',')}`);
  record('C-cross-os', 'every atomic 工具准备 cites Unix and Windows/WSL install path', weakOs.length === 0 ? 'PASS' : 'FAIL', `weak=${weakOs.length} examples=${weakOs.slice(0, 8).join(',')}`);
  record('C-names', 'frontmatter name matches directory; no path-like skill names', badName.length === 0 && slashNames.length === 0 ? 'PASS' : 'FAIL', `badName=${badName.join(',')} slash=${slashNames.join(',')}`);

  const required = [
    join(SKILLS, 're-analyze', 'references', 'platform-tips.md'),
    join(SKILLS, 're-analyze', 'references', 'triage.md'),
    join(SKILLS, 're-analyze', 'references', 'capabilities.md'),
    join(SKILLS, 're-analyze', 'references', 'probe.sh'),
    join(ROOT, 'AGENTS.md'),
    join(ROOT, 'docs', 'skill-template.md'),
    join(ROOT, '.claude-plugin', 'marketplace.json'),
  ];
  const missingReq = required.filter((p) => !existsSync(p));
  record('C-refs', 'platform-tips/triage/capabilities/probe/AGENTS/template/marketplace exist', missingReq.length === 0 ? 'PASS' : 'FAIL', missingReq.join(','));

  const market = JSON.parse(readFileSync(join(ROOT, '.claude-plugin', 'marketplace.json'), 'utf8'));
  const mv = market.plugins?.[0]?.version;
  record('C-marketplace-ver', 'marketplace plugin version equals package 0.0.5', mv === pkg.version ? 'PASS' : 'FAIL', `marketplace=${mv} package=${pkg.version}`);

  const v = runNode(VALIDATOR, []);
  record('C-validate', 'validate.mjs accepts the shipped tree', v.status === 0 && /OK: 121 skills validated/.test(v.stdout) ? 'PASS' : 'FAIL', `status=${v.status} out=${v.stdout.trim()} err=${v.stderr.trim()}`);
}

function proveInstaller() {
  const proj = mkdtempSync(join(tmpdir(), 'rev-prove-proj-'));
  const dry = mkdtempSync(join(tmpdir(), 'rev-prove-dry-'));
  const home = mkdtempSync(join(tmpdir(), 'rev-prove-home-'));

  const dryRun = runNode(INSTALLER, ['--dry-run', '--project', '--target', 'all'], { cwd: dry });
  const dryWrote = existsSync(join(dry, '.claude')) || existsSync(join(dry, '.cursor')) || existsSync(join(dry, '.github'));
  record('I-dry-run', '--dry-run --project --target all writes no files', dryRun.status === 0 && !dryWrote ? 'PASS' : 'FAIL', `status=${dryRun.status} wrote=${dryWrote} err=${dryRun.stderr.trim()}`);

  const all = runNode(INSTALLER, ['--project', '--target', 'all'], { cwd: proj });
  const nativeCounts = {
    claude: existsSync(join(proj, '.claude', 'skills')) ? readdirSync(join(proj, '.claude', 'skills')).filter((n) => n.startsWith('re-')).length : 0,
    gemini: existsSync(join(proj, '.gemini', 'skills')) ? readdirSync(join(proj, '.gemini', 'skills')).filter((n) => n.startsWith('re-')).length : 0,
    codex: existsSync(join(proj, '.codex', 'skills')) ? readdirSync(join(proj, '.codex', 'skills')).filter((n) => n.startsWith('re-')).length : 0,
  };
  const cursorN = existsSync(join(proj, '.cursor', 'rules')) ? readdirSync(join(proj, '.cursor', 'rules')).filter((n) => n.endsWith('.mdc')).length : 0;
  const windN = existsSync(join(proj, '.windsurf', 'rules')) ? readdirSync(join(proj, '.windsurf', 'rules')).filter((n) => n.endsWith('.md')).length : 0;
  const copilot = join(proj, '.github', 'copilot-instructions.md');
  const copilotOk = existsSync(copilot) && readFileSync(copilot, 'utf8').includes('# 逆向工程技能库');
  const cursorSample = join(proj, '.cursor', 'rules', 're-analyze.mdc');
  const cursorHead = existsSync(cursorSample) ? readFileSync(cursorSample, 'utf8') : '';
  record('I-all-status', 'installer --target all --project exits 0', all.status === 0 ? 'PASS' : 'FAIL', `status=${all.status} err=${all.stderr.trim()}`);
  record('I-native-121', 'claude/gemini/codex each receive 121 native skills (cline shares .claude)', nativeCounts.claude === 121 && nativeCounts.gemini === 121 && nativeCounts.codex === 121 ? 'PASS' : 'FAIL', JSON.stringify(nativeCounts));
  record('I-cursor-121', 'cursor writes 121 .mdc with description frontmatter', cursorN === 121 && /^---\n/.test(cursorHead) && /description:/.test(cursorHead) ? 'PASS' : 'FAIL', `mdc=${cursorN} head_ok=${/^---\n/.test(cursorHead)}`);
  record('I-windsurf-121', 'windsurf writes 121 .md rules', windN === 121 ? 'PASS' : 'FAIL', `md=${windN}`);
  record('I-copilot', 'copilot writes aggregated .github/copilot-instructions.md', copilotOk ? 'PASS' : 'FAIL', `exists=${existsSync(copilot)} bytes=${existsSync(copilot) ? statSync(copilot).size : 0}`);

  const again = runNode(INSTALLER, ['--project', '--target', 'claude'], { cwd: proj });
  const skipped = (again.stdout + again.stderr).includes('SKIP');
  record('I-idempotent', 'reinstall without --force skips existing native skills', again.status === 0 && skipped ? 'PASS' : 'FAIL', `status=${again.status} skip=${skipped}`);

  const forced = runNode(INSTALLER, ['--project', '--target', 'claude', '--force'], { cwd: proj });
  record('I-force', '--force overwrite of native skills exits 0', forced.status === 0 ? 'PASS' : 'FAIL', `status=${forced.status} err=${forced.stderr.trim()}`);

  const glob = runNode(INSTALLER, ['--global', '--target', 'claude'], { cwd: proj, env: { HOME: home } });
  const gCount = existsSync(join(home, '.claude', 'skills')) ? readdirSync(join(home, '.claude', 'skills')).filter((n) => n.startsWith('re-')).length : 0;
  record('I-global', '--global writes ~/.claude/skills from HOME', glob.status === 0 && gCount === 121 ? 'PASS' : 'FAIL', `status=${glob.status} count=${gCount} dest=${join(home, '.claude', 'skills')}`);

  const un = runNode(INSTALLER, ['uninstall', '--project', '--target', 'claude'], { cwd: proj });
  const gone = !existsSync(join(proj, '.claude', 'skills', 're-analyze'));
  const cursorStill = existsSync(cursorSample);
  record('I-uninstall-native', 'uninstall --project --target claude removes native skills', un.status === 0 && gone ? 'PASS' : 'FAIL', `status=${un.status} gone=${gone}`);
  record('I-uninstall-rules-remain', 'native uninstall does not remove cursor rules', cursorStill ? 'PASS' : 'FAIL', `cursor_still=${cursorStill}`);

  const unRule = runNode(INSTALLER, ['uninstall', '--project', '--target', 'cursor'], { cwd: proj });
  record('I-uninstall-rule-msg', 'uninstall cursor tells user to remove converted rules manually', /remove .+ manually/.test(unRule.stdout) ? 'PASS' : 'FAIL', unRule.stdout.trim().slice(0, 200));

  const recover = runNode(INSTALLER, ['--project', '--target', 'claude'], { cwd: proj });
  record('I-recover', 'reinstall after uninstall restores re-analyze', recover.status === 0 && existsSync(join(proj, '.claude', 'skills', 're-analyze', 'SKILL.md')) ? 'PASS' : 'FAIL', `status=${recover.status}`);

  const unknown = runNode(INSTALLER, ['--project', '--target', 'not-a-tool'], { cwd: proj });
  record('F-unknown-target', 'unknown --target fails with actionable ERROR', unknown.status !== 0 && /unknown target/.test(unknown.stderr) ? 'PASS' : 'FAIL', `status=${unknown.status} err=${unknown.stderr.trim()}`);

  const clineG = runNode(INSTALLER, ['--global', '--target', 'cline'], { cwd: proj, env: { HOME: home } });
  record('F-cline-global', 'cline --global is skipped or errors honestly', clineG.status === 0 ? (/skip/.test(clineG.stdout + clineG.stderr) ? 'PASS' : 'FAIL') : (/does not support|仅支持/.test(clineG.stderr + clineG.stdout) ? 'PASS' : 'FAIL'), `status=${clineG.status} out=${(clineG.stdout + clineG.stderr).trim().slice(0, 180)}`);

  const conv = runNode(CONVERT, []);
  record('F-convert-usage', 'convert.mjs without args exits nonzero with usage', conv.status !== 0 && /usage:/.test(conv.stderr) ? 'PASS' : 'FAIL', `status=${conv.status} err=${conv.stderr.trim()}`);

  const hung = runNode(INSTALLER, ['--target', 'claude'], { cwd: proj, input: '', timeout: 4000 });
  record('F-interactive', 'missing --project/--global/--yes does not silently succeed', hung.status !== 0 || /global\/project/.test(hung.stdout) ? 'PASS' : 'FAIL', `status=${hung.status} signal=${hung.signal} out=${hung.stdout.trim().slice(0, 120)}`);

  rmSync(proj, { recursive: true, force: true });
  rmSync(dry, { recursive: true, force: true });
  rmSync(home, { recursive: true, force: true });
}

function proveRobustness() {
  const homes = Array.from({ length: 5 }, () => mkdtempSync(join(tmpdir(), 'rev-prove-par-')));
  const procs = homes.map((cwd) => {
    const child = spawnSync(process.execPath, [INSTALLER, '--project', '--target', 'cursor'], {
      encoding: 'utf8',
      timeout: 30000,
      cwd,
    });
    return { cwd, status: child.status, n: existsSync(join(cwd, '.cursor', 'rules')) ? readdirSync(join(cwd, '.cursor', 'rules')).filter((f) => f.endsWith('.mdc')).length : 0 };
  });
  const allOk = procs.every((p) => p.status === 0 && p.n === 121);
  record('R-parallel-5', '5 parallel cursor installs each write 121 rules', allOk ? 'PASS' : 'FAIL', JSON.stringify(procs.map((p) => ({ status: p.status, n: p.n }))));
  for (const cwd of homes) rmSync(cwd, { recursive: true, force: true });

  const empty = mkdtempSync(join(tmpdir(), 'rev-prove-empty-'));
  writeFileSync(join(empty, 'validate.mjs'), readFileSync(VALIDATOR));
  const missing = spawnSync(process.execPath, [join(empty, 'validate.mjs')], { encoding: 'utf8', cwd: empty, timeout: 10000 });
  record('R-validate-missing', 'validator against missing skills dir fails honestly', missing.status !== 0 && /skills dir not found/.test(missing.stderr) ? 'PASS' : 'FAIL', `status=${missing.status} err=${missing.stderr.trim()}`);
  rmSync(empty, { recursive: true, force: true });
}

function proveAdversary() {
  const names = listSkillDirs();
  record('A-no-dotdot-skills', 'no skill directory name is a path escape', names.every((n) => !n.includes('..') && !n.includes('/') && !n.includes('\\')) ? 'PASS' : 'FAIL', names.filter((n) => n.includes('..') || n.includes('/')).join(','));

  const outside = mkdtempSync(join(tmpdir(), 'rev-prove-outside-'));
  const proj = mkdtempSync(join(tmpdir(), 'rev-prove-symlink-'));
  mkdirSync(join(proj, '.claude'));
  rmSync(join(proj, '.claude'), { recursive: true, force: true });
  symlinkSync(outside, join(proj, '.claude'));
  const linked = runNode(INSTALLER, ['--project', '--target', 'claude'], { cwd: proj });
  const escaped = existsSync(join(outside, 'skills', 're-analyze', 'SKILL.md'));
  record('A-symlink-dest', 'installer follows cwd symlink into attacker-chosen dest (must be documented or refused)', escaped ? 'FAIL' : 'PASS', `status=${linked.status} wrote_outside=${escaped} dest=${outside}`);
  rmSync(proj, { recursive: true, force: true });
  rmSync(outside, { recursive: true, force: true });

  const home = mkdtempSync(join(tmpdir(), 'rev-prove-homeesc-'));
  const weirdHome = join(home, 'a', '..', 'escaped');
  mkdirSync(weirdHome, { recursive: true });
  const glob = runNode(INSTALLER, ['--global', '--target', 'claude'], { cwd: mkdtempSync(join(tmpdir(), 'rev-prove-cwd-')), env: { HOME: weirdHome } });
  const resolved = resolve(weirdHome, '.claude', 'skills', 're-analyze', 'SKILL.md');
  const wroteResolved = existsSync(resolved);
  const wroteLiteralDots = existsSync(join(home, 'a', '..', 'escaped', '.claude', 'skills', 're-analyze', 'SKILL.md'));
  record('A-home-dotdot', 'HOME with .. writes only under resolved HOME, not arbitrary FS roots', glob.status === 0 && wroteResolved && resolved.startsWith(resolve(home)) ? 'PASS' : 'FAIL', `status=${glob.status} resolved=${resolved} exists=${wroteResolved} literal=${wroteLiteralDots}`);
  rmSync(home, { recursive: true, force: true });

  const sibling = mkdtempSync(join(tmpdir(), 'rev-prove-sib-'));
  writeFileSync(join(sibling, 'KEEP.txt'), 'keep');
  mkdirSync(join(sibling, '.claude', 'skills'), { recursive: true });
  const inst = runNode(INSTALLER, ['--project', '--target', 'claude'], { cwd: sibling });
  const un = runNode(INSTALLER, ['uninstall', '--project', '--target', 'claude'], { cwd: sibling });
  record('A-uninstall-scope', 'uninstall does not delete sibling KEEP.txt', inst.status === 0 && un.status === 0 && existsSync(join(sibling, 'KEEP.txt')) && readFileSync(join(sibling, 'KEEP.txt'), 'utf8') === 'keep' ? 'PASS' : 'FAIL', `keep=${existsSync(join(sibling, 'KEEP.txt'))}`);
  rmSync(sibling, { recursive: true, force: true });

  const guardSkills = [];
  for (const name of names) {
    const md = readFileSync(join(SKILLS, name, 'SKILL.md'), 'utf8');
    const fm = parseFrontmatter(md);
    if (fm.guard !== undefined) guardSkills.push(name);
  }
  const cracking = readFileSync(join(SKILLS, 're-cracking', 'SKILL.md'), 'utf8');
  record('A-cracking-boundary', 're-cracking documents unauthorized-use prohibition', /禁止/.test(cracking) && /未授权/.test(cracking) ? 'PASS' : 'FAIL', `guard_frontmatter_skills=${guardSkills.length}:${guardSkills.join(',')}`);
}

function proveWxsource() {
  if (!existsSync(WXSOURCE)) {
    record('W-present', 'wxsource.mjs ships in the package', 'FAIL', 'missing');
    return;
  }
  record('W-present', 'wxsource.mjs ships in the package', 'PASS', WXSOURCE);
  const help = runNode(WXSOURCE, []);
  record('W-help', 'wxsource without args prints usage', /kanxue|用法/.test(help.stdout + help.stderr) ? 'PASS' : 'FAIL', `status=${help.status}`);
}

function main() {
  console.log(`PROVE_ROOT=${ROOT}`);
  proveStructure();
  proveInstaller();
  proveRobustness();
  proveAdversary();
  proveWxsource();
  const pass = findings.filter((f) => f.verdict === 'PASS').length;
  const fail = findings.filter((f) => f.verdict === 'FAIL').length;
  const blocked = findings.filter((f) => f.verdict === 'BLOCKED').length;
  const summary = { pass, fail, blocked, total: findings.length, findings };
  const out = process.env.PROVE_JSON;
  if (out) {
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, JSON.stringify(summary, null, 2));
  }
  console.log(`SUMMARY pass=${pass} fail=${fail} blocked=${blocked} total=${findings.length}`);
  if (fail > 0) process.exit(1);
}

main();
