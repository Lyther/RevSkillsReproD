#!/usr/bin/env bash
#
# probe-llm.sh — list ByteLLM model ids. Never prints keys.
#
# Usage: probe-llm.sh
#
# Env:
#   BYTELLM_BASE_URL   default http://127.0.0.1:4000/v1
#   BYTELLM_KEY_FILE   default ~/.ssh/bytellm (client). Do not use ByteLLM/.env.
#   BYTELLM_KEY_LINE   default 11
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/bytellm-key.sh"

BYTELLM_BASE_URL="${BYTELLM_BASE_URL:-http://127.0.0.1:4000/v1}"
BYTELLM_KEY_LINE="${BYTELLM_KEY_LINE:-11}"
BYTELLM_KEY_FILE="$(bytellm_default_key_file)"

log() { printf '%s [%s] %s\n' "$(date -Iseconds)" "${SCRIPT_NAME}" "$*" >&2; }
die() {
    log "ERROR: $*"
    exit 1
}

cleanup() {
    local exit_code=$?
    [[ -n "${HEADER:-}" ]] && rm -f -- "${HEADER}"
    [[ -n "${BODY:-}" ]] && rm -f -- "${BODY}"
    exit "${exit_code}"
}
trap cleanup EXIT

main() {
    command -v curl >/dev/null 2>&1 || die "curl is required"
    command -v python3 >/dev/null 2>&1 || die "python3 is required"
    [[ -f "${BYTELLM_KEY_FILE}" ]] || die "missing ${BYTELLM_KEY_FILE}"

    local key
    key="$(bytellm_read_key "${BYTELLM_KEY_FILE}" "${BYTELLM_KEY_LINE}")" || die "empty key on line ${BYTELLM_KEY_LINE} of ${BYTELLM_KEY_FILE}"

    HEADER="$(mktemp)"
    BODY="$(mktemp)"
    chmod 600 "${HEADER}" "${BODY}"
    # Keep the token off curl argv.
    printf 'Authorization: Bearer %s\n' "${key}" >"${HEADER}"
    key=""
    unset key

    local code
    code="$(curl -sS --noproxy '*' -o "${BODY}" -w '%{http_code}' --connect-timeout 5 \
        -H "@${HEADER}" \
        "${BYTELLM_BASE_URL}/models")" || true
    if [[ "${code}" != "200" ]]; then
        die "ByteLLM ${BYTELLM_BASE_URL}/models HTTP ${code}"
    fi
    python3 - "${BODY}" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
ids = [m.get("id") for m in (data.get("data") or []) if m.get("id")]
print(f"bytellm_models {len(ids)}")
wanted = ("qwen3-max", "openai_qwen3-max-preview")
found = [i for i in ids if i in wanted]
if not found:
    raise SystemExit("qwen3-max not in catalog")
print(f"qwen3_max_ok {' '.join(found)}")
print("catalog_note GET /v1/models is public on this gateway; chat proves the key")
for model_id in ids[:12]:
    print(f"  {model_id}")
PY
}

main "$@"
