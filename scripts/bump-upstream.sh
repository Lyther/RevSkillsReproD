#!/usr/bin/env bash
#
# bump-upstream.sh — move vendor/rev-skills to a remote ref.
#
# Usage: bump-upstream.sh [ref]
#   ref defaults to origin/HEAD
#
# Updates the working-tree pin only. Re-cut patches/ against the new pin
# before committing the gitlink so the overlay stays bisectable.
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

log() { printf '%s [%s] %s\n' "$(date -Iseconds)" "${SCRIPT_NAME}" "$*" >&2; }
die() {
    log "ERROR: $*"
    exit 1
}

usage() {
    cat >&2 <<EOF
Usage: ${SCRIPT_NAME} [ref]

Arguments:
  ref  Remote ref (default: origin/HEAD)
EOF
    exit 1
}

main() {
    local ref="${1:-}"
    case "${ref}" in
        -h | --help) usage ;;
    esac
    [[ -d "${VENDOR}/.git" || -f "${VENDOR}/.git" ]] || die "not a submodule: ${VENDOR}"

    log "fetching rev-skills"
    git -C "${VENDOR}" fetch --tags origin

    local target
    if [[ -z "${ref}" ]]; then
        target="origin/HEAD"
    elif git -C "${VENDOR}" rev-parse --verify --quiet "origin/${ref}" >/dev/null; then
        target="origin/${ref}"
    else
        target="${ref}"
    fi

    log "checking out rev-skills @ ${target} (detached pin)"
    git -C "${VENDOR}" checkout --detach "${target}"
    log "rev-skills now $(git -C "${VENDOR}" rev-parse --short HEAD)"
    git -C "${ROOT}" submodule status
    log "update pins/rev-skills.json (commit + treeHash) and the matching agent-surface external/rev-skills pin + registry commit before install:grimoire"
}

main "$@"
