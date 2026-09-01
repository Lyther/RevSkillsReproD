#!/usr/bin/env bash
#
# verify-prove-remote.sh — clean-room prove of published rev-skills@0.0.5 on a remote host.
# Product under test is the npm tarball, not this checkout. Never prints keys.
#
# Usage: verify-prove-remote.sh
# Env: DEPLOY_HOST (default dev-box-cpu), REMOTE_DIR (default ~/Projects/RevSkillsReproD)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
HOST="${DEPLOY_HOST:-dev-box-cpu}"
REMOTE_DIR="${REMOTE_DIR:-~/Projects/RevSkillsReproD}"
REMOTE_WORK="${REMOTE_WORK:-/tmp/revskills-prove-room}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/remote-dir.sh"

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
    remote_dir_ok "${REMOTE_WORK}" || die "REMOTE_WORK has unsafe characters"
    local remote_home
    remote_home="$(ssh -o BatchMode=yes "${HOST}" 'printf %s "$HOME"')" || die "cannot read remote HOME"
    [[ -n "${remote_home}" ]] || die "remote HOME is empty"
    REMOTE_DIR="$(remote_dir_expand_home "${REMOTE_DIR}" "${remote_home}")" || die "cannot expand REMOTE_DIR"
    remote_dir_ok "${REMOTE_DIR}" || die "expanded REMOTE_DIR has unsafe characters"

    ssh -o BatchMode=yes "${HOST}" "mkdir -p -- ${REMOTE_WORK}/harness ${REMOTE_WORK}/out"
    rsync -az "${SCRIPT_DIR}/verify-prove-rev-skills.mjs" "${HOST}:${REMOTE_WORK}/harness/verify-prove-rev-skills.mjs"
    rsync -az "${SCRIPT_DIR}/verify-prove-llm.sh" "${HOST}:${REMOTE_WORK}/harness/verify-prove-llm.sh"
    rsync -az "${SCRIPT_DIR}/lib/bytellm-key.sh" "${HOST}:${REMOTE_WORK}/harness/bytellm-key.sh"
    if [[ -f "${HOME}/.ssh/bytellm" ]]; then
        rsync -az "${HOME}/.ssh/bytellm" "${HOST}:~/.ssh/bytellm"
        ssh -o BatchMode=yes "${HOST}" 'chmod 600 ~/.ssh/bytellm'
    fi

    # Quoted heredoc so the remote script is literal; WORK/PROJECT_DIR come from env.
    ssh -o BatchMode=yes "${HOST}" \
        env WORK="${REMOTE_WORK}" PROJECT_DIR="${REMOTE_DIR}" \
        bash -s <<'REMOTE'
set -euo pipefail
export http_proxy=http://sys-proxy-rd-relay.byted.org:8118
export https_proxy=http://sys-proxy-rd-relay.byted.org:8118
export HTTP_PROXY=http://sys-proxy-rd-relay.byted.org:8118
export HTTPS_PROXY=http://sys-proxy-rd-relay.byted.org:8118
export no_proxy="127.0.0.1,localhost,10.37.89.91,10.37.89.184,10.199.47.35,10.199.47.55.byted.org,.volces.com,.bytedance.net"
export NO_PROXY="127.0.0.1,localhost,10.37.89.91,10.37.89.184,10.199.47.35,10.199.47.55.byted.org,.volces.com,.bytedance.net"
export DOCKER_BUILDKIT=1
: "${WORK:?WORK required}"
: "${PROJECT_DIR:?PROJECT_DIR required}"
rm -rf -- "${WORK}/npm" "${WORK}/extract" "${WORK}/user"
mkdir -p -- "${WORK}/npm" "${WORK}/extract" "${WORK}/user" "${WORK}/out"
printf 'ignore-scripts=true\n' > "${WORK}/npm/.npmrc"
cd "${WORK}/npm"
npm --userconfig "${WORK}/npm/.npmrc" pack rev-skills@0.0.5
test -f rev-skills-0.0.5.tgz
SHA=$(sha1sum rev-skills-0.0.5.tgz | awk '{print $1}')
echo "tarball_sha1=${SHA}"
if [[ "${SHA}" != 'dc9be1e36f4e338d5b64b1818b057a9a49661c8b' ]]; then
  echo 'TARBALL_SHA_MISMATCH' >&2
  exit 1
fi
openssl dgst -sha512 -binary rev-skills-0.0.5.tgz | openssl base64 -A > "${WORK}/out/tarball.sha512b64"
mkdir -p "${WORK}/extract"
tar -xzf rev-skills-0.0.5.tgz -C "${WORK}/extract"
test -f "${WORK}/extract/package/package.json"
( cd "${WORK}/extract/package" && find . -type f ! -path './.git/*' | sort | xargs sha256sum ) > "${WORK}/out/npm-tree.sha256"
docker inspect --format '{{.Id}}' revskillsrepro-app:0.0.5 > "${WORK}/out/image.id"
docker run --rm --user node --entrypoint '' "$(cat "${WORK}/out/image.id")" \
  node -e 'const {execSync}=require("node:child_process"); process.stdout.write(execSync("sha256sum /app/vendor/rev-skills/package.json").toString())' \
  > "${WORK}/out/image-pkg.sha256"
sha256sum "${WORK}/extract/package/package.json" > "${WORK}/out/npm-pkg.sha256"
export REV_SKILLS_ROOT="${WORK}/extract/package"
export PROVE_JSON="${WORK}/out/prove.json"
set +e
node "${WORK}/harness/verify-prove-rev-skills.mjs" | tee "${WORK}/out/prove.log"
PROVE_RC=$?
set -e
echo "prove_rc=${PROVE_RC}"
# Real user entry: npx published bin into a fresh directory
cd "${WORK}/user"
set +e
export npm_config_userconfig="${WORK}/npm/.npmrc"
npx --yes rev-skills@0.0.5 install --dry-run --project --target all > "${WORK}/out/npx-dry.log" 2>&1
NPX_DRY=$?
npx --yes rev-skills@0.0.5 install --project --target cursor > "${WORK}/out/npx-cursor.log" 2>&1
NPX_CUR=$?
npx --yes skills add dslsdzc/rev-skills -l > "${WORK}/out/skills-list.log" 2>&1
SKILLS_L=$?
node "${WORK}/extract/package/bin/wxsource.mjs" kanxue list --pages 1 > "${WORK}/out/wxsource.json" 2>"${WORK}/out/wxsource.err"
WX=$?
set -e
echo "npx_dry_rc=${NPX_DRY} npx_cursor_rc=${NPX_CUR} skills_list_rc=${SKILLS_L} wxsource_rc=${WX}"
# world-state from npx cursor install
CURSOR_N=$(find "${WORK}/user/.cursor/rules" -name '*.mdc' 2>/dev/null | wc -l | tr -d ' ')
echo "npx_cursor_mdc=${CURSOR_N}"
# restart the already-built image and re-check identity
cd -- "${PROJECT_DIR}"
docker compose down
docker compose up -d --wait
LIVE=$(docker inspect --format '{{.Image}}' revskillsrepro-app-1)
FROZEN=$(cat "${WORK}/out/image.id")
echo "restart_live=${LIVE}"
echo "restart_frozen=${FROZEN}"
docker compose exec -T app node vendor/rev-skills/validate.mjs
chmod +x "${WORK}/harness/verify-prove-llm.sh"
set +e
LLM_RC=0
if [[ -f ~/.ssh/bytellm ]]; then
  BYTELLM_BASE_URL=http://127.0.0.1:4000/v1 BYTELLM_KEY_FILE=${HOME}/.ssh/bytellm BYTELLM_KEY_LINE=11 BYTELLM_MODEL=qwen3-max SKILL_ROOT="${WORK}/extract/package" "${WORK}/harness/verify-prove-llm.sh" | tee "${WORK}/out/llm.log"
  LLM_RC=${PIPESTATUS[0]}
  echo "llm_rc=${LLM_RC}"
else
  echo 'LLM_SKIP no ~/.ssh/bytellm' | tee "${WORK}/out/llm.log"
fi
fail=0
[[ "${PROVE_RC}" -eq 0 ]] || fail=1
[[ "${NPX_DRY}" -eq 0 ]] || fail=1
[[ "${NPX_CUR}" -eq 0 ]] || fail=1
[[ "${SKILLS_L}" -eq 0 ]] || fail=1
[[ "${WX}" -eq 0 ]] || fail=1
[[ "${LLM_RC}" -eq 0 ]] || fail=1
echo PROVE_REMOTE_DONE
exit "${fail}"
REMOTE
}

main "$@"
