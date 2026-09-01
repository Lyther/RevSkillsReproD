#!/usr/bin/env bash
#
# apply-overlay.sh — copy the pinned vendor tree and apply patches/series.
#
# Usage: apply-overlay.sh
# Writes dist/rev-skills. Never mutates vendor/rev-skills.
# This is a proposed-upstream quilt. Grimoire indexes the clean
# agent-surface pin, not this overlay output.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
VENDOR="${ROOT}/vendor/rev-skills"
readonly VENDOR
OUT="${ROOT}/dist/rev-skills"
readonly OUT
SERIES="${ROOT}/patches/series"
readonly SERIES
SKILLS_REL=".claude/skills"
readonly SKILLS_REL

log() { printf '%s [%s] %s\n' "$(date -Iseconds)" "${SCRIPT_NAME}" "$*" >&2; }
die() {
    log "ERROR: $*"
    exit 1
}

tree_hash() {
    local skills_root="$1"
    SKILLS_ROOT="${skills_root}" node --input-type=module -e '
import { createHash } from "node:crypto";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
const root = process.env.SKILLS_ROOT ?? "";
if (!root) process.exit(2);
function walk(dir, acc) {
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, acc);
    else if (st.isFile()) {
      acc.push(`${p.slice(root.length + 1)}:${createHash("sha256").update(readFileSync(p)).digest("hex")}`);
    }
  }
}
const acc = [];
walk(root, acc);
process.stdout.write(createHash("sha256").update(acc.join("\n")).digest("hex"));
'
}

read_pin() {
    local pin_file="$1" field="$2"
    PIN_FILE="${pin_file}" PIN_FIELD="${field}" node --input-type=module -e '
import { readFileSync } from "node:fs";
const p = JSON.parse(readFileSync(process.env.PIN_FILE ?? "", "utf8"));
const field = process.env.PIN_FIELD ?? "";
const value = p[field];
if (typeof value !== "string" || !/^[0-9a-f]{40,64}$/.test(value)) process.exit(2);
process.stdout.write(value);
'
}

main() {
    [[ -f "${VENDOR}/validate.mjs" ]] || die "vendor/rev-skills is missing; run git submodule update --init --recursive"
    [[ -d "${VENDOR}/${SKILLS_REL}" ]] || die "missing ${VENDOR}/${SKILLS_REL}"
    [[ -f "${SERIES}" ]] || die "missing ${SERIES}"
    command -v git >/dev/null 2>&1 || die "git is required to apply the overlay series"
    command -v rsync >/dev/null 2>&1 || die "rsync is required"

    local pin_file base expected_hash actual_hash vendor_head dirty
    pin_file="${ROOT}/pins/rev-skills.json"
    [[ -f "${pin_file}" ]] || die "missing ${pin_file}"
    base="$(read_pin "${pin_file}" commit)" || die "pins/rev-skills.json commit must be 40-hex"
    expected_hash="$(read_pin "${pin_file}" treeHash)" || die "pins/rev-skills.json treeHash must be hex"
    actual_hash="$(tree_hash "${VENDOR}/${SKILLS_REL}")" || die "cannot hash vendor skills tree"
    [[ "${actual_hash}" == "${expected_hash}" ]] || die "vendor ${SKILLS_REL} treeHash ${actual_hash} != pin ${expected_hash}"

    if vendor_head="$(git -C "${VENDOR}" rev-parse HEAD 2>/dev/null)"; then
        [[ "${vendor_head}" == "${base}" ]] || die "vendor HEAD ${vendor_head} != pin ${base}; bump the pin file or checkout the pin"
        dirty="$(git -C "${VENDOR}" status --porcelain)" || die "git status failed"
        [[ -z "${dirty}" ]] || die "vendor/rev-skills is dirty; refuse to copy a dirty pin"
    fi

    rm -rf "${OUT}"
    mkdir -p "${OUT}"
    rsync -a --delete --exclude '.git/' --exclude '.git' "${VENDOR}/" "${OUT}/"

    local patch_name patch_file
    while IFS= read -r patch_name || [[ -n "${patch_name}" ]]; do
        [[ -z "${patch_name}" || "${patch_name}" == \#* ]] && continue
        [[ "${patch_name}" == *..* ]] && die "series path escapes patches/: ${patch_name}"
        patch_file="${ROOT}/patches/${patch_name}"
        [[ -f "${patch_file}" ]] || die "series names missing patch: ${patch_name}"
        if grep -E '^(---|\+\+\+)[[:space:]]+/' -- "${patch_file}" >/dev/null; then
            die "patch ${patch_name} contains an absolute path"
        fi
        if grep -E '^(---|\+\+\+)[[:space:]].*(^|/)\.\.(/|$)' -- "${patch_file}" >/dev/null; then
            die "patch ${patch_name} contains a path traversal"
        fi
        log "applying ${patch_name}"
        git -C "${ROOT}" apply --directory=dist/rev-skills -- "${patch_file}" || die "git apply failed: ${patch_name}"
    done < "${SERIES}"

    if [[ ! -e "${OUT}/skills" && -d "${OUT}/.claude/skills" ]]; then
        ln -s .claude/skills "${OUT}/skills"
    fi

    printf '%s\n' "${base}" > "${OUT}/.overlay-base"
    printf '%s\n' "${actual_hash}" > "${OUT}/.overlay-tree"
    log "overlay ready at ${OUT} (base ${base})"
}

main "$@"
