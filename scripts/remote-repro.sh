#!/usr/bin/env bash
#
# remote-repro.sh — rsync this tree to a dev box and run the Docker repro.
#
# Usage: remote-repro.sh
# Env: DEPLOY_HOST (default dev-box-cpu), REMOTE_DIR (default ~/Projects/RevSkillsReproD)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
HOST="${DEPLOY_HOST:-dev-box-cpu}"
REMOTE_DIR="${REMOTE_DIR:-~/Projects/RevSkillsReproD}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/remote-dir.sh"
PROXY='export http_proxy=http://sys-proxy-rd-relay.byted.org:8118 https_proxy=http://sys-proxy-rd-relay.byted.org:8118 HTTP_PROXY=http://sys-proxy-rd-relay.byted.org:8118 HTTPS_PROXY=http://sys-proxy-rd-relay.byted.org:8118 no_proxy="127.0.0.1,localhost,10.37.89.91,10.37.89.184,10.199.47.35,10.199.47.55.byted.org,.volces.com,.bytedance.net" NO_PROXY="127.0.0.1,localhost,10.37.89.91,10.37.89.184,10.199.47.35,10.199.47.55.byted.org,.volces.com,.bytedance.net"'

log() { printf '%s [%s] %s\n' "$(date -Iseconds)" "${SCRIPT_NAME}" "$*" >&2; }
die() {
    log "ERROR: $*"
    exit 1
}

main() {
    command -v ssh >/dev/null 2>&1 || die "ssh is required"
    command -v rsync >/dev/null 2>&1 || die "rsync is required"
    remote_host_ok "${HOST}" || die "DEPLOY_HOST has unsafe characters"
    remote_dir_ok "${REMOTE_DIR}" || die "REMOTE_DIR has unsafe characters"
    local remote_home remote_q
    remote_home="$(ssh -o BatchMode=yes "${HOST}" 'printf %s "$HOME"')" || die "cannot read remote HOME"
    [[ -n "${remote_home}" ]] || die "remote HOME is empty"
    REMOTE_DIR="$(remote_dir_expand_home "${REMOTE_DIR}" "${remote_home}")" || die "cannot expand REMOTE_DIR"
    remote_dir_ok "${REMOTE_DIR}" || die "expanded REMOTE_DIR has unsafe characters"
    remote_q="$(remote_dir_quote "${REMOTE_DIR}")"

    log "deploying ${ROOT} -> ${HOST}:${REMOTE_DIR}"
    ssh -o BatchMode=yes "${HOST}" "mkdir -p -- ${remote_q}"

    if [[ -f "${HOME}/.ssh/bytellm" ]]; then
        ssh -o BatchMode=yes "${HOST}" 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
        rsync -az "${HOME}/.ssh/bytellm" "${HOST}:~/.ssh/bytellm"
        ssh -o BatchMode=yes "${HOST}" 'chmod 600 ~/.ssh/bytellm'
    fi

    rsync -az --delete \
        --exclude '.git/' \
        --exclude 'vendor/rev-skills/.git' \
        --exclude 'node_modules/' \
        --exclude '.DS_Store' \
        --exclude '.env' \
        --exclude '.cursor/' \
        "${ROOT}/" "${HOST}:${REMOTE_DIR}/"

    ssh -o BatchMode=yes "${HOST}" "set -euo pipefail
${PROXY}
export DOCKER_BUILDKIT=1
cd -- ${remote_q}
chmod +x scripts/*.sh
test -f .env || cp .env.example .env
npm run test:overlay
make test
make up
docker compose exec -T app node vendor/rev-skills/validate.mjs
if [[ -f ~/.ssh/bytellm ]]; then
  BYTELLM_KEY_FILE=\${HOME}/.ssh/bytellm BYTELLM_KEY_LINE=11 ./scripts/probe-llm.sh
  BYTELLM_KEY_FILE=\${HOME}/.ssh/bytellm BYTELLM_KEY_LINE=11 BYTELLM_MODEL=qwen3-max ./scripts/live-skill.sh
else
  echo 'ByteLLM probe skipped: no ~/.ssh/bytellm' >&2
fi
"
}

main "$@"
